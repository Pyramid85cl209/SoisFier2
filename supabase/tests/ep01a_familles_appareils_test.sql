-- Test de la migration ep01a_familles_appareils (EP-01 lot A) : dans une transaction annulée (le fichier contient la migration puis les cas).
-- Famille, enfants, utilisateurs et appareils fictifs ; rien n'est conservé. Résultat : une ligne d'erreur « RESULT: … ».
begin;
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

do $t$
declare
  u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid(); u3 uuid := gen_random_uuid();
  f1 uuid; f2 uuid; f3 uuid; f4 uuid; fx uuid; fa uuid; a uuid; b uuid; c uuid; ra uuid; rb uuid; rc uuid;
  code text; code2 text; j json; tok text; tok1 text; res text := ''; n int; td date;
begin
  insert into auth.users(id, email) values (u1, 'p1.test@example.invalid'), (u2, 'p2.test@example.invalid'), (u3, 'p3.test@example.invalid');
  -- Familles
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin f1 := public.create_family('F1', 'P1', 1::smallint, '{6,7}'::smallint[], 'Europe/Paris');
  res := res || ' 1.ancienne_idem=' || (public.create_family('F1bis', 'P1', 1::smallint, '{6,7}'::smallint[], 'Europe/Paris') = f1);
  res := res || ' 1b.nouvelle_sans_autre=' || (public.create_family('F1ter', 'P1', 1::smallint, '{6,7}'::smallint[], 'Europe/Paris', false) = f1);
  f2 := public.create_family('F2', 'P1', 1::smallint, '{6,7}'::smallint[], 'Europe/Paris', true);
  f3 := public.create_family('F3', 'P1', 1::smallint, '{6,7}'::smallint[], 'Europe/Paris', true);
  res := res || ' 2.trois_familles=' || (f1 <> f2 and f2 <> f3) || '/membre_de=' || (select count(*) from public.family_members where user_id = u1);
  exception when others then res := res || ' 1.x=' || sqlerrm; end;
  begin f4 := public.create_family('F4', 'P1', 1::smallint, '{6,7}'::smallint[], 'Europe/Paris', true); res := res || ' 3.quatrieme=cree';
  exception when others then res := res || ' 3.quatrieme=' || sqlerrm; end;
  reset role;
  res := res || ' 3b.created_by=' || (select count(*) from public.families where created_by = u1);
  -- u2 rejoint f1 et f2 (illimité), puis crée sa famille : compte 1
  insert into public.family_members(family_id, user_id, role) values (f1, u2, 'parent'), (f2, u2, 'parent');
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  fx := public.create_family('F-u2', 'P2', 1::smallint, '{6,7}'::smallint[], 'Europe/Paris', true);
  res := res || ' 4.adherent_cree_la_sienne=' || (fx is not null and fx <> f1);
  reset role;
  -- Enfants et routines de f1
  update public.families set plan = 'premium' where id = f1;
  insert into public.children(family_id, name, emoji, color) values (f1, 'EnfA', 'a', '#111111') returning id into a;
  insert into public.children(family_id, name, emoji, color) values (f1, 'EnfB', 'b', '#222222') returning id into b;
  insert into public.children(family_id, name, emoji, color) values (f1, 'EnfC', 'c', '#333333') returning id into c;
  insert into public.routines(family_id, child_id, title, moment) values (f1, a, 'RA', 'matin') returning id into ra;
  insert into public.routines(family_id, child_id, title, moment) values (f1, b, 'RB', 'matin') returning id into rb;
  insert into public.routines(family_id, child_id, title, moment) values (f1, c, 'RC', 'matin') returning id into rc;
  td := private.family_today(f1);
  -- Appareil commun A+B
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  code := public.create_child_code(a, array[b]);
  reset role; set local role anon;
  j := public.child_pair(code, 'Tablette');
  tok := j ->> 'token';
  reset role;
  res := res || ' 5a.jeton=' || (tok is not null);
  if tok is null then res := res || ' 5b.pair=' || j::text; end if;
  res := res || ' 6.liens=' || (select count(*) from public.child_device_children l join public.child_devices d on d.id = l.device_id where d.label = 'Tablette') || '/child_id_rempli=' || (select child_id is not null from public.child_devices where label = 'Tablette');
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin code2 := public.create_child_code(a, array[(select id from public.children where family_id = fx limit 1)]); res := res || ' 5.autre_famille_ignoree=' || (select array_length(child_ids,1) from public.child_device_codes where code = code2);
  exception when others then res := res || ' 5.x=' || sqlerrm; end;
  reset role;
  set local role anon;
  begin perform public.child_state(tok, null); res := res || ' 7.sans_enfant=ok'; exception when others then res := res || ' 7.sans_enfant=' || sqlerrm; end;
  begin perform public.child_state(tok); res := res || ' 7b.ancienne_sig=ok'; exception when others then res := res || ' 7b.ancienne_sig=' || sqlerrm; end;
  begin perform public.child_state(tok, c); res := res || ' 8.enfant_non_relie=ok'; exception when others then res := res || ' 8.enfant_non_relie=' || sqlerrm; end;
  begin j := public.child_state(tok, a);
  res := res || ' 9.etat_A=' || (j -> 'child' ->> 'name') || '/common=' || (j ->> 'common') || '/enfants=' || json_array_length(j -> 'device_children')
     || '/routines=' || (select string_agg(r ->> 'title', ',') from json_array_elements(j -> 'routines') r)
     || '/cles_autres=' || (select string_agg(k, ',' order by k) from json_object_keys((j -> 'device_children' ->> 0)::json) k);
  exception when others then res := res || ' 9.x=' || sqlerrm; end;
  begin perform public.child_toggle(tok, a, ra, td, true, 'child'); exception when others then res := res || ' 10a.x=' || sqlerrm; end;
  begin perform public.child_toggle(tok, a, rb, td, true, 'child'); res := res || ' 10.coche_autre=ok'; exception when others then res := res || ' 10.coche_autre=' || sqlerrm; end;
  begin perform public.child_toggle(tok, null, ra, td, true, 'child'); res := res || ' 10b.coche_sans_enfant=ok'; exception when others then res := res || ' 10b.coche_sans_enfant=' || sqlerrm; end;
  begin perform public.child_badges_seen(tok, b, array['x']); exception when others then res := res || ' 10c.x=' || sqlerrm; end;
  reset role;
  res := res || ' 11.coches=' || (select count(*) from public.completions where routine_id = ra and day = td) || '/' || (select count(*) from public.completions where routine_id = rb);
  -- Code de l'enfant (12 : un compte sans droit sur la famille)
  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.set_child_code(a, '{"salt":"s","hash":"h"}'::jsonb); res := res || ' 12.set_code_sans_droit=ok'; exception when others then res := res || ' 12.set_code_sans_droit=' || sqlerrm; end;
  begin perform public.set_child_code(a, '{"x":1}'::jsonb); res := res || ' 12b.mauvais=ok'; exception when others then res := res || ' 12b.mauvais=' || sqlerrm; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.set_child_code(a, '{"salt":"s","hash":"h"}'::jsonb); exception when others then res := res || ' 12c.x=' || sqlerrm; end;
  reset role; set local role anon;
  begin j := public.child_state(tok, b);
  res := res || ' 13.verifier=' || coalesce((select string_agg((e ->> 'name') || ':' || coalesce((e -> 'verifier')::text, 'null'), ',' order by e ->> 'name') from json_array_elements(j -> 'device_children') e), '');
  exception when others then res := res || ' 13.x=' || sqlerrm; end;
  begin perform count(*) from private.child_codes; res := res || ' 14.anon_lit_codes=ok'; exception when others then res := res || ' 14.anon_lit_codes=refuse'; end;
  reset role;
  -- RLS de la liaison
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
  res := res || ' 15.liaison_vue_membre=' || (select count(*) from public.child_device_children);
  begin insert into public.child_device_children(device_id, child_id, family_id) select device_id, c, f1 from public.child_device_children limit 1; res := res || ' 16.ecriture=ok';
  exception when others then res := res || ' 16.ecriture=refuse'; end;
  exception when others then res := res || ' 15.x=' || sqlerrm; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  set local role authenticated;
  res := res || ' 17.liaison_vue_etranger=' || (select count(*) from public.child_device_children);
  reset role;
  -- Appareil d'un seul enfant : ancienne et nouvelle signature
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin code2 := public.create_child_code(c);
  reset role; set local role anon;
  tok1 := (public.child_pair(code2, 'Seul')) ->> 'token';
  res := res || ' 18.jeton=' || (tok1 is not null) || ' seul=' || (public.child_state(tok1) -> 'child' ->> 'name') || '/' || (public.child_state(tok1, null) -> 'child' ->> 'name') || '/common=' || (public.child_state(tok1, null) ->> 'common');
  exception when others then res := res || ' 18.x=' || sqlerrm; end;
  reset role;
  -- Mode enfant ici : plusieurs enfants, réutilisation de la ligne
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin j := public.child_pair_here(a, 'Ici', array[b], null, 'https://ep.invalid/x');
  res := res || ' 19.ici=' || (select count(*) from public.child_device_children where device_id = (select id from public.child_devices where label = 'Ici')) || '/mode_here=' || (select mode_here from public.child_devices where label = 'Ici');
  j := public.child_pair_here(a, 'Ici', array[c], j ->> 'token', null);
  res := res || ' 19b.reutilise=' || (select count(*) from public.child_devices where label = 'Ici') || '/enfants=' || (select count(*) from public.child_device_children where device_id = (select id from public.child_devices where label = 'Ici')) || '/endpoint_gardee=' || (select here_endpoint from public.child_devices where label = 'Ici');
  res := res || ' 19c.ancienne_sig=' || (public.child_pair_here(a, 'Ici2') ->> 'child_id' = a::text);
  exception when others then res := res || ' 19.x=' || sqlerrm; end;
  reset role;
  -- Suppression d'enfants : l'appareil reste tant qu'un enfant lui est relié
  begin
  delete from public.children where id = b;
  res := res || ' 20.apres_B=' || (select count(*) from public.child_devices where label = 'Tablette');
  delete from public.children where id = a;
  res := res || ' 21.apres_A=' || (select count(*) from public.child_devices where label = 'Tablette') || '/codes=' || (select count(*) from private.child_codes);
  -- Droits des nouvelles fonctions
  exception when others then res := res || ' 20.x=' || sqlerrm; end;
  res := res || ' 22.droits=anon_cree_famille:' || has_function_privilege('anon', 'public.create_family(text,text,smallint,smallint[],text,boolean)', 'execute')
     || '/anon_set_code:' || has_function_privilege('anon', 'public.set_child_code(uuid,jsonb)', 'execute')
     || '/anon_state:' || has_function_privilege('anon', 'public.child_state(text,uuid)', 'execute');
  raise exception 'RESULT:%', res;
end $t$;
