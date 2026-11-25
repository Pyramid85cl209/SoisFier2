-- Test de la migration ep01b_rappels_secrets (EP-01 lot B), à coller dans l'éditeur SQL de Supabase (le fichier contient la migration A, la migration B, puis les cas : il se lance seul).
-- Tout se passe dans une transaction annulée : famille, enfants, utilisateurs, appareils et abonnements fictifs, rien n'est conservé.
-- Résultat : une ligne d'erreur « RESULT: … ». Le dernier cas lit cron.job : la commande doit avoir été remplacée par la migration.
begin;
-- Migration A complète d'abord (dans la même transaction), puis la migration B, puis les cas.
-- EP-01 lot A : plusieurs familles (ADR-54), appareil commun à plusieurs enfants (ADR-52), code de l'enfant (ADR-53).
-- Additions seulement : compatible avec la version 32 de l'application en ligne (les anciennes signatures restent, rien n'est supprimé ;
-- les nouvelles ont un paramètre d'enfant ou de famille sans valeur par défaut, pour ne jamais être ambiguës avec les anciennes).
-- Les retraits (colonne child_devices.child_id, anciennes signatures) sont dans supabase/editeur-sql/ep01_retraits.sql (éditeur SQL, ADR-07).
-- À tester dans une transaction annulée : supabase/tests/ep01a_familles_appareils_test.sql.

------------------------------------------------------------------------------------------------------------------------
-- 1. Familles : créateur et limite de 3 familles créées (DEC-19)
------------------------------------------------------------------------------------------------------------------------
alter table public.families add column if not exists created_by uuid references auth.users(id) on delete set null;
-- Familles existantes : créateur = Parent inscrit le plus tôt (hypothèse : create_family inscrit le créateur en premier)
update public.families f set created_by = (
  select m.user_id from public.family_members m where m.family_id = f.id and m.role = 'parent' order by m.created_at limit 1)
where f.created_by is null;

-- Ancienne signature : comportement inchangé (renvoie la première famille du compte), mais le créateur est noté
create or replace function public.create_family(p_name text, p_display_name text, p_week_start smallint default 1,
  p_weekend smallint[] default '{6,7}', p_timezone text default 'Europe/Paris')
returns uuid language plpgsql security definer set search_path = '' as $$
declare fid uuid; uid uuid := auth.uid(); ws smallint; we smallint[]; tz text;
begin
  if uid is null then raise exception 'SF:login_required'; end if;
  select family_id into fid from public.family_members where user_id = uid order by created_at limit 1;
  if fid is not null then return fid; end if;
  ws := case when p_week_start between 1 and 7 then p_week_start else 1 end;
  we := case when p_weekend is not null and p_weekend <@ array[1,2,3,4,5,6,7]::smallint[] and cardinality(p_weekend) <= 3
             then coalesce((select array_agg(distinct x order by x) from unnest(p_weekend) x), '{}') else '{6,7}' end;
  tz := case when private.valid_tz(p_timezone) then p_timezone else 'Europe/Paris' end;
  insert into public.families(name, week_start, weekend_days, timezone, created_by)
  values (coalesce(nullif(trim(p_name), ''), 'Ma famille'), ws, we, tz, uid) returning id into fid;
  insert into public.family_members(family_id, user_id, role, display_name) values (fid, uid, 'parent', nullif(trim(p_display_name), ''));
  return fid;
end $$;

-- Nouvelle signature : p_another = false : comme avant ; true : une autre famille, 3 créées au plus (SF:family_limit)
create or replace function public.create_family(p_name text, p_display_name text, p_week_start smallint,
  p_weekend smallint[], p_timezone text, p_another boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare fid uuid; uid uuid := auth.uid(); ws smallint; we smallint[]; tz text;
begin
  if uid is null then raise exception 'SF:login_required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('create_family:' || uid::text, 0));
  if not coalesce(p_another, false) then
    select family_id into fid from public.family_members where user_id = uid order by created_at limit 1;
    if fid is not null then return fid; end if;
  elsif (select count(*) from public.families where created_by = uid) >= 3 then
    raise exception 'SF:family_limit';
  end if;
  ws := case when p_week_start between 1 and 7 then p_week_start else 1 end;
  we := case when p_weekend is not null and p_weekend <@ array[1,2,3,4,5,6,7]::smallint[] and cardinality(p_weekend) <= 3
             then coalesce((select array_agg(distinct x order by x) from unnest(p_weekend) x), '{}') else '{6,7}' end;
  tz := case when private.valid_tz(p_timezone) then p_timezone else 'Europe/Paris' end;
  insert into public.families(name, week_start, weekend_days, timezone, created_by)
  values (coalesce(nullif(trim(p_name), ''), 'Ma famille'), ws, we, tz, uid) returning id into fid;
  insert into public.family_members(family_id, user_id, role, display_name) values (fid, uid, 'parent', nullif(trim(p_display_name), ''));
  return fid;
end $$;
revoke all on function public.create_family(text, text, smallint, smallint[], text, boolean) from public, anon;
grant execute on function public.create_family(text, text, smallint, smallint[], text, boolean) to authenticated;

------------------------------------------------------------------------------------------------------------------------
-- 2. Appareil commun : table de liaison appareil-enfants (ADR-52)
------------------------------------------------------------------------------------------------------------------------
create table if not exists public.child_device_children (
  device_id uuid not null references public.child_devices(id) on delete cascade,
  child_id uuid not null,
  family_id uuid not null,
  primary key (device_id, child_id),
  foreign key (child_id, family_id) references public.children(id, family_id) on delete cascade
);
create index if not exists child_device_children_child_idx on public.child_device_children(child_id);
alter table public.child_device_children enable row level security;
create policy device_children_select on public.child_device_children for select using ((select private.is_member(family_id)));
revoke insert, update, delete, truncate on public.child_device_children from anon, authenticated;
revoke all on public.child_device_children from anon;
grant select on public.child_device_children to soisfier_sauvegarde;

-- Remplissage depuis l'existant
insert into public.child_device_children(device_id, child_id, family_id)
select d.id, d.child_id, d.family_id from public.child_devices d where d.child_id is not null
on conflict do nothing;

-- Dès maintenant, child_devices.child_id n'est plus la source (il reste rempli avec le premier enfant jusqu'au retrait) : facultatif, sans suppression en cascade
-- (la colonne et la contrainte sont retirées par supabase/editeur-sql/ep01_retraits.sql)
alter table public.child_devices alter column child_id drop not null;
alter table public.child_devices drop constraint if exists child_devices_child_id_family_id_fkey;
-- Lignes « Mode enfant ici » (ADR-57) : posées ici, utilisées par le lot rappels
alter table public.child_devices add column if not exists mode_here boolean not null default false;
alter table public.child_devices add column if not exists here_endpoint text;
update public.child_devices set mode_here = true where nullif(btrim(label), '') is not null and not mode_here;

-- L'appareil qui perd son dernier enfant est supprimé (F03-09 CA9 : il reste pour l'enfant restant)
create or replace function private.device_without_child() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.child_devices d where d.id = old.device_id
    and not exists (select 1 from public.child_device_children l where l.device_id = d.id);
  return old;
end $$;
drop trigger if exists child_device_children_empty on public.child_device_children;
create trigger child_device_children_empty after delete on public.child_device_children
  for each row execute function private.device_without_child();

-- Codes d'appareil : plusieurs enfants
alter table public.child_device_codes add column if not exists child_ids uuid[];

-- Ancienne signature : un seul enfant relié (jeton, liaison)
create or replace function private.device_child(p_token text, out device_id uuid, out child_id uuid, out family_id uuid)
returns record language plpgsql security definer set search_path = '' as $$
declare seen timestamptz; n int;
begin
  select d.id, d.family_id, coalesce(d.last_seen, d.created_at) into device_id, family_id, seen
  from public.child_devices d where d.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if device_id is null then raise exception 'SF:device_unknown'; end if;
  if seen < now() - interval '3 months' then raise exception 'SF:device_expired'; end if;
  select count(*), min(l.child_id::text)::uuid into n, child_id from public.child_device_children l where l.device_id = device_child.device_id;
  if n <> 1 then raise exception 'SF:device_unknown'; end if;
  update public.child_devices set last_seen = now() where id = device_id;
end $$;

-- Nouvelle signature : enfant facultatif ; obligatoire et relié sur un appareil de plusieurs enfants
create or replace function private.device_child(p_token text, p_child uuid, out device_id uuid, out child_id uuid, out family_id uuid)
returns record language plpgsql security definer set search_path = '' as $$
declare seen timestamptz; n int;
begin
  select d.id, d.family_id, coalesce(d.last_seen, d.created_at) into device_id, family_id, seen
  from public.child_devices d where d.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if device_id is null then raise exception 'SF:device_unknown'; end if;
  if seen < now() - interval '3 months' then raise exception 'SF:device_expired'; end if;
  select count(*) into n from public.child_device_children l where l.device_id = device_child.device_id;
  if p_child is null then
    if n <> 1 then raise exception 'SF:device_unknown'; end if;
    select l.child_id into child_id from public.child_device_children l where l.device_id = device_child.device_id;
  else
    if not exists (select 1 from public.child_device_children l where l.device_id = device_child.device_id and l.child_id = p_child) then
      raise exception 'SF:device_unknown';
    end if;
    child_id := p_child;
  end if;
  update public.child_devices set last_seen = now() where id = device_id;
end $$;

-- Appareil sans enfant précis (abonnement aux rappels, liste des enfants)
create or replace function private.device_of(p_token text, out device_id uuid, out family_id uuid)
returns record language plpgsql security definer set search_path = '' as $$
declare seen timestamptz;
begin
  select d.id, d.family_id, coalesce(d.last_seen, d.created_at) into device_id, family_id, seen
  from public.child_devices d where d.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if device_id is null then raise exception 'SF:device_unknown'; end if;
  if seen < now() - interval '3 months' then raise exception 'SF:device_expired'; end if;
  update public.child_devices set last_seen = now() where id = device_id;
end $$;

-- Relier avec un code (anon) : tous les enfants du code encore présents
create or replace function public.child_pair(p_code text, p_label text default null)
returns json language plpgsql security definer set search_path = '' as $$
declare rec record; tok text; ck text := private.client_key(); did uuid; first_child uuid;
begin
  perform private.code_guard('pair', ck);
  select * into rec from public.child_device_codes where code = upper(trim(p_code)) and expires_at > now();
  if not found then
    perform private.code_fail('pair', ck);
    return json_build_object('error', 'bad_code');
  end if;
  tok := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.child_devices(child_id, family_id, token_hash, label)
  values (rec.child_id, rec.family_id, encode(extensions.digest(tok, 'sha256'), 'hex'), nullif(left(trim(p_label), 60), '')) returning id into did;
  insert into public.child_device_children(device_id, child_id, family_id)
  select did, c.id, c.family_id from public.children c
  where c.family_id = rec.family_id and c.id = any(coalesce(rec.child_ids, array[rec.child_id]));
  delete from public.child_devices where id = did and not exists (select 1 from public.child_device_children where device_id = did);
  delete from public.child_device_codes where code = rec.code;
  select l.child_id into first_child from public.child_device_children l where l.device_id = did order by l.child_id limit 1;
  if first_child is null then return json_build_object('error', 'bad_code'); end if;
  return json_build_object('token', tok, 'child_id', coalesce(rec.child_id, first_child),
    'child_ids', (select json_agg(l.child_id) from public.child_device_children l where l.device_id = did));
end $$;

-- Code d'appareil pour plusieurs enfants (Parent seul, enfants de la même famille)
create or replace function public.create_child_code(p_child uuid, p_children uuid[])
returns text language plpgsql security definer set search_path = '' as $$
declare fid uuid; c text; ids uuid[];
begin
  select family_id into fid from public.children where id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:device_parent_only'; end if;
  ids := coalesce((select array_agg(distinct x.id) from public.children x
                   where x.family_id = fid and x.id = any(coalesce(p_children, array[]::uuid[]) || p_child)), array[p_child]);
  delete from public.child_device_codes where child_id = any(ids) or expires_at < now();
  c := private.random_code(6);
  insert into public.child_device_codes(code, child_id, family_id, expires_at, child_ids)
  values (c, p_child, fid, now() + interval '15 minutes', ids);
  return c;
end $$;
revoke all on function public.create_child_code(uuid, uuid[]) from public, anon;
grant execute on function public.create_child_code(uuid, uuid[]) to authenticated;

-- Ancienne signature de « Mode enfant ici » : la liaison remplace child_id
create or replace function public.child_pair_here(p_child uuid, p_label text default null)
returns json language plpgsql security definer set search_path = '' as $$
declare fid uuid; tok text; did uuid;
begin
  select c.family_id into fid from public.children c where c.id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:device_parent_only'; end if;
  tok := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.child_devices(child_id, family_id, token_hash, label, mode_here)
  values (p_child, fid, encode(extensions.digest(tok, 'sha256'), 'hex'), nullif(left(trim(p_label), 60), ''), true) returning id into did;
  insert into public.child_device_children(device_id, child_id, family_id) values (did, p_child, fid);
  return json_build_object('token', tok, 'child_id', p_child);
end $$;

-- Mode enfant ici pour plusieurs enfants ; la ligne du téléphone (p_token) est réutilisée et ses enfants mis à jour (R03-08)
create or replace function public.child_pair_here(p_child uuid, p_label text, p_children uuid[], p_token text, p_endpoint text)
returns json language plpgsql security definer set search_path = '' as $$
declare fid uuid; tok text; did uuid; ids uuid[]; ep text := nullif(left(btrim(coalesce(p_endpoint, '')), 1000), '');
begin
  select c.family_id into fid from public.children c where c.id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:device_parent_only'; end if;
  ids := coalesce((select array_agg(distinct x.id) from public.children x
                   where x.family_id = fid and x.id = any(coalesce(p_children, array[]::uuid[]) || p_child)), array[p_child]);
  if p_token is not null then
    select d.id into did from public.child_devices d
    where d.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and d.family_id = fid and d.mode_here;
  end if;
  if did is not null then
    tok := p_token;
    insert into public.child_device_children(device_id, child_id, family_id)
    select did, x, fid from unnest(ids) x on conflict do nothing;
    delete from public.child_device_children where device_id = did and child_id <> all(ids);
    update public.child_devices set here_endpoint = coalesce(ep, here_endpoint), last_seen = now() where id = did;
  else
    tok := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.child_devices(child_id, family_id, token_hash, label, mode_here, here_endpoint)
    values (p_child, fid, encode(extensions.digest(tok, 'sha256'), 'hex'), nullif(left(trim(p_label), 60), ''), true, ep) returning id into did;
  end if;
  insert into public.child_device_children(device_id, child_id, family_id)
  select did, x, fid from unnest(ids) x on conflict do nothing;
  return json_build_object('token', tok, 'child_id', p_child, 'child_ids', to_json(ids));
end $$;
revoke all on function public.child_pair_here(uuid, text, uuid[], text, text) from public, anon;
grant execute on function public.child_pair_here(uuid, text, uuid[], text, text) to authenticated;

------------------------------------------------------------------------------------------------------------------------
-- 3. Code de l'enfant : empreinte calculée par le téléphone du Parent, table hors API (ADR-53)
------------------------------------------------------------------------------------------------------------------------
create table if not exists private.child_codes (
  child_id uuid primary key,
  family_id uuid not null,
  verifier jsonb not null,
  updated_at timestamptz not null default now(),
  foreign key (child_id, family_id) references public.children(id, family_id) on delete cascade
);
alter table private.child_codes enable row level security;
grant select on private.child_codes to soisfier_sauvegarde;

create or replace function public.set_child_code(p_child uuid, p_verifier jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare fid uuid;
begin
  select family_id into fid from public.children where id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:device_parent_only'; end if;
  if p_verifier is null or jsonb_typeof(p_verifier) <> 'object' or not (p_verifier ? 'salt' and p_verifier ? 'hash')
     or length(p_verifier::text) > 400 then raise exception 'SF:bad_code'; end if;
  insert into private.child_codes(child_id, family_id, verifier) values (p_child, fid, p_verifier)
  on conflict (child_id) do update set verifier = excluded.verifier, updated_at = now();
end $$;
revoke all on function public.set_child_code(uuid, jsonb) from public, anon;
grant execute on function public.set_child_code(uuid, jsonb) to authenticated;

------------------------------------------------------------------------------------------------------------------------
-- 4. Fonctions de l'enfant : corps commun, enfant facultatif
------------------------------------------------------------------------------------------------------------------------
create or replace function private.child_state_body(p_child uuid, p_family uuid)
returns json language plpgsql security definer set search_path = '' as $$
declare today date; res json;
begin
  today := private.family_today(p_family);
  perform private.close_periods(p_child);
  select json_build_object(
    'today', today,
    'premium', private.is_premium(p_family),
    'child', (select row_to_json(c) from (select id, name, emoji, color, garden_start from public.children where id = p_child) c),
    'routines', coalesce((select json_agg(r order by r.position, r.created_at) from
        (select id, title, emoji, place, moment, stars, days, is_bonus, timer_minutes, position, created_at, kind, start_day, end_day, holiday_period_id,
           coalesce((select json_agg(json_build_object('valid_from', s.valid_from, 'days', s.days, 'is_bonus', s.is_bonus, 'stars', s.stars) order by s.valid_from)
                     from public.routine_settings s where s.routine_id = routines.id), '[]'::json) as settings
         from public.routines where child_id = p_child and active and (kind = 'regular' or end_day >= today - 2)) r), '[]'::json),
    'holidays', coalesce((select json_agg(h order by h.start_day) from
        (select p.id, p.name, p.start_day, p.end_day,
           coalesce((select json_agg(json_build_object('routine_id', o.routine_id, 'status', o.status, 'days', o.days, 'stars', o.stars))
                     from public.holiday_overrides o where o.period_id = p.id), '[]'::json) as overrides
         from public.holiday_periods p where p.child_id = p_child and p.active and p.end_day >= today - 60) h), '[]'::json),
    'completions', coalesce((select json_agg(x) from
        (select routine_id, day, stars, source, validated_at is not null as validated,
           case when validated_at is null then null when validated_by is null then 'auto'
                when exists (select 1 from public.family_members m where m.family_id = p_family and m.user_id = validated_by) then 'member' end as validated_label,
           case when validated_at is not null and validated_by is not null
                then (select m.relation_key from public.family_members m where m.family_id = p_family and m.user_id = validated_by) end as validated_rel,
           case when validated_at is not null and validated_by is not null
                then (select nullif(btrim(m.relation), '') from public.family_members m where m.family_id = p_family and m.user_id = validated_by and m.relation_key is null) end as validated_custom
         from public.completions where child_id = p_child and day >= today - 60) x), '[]'::json),
    'oneoff_done', (select count(*) from public.completions c join public.routines r on r.id = c.routine_id
                    where c.child_id = p_child and r.kind = 'oneoff' and c.validated_at is not null),
    'rewards', coalesce((select json_agg(w order by w.cost) from
        (select id, title, emoji, tier, event_date, place, private.reward_cost(rw, p_child) as cost
         from public.rewards rw where family_id = p_family and active and (child_id is null or child_id = p_child)
           and (event_date is null or event_date >= today)) w), '[]'::json),
    'redemptions', coalesce((select json_agg(z order by z.created_at desc) from
        (select id, title, emoji, cost, created_at from public.redemptions where child_id = p_child
         order by created_at desc limit 30) z), '[]'::json),
    'penalties', coalesce((select json_agg(p order by p.created_at desc) from
        (select id, title, emoji, stars, created_at from public.penalty_events where child_id = p_child
         order by created_at desc limit 30) p), '[]'::json),
    'badges', coalesce((select json_agg(b.badge_key) from public.child_badges b where b.child_id = p_child), '[]'::json),
    'badges_new', coalesce((select json_agg(b.badge_key) from public.child_badges b where b.child_id = p_child and b.shown_at is null), '[]'::json),
    'badge_dates', coalesce((select json_object_agg(b.badge_key, b.earned_at) from public.child_badges b where b.child_id = p_child), '{}'::json),
    'stats', (select row_to_json(s) from (select earned, done_count, pending_stars, pending_count, spent, redeemed_count, broken, broken_count
              from public.child_stats where child_id = p_child) s),
    'garden', private.garden_payload(p_child),
    'family', (select json_build_object('week_start', week_start, 'weekend_days', weekend_days, 'timezone', timezone) from public.families where id = p_family)
  ) into res;
  return res;
end $$;

-- Ancienne signature : un appareil d'un seul enfant
create or replace function public.child_state(p_token text)
returns json language plpgsql security definer set search_path = '' as $$
declare d record;
begin
  select * into d from private.device_child(p_token);
  return private.child_state_body(d.child_id, d.family_id);
end $$;

-- Nouvelle signature : enfant facultatif ; liste des enfants reliés (prénom, avatar, couleur, empreinte du code) sur un appareil commun
create or replace function public.child_state(p_token text, p_child uuid)
returns json language plpgsql security definer set search_path = '' as $$
declare d record; res jsonb; n int;
begin
  select * into d from private.device_child(p_token, p_child);
  res := private.child_state_body(d.child_id, d.family_id)::jsonb;
  select count(*) into n from public.child_device_children l where l.device_id = d.device_id;
  return (res || jsonb_build_object(
    'common', n > 1,
    'device_children', case when n > 1 then coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'emoji', c.emoji, 'color', c.color, 'verifier', k.verifier) order by c.position, c.created_at)
      from public.child_device_children l join public.children c on c.id = l.child_id
      left join private.child_codes k on k.child_id = c.id where l.device_id = d.device_id), '[]'::jsonb) else '[]'::jsonb end))::json;
end $$;

-- Nouvelles signatures des autres fonctions : p_child en 2e paramètre, sans valeur par défaut
create or replace function public.child_toggle(p_token text, p_child uuid, p_routine uuid, p_day date, p_done boolean, p_source text default 'child')
returns json language plpgsql security definer set search_path = '' as $$
declare d record; today date; r record;
begin
  select * into d from private.device_child(p_token, p_child);
  today := private.family_today(d.family_id);
  select * into r from public.routines where id = p_routine and child_id = d.child_id and active;
  if not found then raise exception 'SF:routine_not_found'; end if;
  if p_day < today - 2 or p_day > today then raise exception 'SF:day_locked'; end if;
  if r.kind = 'oneoff' and (p_day < r.start_day or p_day > r.end_day) then raise exception 'SF:oneoff_out_of_range'; end if;
  if r.holiday_period_id is not null and not exists (select 1 from public.holiday_periods p
      where p.id = r.holiday_period_id and p.active and p_day between p.start_day and p.end_day) then
    raise exception 'SF:holiday_out_of_range';
  end if;
  if p_done then
    perform set_config('sf.via_device', 'on', true);
    insert into public.completions(family_id, child_id, routine_id, day, source)
    values (d.family_id, d.child_id, p_routine, p_day, case when p_source in ('child','timer') then p_source else 'child' end)
    on conflict (routine_id, day) do nothing;
    perform set_config('sf.via_device', '', true);
  else
    if exists (select 1 from public.completions where routine_id = p_routine and day = p_day and validated_at is not null) then
      raise exception 'SF:validated_by_parent';
    end if;
    delete from public.completions where routine_id = p_routine and day = p_day and child_id = d.child_id and validated_at is null;
  end if;
  return json_build_object('ok', true);
end $$;

create or replace function public.child_redeem(p_token text, p_child uuid, p_reward uuid)
returns json language plpgsql security definer set search_path = '' as $$
declare d record; w public.rewards; price int;
begin
  select * into d from private.device_child(p_token, p_child);
  select * into w from public.rewards where id = p_reward and family_id = d.family_id and active
    and (child_id is null or child_id = d.child_id);
  if not found then raise exception 'SF:reward_not_found'; end if;
  price := private.reward_cost(w, d.child_id);
  if coalesce(private.balance(d.child_id), 0) < price then raise exception 'SF:not_enough_stars'; end if;
  perform set_config('sf.via_device', 'on', true);
  insert into public.redemptions(family_id, child_id, reward_id, title, emoji, cost)
  values (d.family_id, d.child_id, w.id, w.title, w.emoji, price);
  perform set_config('sf.via_device', '', true);
  return json_build_object('ok', true);
end $$;

create or replace function public.child_badges_seen(p_token text, p_child uuid, p_keys text[])
returns void language plpgsql security definer set search_path = '' as $$
declare d record;
begin
  select * into d from private.device_child(p_token, p_child);
  update public.child_badges set shown_at = now() where child_id = d.child_id and badge_key = any(p_keys) and shown_at is null;
end $$;

-- Rappels de l'appareil : un abonnement par appareil, sans enfant précis (ADR-55)
create or replace function public.child_push_subscribe(p_token text, p_endpoint text, p_p256dh text, p_auth text, p_times text[], p_locale text default 'fr')
returns void language plpgsql security definer set search_path = '' as $$
declare d record; loc text := private.valid_locale(p_locale);
begin
  select * into d from private.device_of(p_token);
  insert into public.push_subscriptions(family_id, user_id, child_device_id, endpoint, p256dh, auth, reminder_times, locale)
  values (d.family_id, null, d.device_id, p_endpoint, p_p256dh, p_auth, p_times, loc)
  on conflict (endpoint) do update set family_id = excluded.family_id, user_id = null,
    child_device_id = excluded.child_device_id, p256dh = excluded.p256dh, auth = excluded.auth, reminder_times = excluded.reminder_times, locale = excluded.locale;
end $$;

-- Droits : mêmes que les fonctions d'origine (anon et comptes connectés pour les fonctions de l'enfant)
revoke all on function public.child_state(text, uuid) from public;
revoke all on function public.child_toggle(text, uuid, uuid, date, boolean, text) from public;
revoke all on function public.child_redeem(text, uuid, uuid) from public;
revoke all on function public.child_badges_seen(text, uuid, text[]) from public;
grant execute on function public.child_state(text, uuid) to anon, authenticated;
grant execute on function public.child_toggle(text, uuid, uuid, date, boolean, text) to anon, authenticated;
grant execute on function public.child_redeem(text, uuid, uuid) to anon, authenticated;
grant execute on function public.child_badges_seen(text, uuid, text[]) to anon, authenticated;

-- EP-01 lot B : rappels regroupés (ADR-55), rappel à l'heure d'une routine (ADR-57), secrets hors base (ADR-45, DT11-09).
-- Additions seulement : aucune ligne de private.config n'est supprimée ici (supabase/editeur-sql/ep01_retraits.sql, après la mise en ligne).
-- ORDRE DE MISE EN LIGNE : 1) secrets VAPID_PRIVATE_KEY et VAPID_SUBJECT posés dans les secrets de la fonction Edge ;
-- 2) fonction send-reminders redéployée (elle lit ses clés dans ses secrets, sinon dans la réponse, et comprend les deux formats) ;
-- 3) cette migration ; 4) plus tard, retraits (éditeur SQL). Après l'étape 3, reminders_due ne renvoie plus de clé privée.
-- À tester dans une transaction annulée : supabase/tests/ep01b_rappels_secrets_test.sql.

------------------------------------------------------------------------------------------------------------------------
-- 1. Rappel à l'heure d'une routine : donnée, contrainte, Premium (ADR-57)
------------------------------------------------------------------------------------------------------------------------
alter table public.routines add column if not exists remind_at time;
alter table public.routines drop constraint if exists routines_remind_at_check;
alter table public.routines add constraint routines_remind_at_check check (
  remind_at is null or (kind = 'regular'
    and extract(minute from remind_at)::int in (0, 15, 30, 45) and extract(second from remind_at) = 0
    and remind_at >= time '05:00' and remind_at <= time '23:45'));

create or replace function private.remind_guard() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.remind_at is null then return new; end if;
  if tg_op = 'UPDATE' and new.remind_at is not distinct from old.remind_at then return new; end if;
  if not private.is_premium(new.family_id) then raise exception 'SF:premium_reminder'; end if;
  return new;
end $$;
drop trigger if exists routines_remind_premium on public.routines;
create trigger routines_remind_premium before insert or update of remind_at on public.routines
  for each row execute function private.remind_guard();

------------------------------------------------------------------------------------------------------------------------
-- 2. Abonnements : plusieurs familles, lignes « Mode enfant ici » (ADR-55, ADR-57)
------------------------------------------------------------------------------------------------------------------------
-- Un membre qui quitte une famille : l'abonnement passe à une autre famille du compte s'il en reste une, sinon il est supprimé (C-20)
create or replace function private.member_left() returns trigger language plpgsql security definer set search_path = '' as $$
declare other uuid;
begin
  select m.family_id into other from public.family_members m where m.user_id = old.user_id and m.family_id <> old.family_id order by m.created_at limit 1;
  if other is not null then
    update public.push_subscriptions set family_id = other where family_id = old.family_id and user_id = old.user_id;
  else
    delete from public.push_subscriptions where family_id = old.family_id and user_id = old.user_id;
  end if;
  return old;
end $$;

-- Abonnement de l'adulte, avec les jetons « Mode enfant ici » gardés sur ce téléphone : leur adresse d'envoi est notée (ADR-57)
create or replace function public.parent_push_subscribe(p_family uuid, p_endpoint text, p_p256dh text, p_auth text, p_times text[], p_locale text, p_tokens text[])
returns void language plpgsql security definer set search_path = '' as $$
declare loc text := private.valid_locale(p_locale);
begin
  if not private.is_member(p_family) then raise exception 'SF:access_denied'; end if;
  insert into public.push_subscriptions(family_id, user_id, child_device_id, endpoint, p256dh, auth, reminder_times, locale)
  values (p_family, auth.uid(), null, p_endpoint, p_p256dh, p_auth, p_times, loc)
  on conflict (endpoint) do update set family_id = excluded.family_id, user_id = excluded.user_id,
    child_device_id = null, p256dh = excluded.p256dh, auth = excluded.auth, reminder_times = excluded.reminder_times, locale = excluded.locale;
  update public.child_devices d set here_endpoint = p_endpoint
  where d.mode_here and d.token_hash in (select encode(extensions.digest(t, 'sha256'), 'hex') from unnest(coalesce(p_tokens, array[]::text[])) t)
    and exists (select 1 from public.family_members m where m.family_id = d.family_id and m.user_id = auth.uid());
end $$;
revoke all on function public.parent_push_subscribe(uuid, text, text, text, text[], text, text[]) from public, anon;
grant execute on function public.parent_push_subscribe(uuid, text, text, text, text[], text, text[]) to authenticated;

------------------------------------------------------------------------------------------------------------------------
-- 3. Secret de la tâche dans Vault (ADR-45) : copie du secret actuel, la valeur ne transite par aucun client
------------------------------------------------------------------------------------------------------------------------
do $v$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_secret') then
    perform vault.create_secret((select value from private.config where key = 'cron_secret'), 'cron_secret', 'Secret de la tâche des rappels (ADR-45)');
  end if;
end $v$;

select cron.alter_job(
  (select jobid from cron.job where jobname = 'soisfier-reminders'),
  command := $cmd$
  select net.http_post(
    url := 'https://mlgrtpuvnjgkjnmhnlfg.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
  $cmd$);

------------------------------------------------------------------------------------------------------------------------
-- 4. reminders_due : familles du compte, appareil commun, rappels de routine, plus aucune clé renvoyée
--    Lecture seule : aucune écriture, aucun appel réseau (l'envoi est fait par send-reminders).
--    Formats : résumé adulte {kind:'parent', children:[{name, done, total, pending, family?}]} ; résumé appareil
--    {kind:'child', left} (un enfant) ou {kind:'child', kids:[{name, left}]} (appareil commun) ;
--    rappel de routine {kind:'routine', mode:'device'|'here', child, common, at, routines:[{title, emoji}]}.
------------------------------------------------------------------------------------------------------------------------
create or replace function public.reminders_due(p_secret text)
returns json language plpgsql security definer set search_path = '' as $$
declare sec text; sums jsonb; routs jsonb;
begin
  select decrypted_secret into sec from vault.decrypted_secrets where name = 'cron_secret';
  if p_secret is null or sec is null or p_secret is distinct from sec then raise exception 'SF:access_denied'; end if;

  with fam as (
    select f.id, f.name, f.timezone as tz, (now() at time zone f.timezone) as now_l from public.families f
  ),
  due as (
    select s.* from public.push_subscriptions s join fam on fam.id = s.family_id
    where (s.child_device_id is not null
           or exists (select 1 from public.family_members m where m.family_id = s.family_id and m.user_id = s.user_id))
      and exists (select 1 from unnest(s.reminder_times) t
                  where t ~ '^\d{2}:\d{2}$' and fam.now_l::time >= t::time and fam.now_l::time < t::time + interval '15 minutes')
  ),
  cov as (
    select d.id as sub_id, c.id as child_id from due d
      join public.family_members m on m.user_id = d.user_id join public.children c on c.family_id = m.family_id
    where d.child_device_id is null
    union all
    select d.id, l.child_id from due d join public.child_device_children l on l.device_id = d.child_device_id
    where d.child_device_id is not null
  ),
  todo as (
    select c.id as child_id, c.family_id, c.name, fc.name as fam_name,
      exists (select 1 from public.pauses p where p.child_id = c.id and fc.now_l::date between p.start_day and p.end_day) as paused,
      (select count(*) from private.routine_rules(c.id, fc.now_l::date) rr where not rr.is_bonus) + o.total as total,
      (select count(*) from private.routine_rules(c.id, fc.now_l::date) rr where not rr.is_bonus
        and exists (select 1 from public.completions x where x.routine_id = rr.routine_id and x.day = fc.now_l::date)) + o.done as done,
      (select count(*) from public.completions x where x.child_id = c.id and x.validated_at is null) as pending
    from public.children c
    join fam fc on fc.id = c.family_id
    cross join lateral (
      select count(*) as total,
             count(*) filter (where exists (select 1 from public.completions x where x.routine_id = r.id and x.day = fc.now_l::date)) as done
      from public.routines r
      where r.child_id = c.id and r.kind = 'oneoff' and not r.is_bonus
        and case when r.ended_at is not null then (r.ended_at at time zone fc.tz)::date > fc.now_l::date else r.active end
        and fc.now_l::date between r.start_day and r.end_day
        and (exists (select 1 from public.completions x where x.routine_id = r.id and x.day = fc.now_l::date)
             or (fc.now_l::date = r.end_day and not exists (select 1 from public.completions x where x.routine_id = r.id)))
    ) o
    where exists (select 1 from cov where cov.child_id = c.id)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'endpoint', d.endpoint, 'p256dh', d.p256dh, 'auth', d.auth, 'locale', d.locale,
    'kind', case when d.child_device_id is not null then 'child' else 'parent' end,
    'left', case when d.child_device_id is not null
                  and (select count(*) from public.child_device_children l where l.device_id = d.child_device_id) = 1 then
        (select case when t.paused then null else t.total - t.done end
         from todo t join public.child_device_children l on l.child_id = t.child_id where l.device_id = d.child_device_id) end,
    'kids', case when d.child_device_id is not null
                  and (select count(*) from public.child_device_children l where l.device_id = d.child_device_id) > 1 then
        (select jsonb_agg(jsonb_build_object('name', t.name, 'left', t.total - t.done) order by t.name)
         from todo t join cov on cov.child_id = t.child_id and cov.sub_id = d.id where not t.paused) end,
    'children', case when d.child_device_id is null then
        (select jsonb_agg(jsonb_build_object('name', t.name, 'done', t.done, 'total', t.total, 'pending', t.pending,
            'family', case when (select count(*) from public.family_members m where m.user_id = d.user_id) >= 2 then t.fam_name end)
            order by t.fam_name, t.name)
         from todo t join cov on cov.child_id = t.child_id and cov.sub_id = d.id
         where not t.paused and (t.total > 0 or t.pending > 0)) end
  )), '[]'::jsonb) into sums from due d;

  -- Rappels à l'heure d'une routine (F11-05, R11-10) : routines habituelles Premium dues ce jour, non cochées, enfant hors pause
  with fam as (
    select f.id, (now() at time zone f.timezone) as now_l from public.families f
  ),
  rem as (
    select r.id as rid, r.title, r.emoji, r.remind_at, c.id as child_id, c.name as child_name, c.family_id
    from public.routines r
    join public.children c on c.id = r.child_id
    join fam on fam.id = r.family_id
    where r.kind = 'regular' and r.active and r.remind_at is not null and private.is_premium(r.family_id)
      and (extract(hour from fam.now_l) * 60 + extract(minute from fam.now_l))::int
          between (extract(hour from r.remind_at) * 60 + extract(minute from r.remind_at))::int
              and (extract(hour from r.remind_at) * 60 + extract(minute from r.remind_at))::int + 14
      and not exists (select 1 from public.pauses p where p.child_id = c.id and fam.now_l::date between p.start_day and p.end_day)
      and exists (select 1 from private.routine_rules(c.id, fam.now_l::date) rr where rr.routine_id = r.id)
      and not exists (select 1 from public.completions x where x.routine_id = r.id and x.day = fam.now_l::date)
  ),
  dev as (
    select distinct s.id as sub_id, s.endpoint, s.p256dh, s.auth, s.locale, rem.child_id, 'device'::text as mode,
      (select count(*) from public.child_device_children l2 where l2.device_id = cd.id) > 1 as common
    from rem
    join public.child_device_children l on l.child_id = rem.child_id
    join public.child_devices cd on cd.id = l.device_id and not cd.mode_here
    join public.push_subscriptions s on s.child_device_id = cd.id
  ),
  here as (
    select distinct s.id as sub_id, s.endpoint, s.p256dh, s.auth, s.locale, rem.child_id, 'here'::text as mode, false as common
    from rem
    join public.child_device_children l on l.child_id = rem.child_id
    join public.child_devices cd on cd.id = l.device_id and cd.mode_here and cd.here_endpoint is not null
    join public.push_subscriptions s on s.endpoint = cd.here_endpoint and s.user_id is not null
    where not exists (select 1 from dev where dev.child_id = rem.child_id)
      and exists (select 1 from public.family_members m where m.family_id = rem.family_id and m.user_id = s.user_id)
  ),
  dest as (select * from dev union all select * from here)
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', 'routine', 'mode', g.mode, 'endpoint', g.endpoint, 'p256dh', g.p256dh, 'auth', g.auth, 'locale', g.locale,
    'child', g.child_name, 'common', g.common, 'at', to_char(g.remind_at, 'HH24:MI'), 'routines', g.rts)), '[]'::jsonb) into routs
  from (
    select dest.mode, dest.endpoint, dest.p256dh, dest.auth, dest.locale, dest.common, rem.child_name, rem.remind_at,
      jsonb_agg(jsonb_build_object('title', rem.title, 'emoji', rem.emoji) order by rem.title) as rts
    from dest join rem on rem.child_id = dest.child_id
    group by dest.sub_id, dest.mode, dest.endpoint, dest.p256dh, dest.auth, dest.locale, dest.common, rem.child_id, rem.child_name, rem.remind_at
  ) g;

  return json_build_object('vapid_public', (select value from private.config where key = 'vapid_public'), 'items', sums || routs);
end $$;

do $t$
declare
  u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid();
  tz text; f1 uuid; f2 uuid; f3 uuid; c1 uuid; c1b uuid; c2 uuid; c3 uuid; r1 uuid; r2 uuid; r3 uuid; r4 uuid;
  d_com uuid; d_one uuid; d_here uuid; hm text; qt time; sec text; j jsonb; it jsonb; res text := '';
begin
  tz := (select z from unnest(array['Pacific/Auckland','Europe/Paris','America/New_York','Asia/Tokyo','Pacific/Honolulu']) z
         where extract(hour from now() at time zone z) between 6 and 21 limit 1);
  insert into auth.users(id, email) values (u1, 'p1.test@example.invalid'), (u2, 'p2.test@example.invalid');
  insert into public.families(name, plan, timezone) values ('Fam1', 'premium', tz) returning id into f1;
  insert into public.families(name, plan, timezone) values ('Fam2', 'premium', tz) returning id into f2;
  insert into public.families(name, plan, timezone) values ('Fam3', 'free', tz) returning id into f3;
  insert into public.family_members(family_id, user_id, role) values (f1, u1, 'parent'), (f2, u1, 'parent'), (f3, u2, 'parent'), (f1, u2, 'parent'), (f2, u2, 'parent');
  qt := ((date_trunc('hour', now() at time zone tz) + floor(extract(minute from now() at time zone tz) / 15) * interval '15 minutes'))::time;
  hm := to_char((now() at time zone tz) - interval '1 minute', 'HH24:MI');
  insert into public.children(family_id, name) values (f1, 'Enf1') returning id into c1;
  insert into public.children(family_id, name) values (f1, 'Enf1b') returning id into c1b;
  insert into public.children(family_id, name) values (f2, 'Enf2') returning id into c2;
  insert into public.children(family_id, name) values (f3, 'Enf3') returning id into c3;
  insert into public.routines(family_id, child_id, title, emoji, moment, remind_at) values (f1, c1, 'R1', 'a', 'matin', qt) returning id into r1;
  insert into public.routines(family_id, child_id, title, emoji, moment, remind_at) values (f1, c1, 'R1b', 'b', 'matin', qt);
  insert into public.routines(family_id, child_id, title, emoji, moment, remind_at) values (f2, c2, 'R2', 'c', 'matin', qt) returning id into r2;
  insert into public.routines(family_id, child_id, title, emoji, moment) values (f1, c1b, 'R1c', 'd', 'matin') returning id into r3;
  begin insert into public.routines(family_id, child_id, title, emoji, moment, remind_at) values (f3, c3, 'R3', 'e', 'matin', qt);
        res := res || ' 1.gratuit_remind=ok'; exception when others then res := res || ' 1.gratuit_remind=' || sqlerrm; end;
  begin insert into public.routines(family_id, child_id, title, moment, remind_at) values (f1, c1, 'X', 'matin', time '10:10'); res := res || ' 2.minute10=ok';
        exception when others then res := res || ' 2.minute10=refuse'; end;
  begin insert into public.routines(family_id, child_id, title, moment, remind_at) values (f1, c1, 'X', 'matin', time '04:45'); res := res || ' 2b.avant5h=ok';
        exception when others then res := res || ' 2b.avant5h=refuse'; end;
  begin insert into public.routines(family_id, child_id, title, moment, kind, start_day, end_day, remind_at) values (f1, c1, 'X', 'matin', 'oneoff', current_date, current_date, time '10:00'); res := res || ' 2c.oneoff=ok';
        exception when others then res := res || ' 2c.oneoff=refuse'; end;
  begin update public.routines set remind_at = null where id = r1; update public.routines set remind_at = qt where id = r1; res := res || ' 2d.maj_premium=ok';
        exception when others then res := res || ' 2d.maj=' || sqlerrm; end;
  -- appareils : commun (c1, c1b), un enfant (c2 : Mode ici), Mode ici de c3 (famille gratuite)
  insert into public.child_devices(child_id, family_id, token_hash, label) values (c1, f1, 'h-com', 'Commun') returning id into d_com;
  insert into public.child_device_children(device_id, child_id, family_id) values (d_com, c1, f1), (d_com, c1b, f1);
  insert into public.child_devices(child_id, family_id, token_hash, label, mode_here, here_endpoint) values (c2, f2, 'h-here', 'Ici', true, 'e-par') returning id into d_here;
  insert into public.child_device_children(device_id, child_id, family_id) values (d_here, c2, f2);
  insert into public.push_subscriptions(family_id, user_id, endpoint, p256dh, auth, reminder_times) values (f1, u1, 'e-par', 'k', 'a', array[hm]);
  insert into public.push_subscriptions(family_id, child_device_id, endpoint, p256dh, auth, reminder_times) values (f1, d_com, 'e-com', 'k', 'a', array[hm]);
  sec := (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret');
  res := res || ' 3.vault=' || (sec is not null) || '/egal_config=' || (sec = (select value from private.config where key = 'cron_secret'));
  begin perform public.reminders_due('mauvais'); res := res || ' 4.secret_faux=ok'; exception when others then res := res || ' 4.secret_faux=' || sqlerrm; end;
  j := public.reminders_due(sec)::jsonb;
  res := res || ' 5.cles=' || (select string_agg(k, ',' order by k) from jsonb_object_keys(j) k);
  select i into it from jsonb_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-par' and i ->> 'kind' = 'parent';
  res := res || ' 6.adulte_2_familles=' || coalesce((select string_agg(coalesce(c ->> 'family', '-') || '/' || (c ->> 'name'), ',' order by c ->> 'family', c ->> 'name') from jsonb_array_elements(it -> 'children') c), 'aucun');
  select i into it from jsonb_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-com' and i ->> 'kind' = 'child';
  res := res || ' 7.appareil_commun_kids=' || coalesce((select string_agg((k ->> 'name') || ':' || (k ->> 'left'), ',' order by k ->> 'name') from jsonb_array_elements(it -> 'kids') k), 'aucun') || '/left=' || coalesce(it ->> 'left', 'null');
  select i into it from jsonb_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-com' and i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf1';
  res := res || ' 8.routine_commun=' || coalesce((select string_agg(r ->> 'title', ',' order by r ->> 'title') from jsonb_array_elements(it -> 'routines') r), 'aucune') || '/mode=' || coalesce(it ->> 'mode', '-') || '/common=' || coalesce(it ->> 'common', '-') || '/at_ok=' || coalesce((it ->> 'at') = to_char(qt, 'HH24:MI'), false);
  select i into it from jsonb_array_elements(j -> 'items') i where i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf1b';
  res := res || ' 9.sans_rappel_enf1b=' || (it is null);
  select i into it from jsonb_array_elements(j -> 'items') i where i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf2';
  res := res || ' 10.mode_ici=' || coalesce(it ->> 'endpoint', 'aucun') || '/' || coalesce(it ->> 'mode', '-');
  -- 11 : l'enfant a un appareil à lui avec abonnement : le téléphone du parent ne reçoit plus le rappel
  insert into public.push_subscriptions(family_id, child_device_id, endpoint, p256dh, auth, reminder_times) values (f2, (select id from public.child_devices where token_hash = 'h-here'), 'e-ici-sub', 'k', 'a', array['00:00']);
  j := public.reminders_due(sec)::jsonb;
  res := res || ' 11.mode_ici_avec_abonnement_propre=' || (select count(*) from jsonb_array_elements(j -> 'items') i where i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf2');
  delete from public.push_subscriptions where endpoint = 'e-ici-sub';
  -- 12 : routine cochée, famille gratuite, pause
  insert into public.completions(routine_id, child_id, family_id, day, stars) values (r2, c2, f2, (now() at time zone tz)::date, 1);
  j := public.reminders_due(sec)::jsonb;
  res := res || ' 12.cochee=' || (select count(*) from jsonb_array_elements(j -> 'items') i where i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf2');
  insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (f1, c1, (now() at time zone tz)::date, (now() at time zone tz)::date, 'rest');
  j := public.reminders_due(sec)::jsonb;
  res := res || ' 13.pause=' || (select count(*) from jsonb_array_elements(j -> 'items') i where i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf1');
  begin update public.families set plan = 'free' where id = f2; exception when others then res := res || ' 13b.x=' || sqlerrm; end;
  -- 14 : parent_push_subscribe avec jetons
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.parent_push_subscribe(f1, 'e-nouveau', 'k', 'a', array['07:30'], 'fr', array['jeton-inconnu']); res := res || ' 14.abonne_jetons=ok'; exception when others then res := res || ' 14.x=' || sqlerrm; end;
  begin perform public.parent_push_subscribe(f3, 'e-x', 'k', 'a', array['07:30'], 'fr', null); res := res || ' 14b.autre_famille=ok'; exception when others then res := res || ' 14b.autre_famille=' || sqlerrm; end;
  reset role;
  -- 15 : départ d'une famille : l'abonnement suit, puis disparaît au dernier départ
  begin
  delete from public.family_members where family_id = f1 and user_id = u1;
  res := res || ' 15.apres_depart_f1=' || coalesce((select (family_id = f2)::text from public.push_subscriptions where endpoint = 'e-par'), 'supprime');
  delete from public.family_members where family_id = f2 and user_id = u1;
  res := res || ' 15b.apres_depart_f2=' || coalesce((select 'reste' from public.push_subscriptions where endpoint = 'e-par'), 'supprime');
  exception when others then res := res || ' 15.x=' || sqlerrm; end;
  res := res || ' 16.cron_sans_config=' || (select (command not like '%private.config%' and command like '%vault.decrypted_secrets%') from cron.job where jobname = 'soisfier-reminders');
  raise exception 'RESULT:%', res;
end $t$;
