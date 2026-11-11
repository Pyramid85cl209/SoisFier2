-- EP-09 thème A (1/2) : contrôles serveur et sécurité. Migration « ajouts et remplacements » (aucun drop, revoke ni delete exécuté).
-- Les corps de fonctions ci-dessous contiennent des delete (purge, retrait d'appareil, abonnements d'un membre parti) : ils ne s'exécutent pas à l'application.
-- À tester dans une transaction annulée (supabase/tests/ep09a_controles_test.sql) avant d'appliquer. À appliquer AVANT ep09a_droits_retraits.
--
-- ADR-41  coches : déclencheur private.check_completion (DT04-14, DT05-05, DT04-03, DT10-09)
-- ADR-43  échange de l'adulte : public.redeem (DT06-02, DT00-25)
-- ADR-36  essais limités : private.code_failures, join_family (clé = compte), child_pair (clé = connexion internet) (DT02-08)
-- ADR-40  appareil de l'enfant périmé après 3 mois (DT03-07), purge quotidienne (ADR-47)
-- ADR-49  sortie du mode enfant : public.child_unpair (DT03-02) ; Mode enfant ici sans code enfant : public.child_pair_here (DT03-05)
-- Droits et données : nom d'utilisateur (DT02-05), code déjà membre (DT02-04), lien de l'adulte côté enfant (DT03-03, DT02-02),
--                     rappels d'un membre parti (DT11-07).
--
-- Codes d'erreur nouveaux : SF:not_due, SF:already_done, SF:bad_price, SF:code_locked:<minutes>, SF:device_expired, SF:already_member, SF:not_your_name.
-- Une erreur annule toute la transaction (donc l'enregistrement d'un échec) : un code faux n'est donc PAS une erreur pour join_family
-- (renvoie null) ni pour child_pair (renvoie {"error":"bad_code"}) ; l'application en fait l'erreur SF:bad_code côté écran.

-- ============================================================================
-- 1. Essais limités des codes (ADR-36)
-- ============================================================================
create table if not exists private.code_failures (
  id           bigint generated always as identity primary key,
  kind         text not null check (kind in ('invite', 'pair')),
  k            text not null,                         -- invite : identifiant du compte ; pair : empreinte de la connexion internet
  at           timestamptz not null default now(),
  locked_until timestamptz                            -- posé sur le 5e échec en 15 minutes : blocage de 15 minutes
);
create index if not exists code_failures_k_idx on private.code_failures (kind, k, at);
alter table private.code_failures enable row level security;   -- aucune politique : table interne, jamais exposée

create or replace function private.code_guard(p_kind text, p_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare lu timestamptz;
begin
  select max(f.locked_until) into lu from private.code_failures f
   where f.kind = p_kind and f.k = p_key and f.locked_until > now();
  if lu is not null then
    raise exception 'SF:code_locked:%', greatest(1, ceil(extract(epoch from (lu - now())) / 60)::int);
  end if;
end $function$;

create or replace function private.code_fail(p_kind text, p_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare n int;
begin
  select count(*) into n from private.code_failures f
   where f.kind = p_kind and f.k = p_key and f.at > now() - interval '15 minutes';
  insert into private.code_failures(kind, k, locked_until)
  values (p_kind, p_key, case when n + 1 >= 5 then now() + interval '15 minutes' end);
end $function$;

-- Empreinte de la connexion internet de l'appelant : adresse IPv4 entière, préfixe /64 en IPv6, hachée (SHA-256).
-- En-têtes lus : cf-connecting-ip (posé par le réseau d'accès, non falsifiable), puis x-real-ip, puis le 1er élément de x-forwarded-for.
create or replace function private.client_key()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare h json; ip text; a inet;
begin
  begin h := nullif(current_setting('request.headers', true), '')::json; exception when others then h := null; end;
  ip := coalesce(nullif(trim(h ->> 'cf-connecting-ip'), ''), nullif(trim(h ->> 'x-real-ip'), ''),
                 nullif(trim(split_part(coalesce(h ->> 'x-forwarded-for', ''), ',', 1)), ''));
  begin a := ip::inet; exception when others then a := null; end;
  if a is null then return 'noip'; end if;
  return encode(extensions.digest(case family(a) when 6 then network(set_masklen(a, 64))::text else host(a) end, 'sha256'), 'hex');
end $function$;

create or replace function public.join_family(p_code text, p_display_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare inv record; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'SF:login_required'; end if;
  perform private.code_guard('invite', uid::text);
  select * into inv from public.invites where code = upper(trim(p_code)) and used_at is null and expires_at > now();
  if not found then
    perform private.code_fail('invite', uid::text);
    return null;                                    -- code faux : l'échec doit rester enregistré (pas d'erreur levée)
  end if;
  if exists (select 1 from public.family_members m where m.family_id = inv.family_id and m.user_id = uid) then
    raise exception 'SF:already_member';            -- DT02-04 : le code n'est pas consommé
  end if;
  insert into public.family_members(family_id, user_id, role, display_name, relation)
  values (inv.family_id, uid, inv.role, nullif(trim(p_display_name), ''), inv.relation);
  update public.invites set used_at = now() where code = inv.code;
  return inv.family_id;
end $function$;

create or replace function public.child_pair(p_code text, p_label text default null)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare rec record; tok text; ck text := private.client_key();
begin
  perform private.code_guard('pair', ck);
  select * into rec from public.child_device_codes where code = upper(trim(p_code)) and expires_at > now();
  if not found then
    perform private.code_fail('pair', ck);
    return json_build_object('error', 'bad_code');  -- code faux : l'échec doit rester enregistré (pas d'erreur levée)
  end if;
  tok := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.child_devices(child_id, family_id, token_hash, label)
  values (rec.child_id, rec.family_id, encode(extensions.digest(tok, 'sha256'), 'hex'), nullif(left(trim(p_label), 60), ''));
  delete from public.child_device_codes where code = rec.code;
  return json_build_object('token', tok, 'child_id', rec.child_id);
end $function$;

-- ============================================================================
-- 2. Appareil de l'enfant : expiration à 3 mois (ADR-40), sortie (ADR-49), Mode enfant ici (DT03-05), purge (ADR-47)
-- ============================================================================
create or replace function private.device_child(p_token text, OUT device_id uuid, OUT child_id uuid, OUT family_id uuid)
returns record
language plpgsql
security definer
set search_path = ''
as $function$
declare seen timestamptz;
begin
  select d.id, d.child_id, d.family_id, coalesce(d.last_seen, d.created_at) into device_id, child_id, family_id, seen
  from public.child_devices d
  where d.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if device_id is null then raise exception 'SF:device_unknown'; end if;
  -- Jeton périmé : refusé (une erreur annulerait un delete ici) ; l'application appelle child_unpair, sinon la purge quotidienne le retire.
  if seen < now() - interval '3 months' then raise exception 'SF:device_expired'; end if;
  update public.child_devices set last_seen = now() where id = device_id;
end $function$;

-- Retire l'appareil du jeton, même périmé. Sans effet pour un jeton inconnu (file hors ligne rejouée).
create or replace function public.child_unpair(p_token text)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
begin
  delete from public.child_devices where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  return json_build_object('ok', true);
end $function$;

-- Mode enfant ici : appareil créé pour le téléphone du parent connecté, sans passer par child_device_codes (le code en attente de l'enfant reste valable).
create or replace function public.child_pair_here(p_child uuid, p_label text default null)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare fid uuid; tok text;
begin
  select c.family_id into fid from public.children c where c.id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:device_parent_only'; end if;
  tok := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.child_devices(child_id, family_id, token_hash, label)
  values (p_child, fid, encode(extensions.digest(tok, 'sha256'), 'hex'), nullif(left(trim(p_label), 60), ''));
  return json_build_object('token', tok, 'child_id', p_child);
end $function$;

create or replace function private.purge_daily()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  delete from private.code_failures where at < now() - interval '1 day';
  delete from public.child_devices where coalesce(last_seen, created_at) < now() - interval '3 months';   -- abonnements de rappel liés : en cascade
end $function$;

select cron.schedule('soisfier-purge-daily', '25 3 * * *', 'select private.purge_daily()');

-- ============================================================================
-- 3. Coches contrôlées par le serveur (ADR-41)
-- ============================================================================
create or replace function private.check_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare r public.routines; today date;
begin
  -- report_sheet contrôle déjà ses jours et ses routines : exemption par un repère local à sa transaction (comme sf.via_device).
  if coalesce(current_setting('sf.via_report', true), '') = 'on' then return new; end if;
  select * into r from public.routines where id = new.routine_id;
  if not found then return new; end if;               -- la clé étrangère refusera
  today := private.family_today(new.family_id);
  if new.day > today or new.day < today - 6 then raise exception 'SF:day_locked'; end if;   -- adulte : 6 jours (child_toggle garde ses 2 jours)
  if r.kind = 'oneoff' then
    if new.day < r.start_day or new.day > r.end_day then raise exception 'SF:oneoff_out_of_range'; end if;
    if exists (select 1 from public.completions c where c.routine_id = r.id and c.day <> new.day) then raise exception 'SF:already_done'; end if;
  else
    if not exists (select 1 from private.routine_rules(new.child_id, new.day) rr where rr.routine_id = r.id) then
      if r.holiday_period_id is not null then raise exception 'SF:holiday_out_of_range'; end if;
      raise exception 'SF:not_due';
    end if;
  end if;
  return new;
end $function$;

create trigger completions_check before insert on public.completions
  for each row execute function private.check_completion();

-- report_sheet : identique à la v30, avec le repère sf.via_report autour de l'insertion
create or replace function public.report_sheet(p_child uuid, p_week_start date, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  fid uuid; ws int; today date; cur date;
  items jsonb := coalesce(p_items, '[]'::jsonb);
  e jsonb; rtxt text; rid uuid; d date; st text; rc int;
  r record; cm record;
  res jsonb := '[]'::jsonb;
begin
  select c.family_id into fid from public.children c where c.id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:access_denied'; end if;
  if not private.is_premium(fid) then raise exception 'SF:premium_report'; end if;

  select f.week_start into ws from public.families f where f.id = fid;
  today := private.family_today(fid);
  cur := today - (((extract(isodow from today)::int - ws) + 7) % 7);
  if p_week_start is null or p_week_start not in (cur, cur - 7) then raise exception 'SF:scan_week'; end if;

  if jsonb_typeof(items) <> 'array' then items := '[]'::jsonb; end if;
  if jsonb_array_length(items) > 500 then raise exception 'SF:scan_too_many'; end if;

  for e in select x.value from jsonb_array_elements(items) as x loop
    begin d := (e->>'day')::date; exception when others then d := null; end;
    if d is null or d < p_week_start or d > p_week_start + 6 or d > today then raise exception 'SF:scan_day'; end if;

    rtxt := e->>'routine'; rid := null;
    if rtxt ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then rid := rtxt::uuid; end if;

    select ro.child_id, ro.kind, ro.active into r from public.routines ro where ro.id = rid;
    if not found or r.child_id <> p_child or r.kind <> 'regular' or not r.active then
      st := 'stopped';
    elsif not exists (select 1 from private.routine_rules(p_child, d) rr where rr.routine_id = rid) then
      st := 'not_due';
    else
      select co.id, co.validated_at into cm from public.completions co where co.routine_id = rid and co.day = d for update;
      if not found then
        perform set_config('sf.via_report', 'on', true);
        insert into public.completions(family_id, child_id, routine_id, day, source)
        values (fid, p_child, rid, d, 'parent')
        on conflict (routine_id, day) do nothing;
        get diagnostics rc = row_count;
        perform set_config('sf.via_report', '', true);
        st := case when rc = 1 then 'reported' else 'already_done' end;
      elsif cm.validated_at is null then
        update public.completions set validated_at = now() where id = cm.id;
        st := 'validated';
      else
        st := 'already_done';
      end if;
    end if;
    res := res || jsonb_build_object('routine', rtxt, 'day', d, 'status', st);
  end loop;
  return res;
end $function$;

-- ============================================================================
-- 4. Échange de l'adulte par une fonction serveur (ADR-43)
-- ============================================================================
create or replace function public.redeem(p_child uuid, p_reward uuid, p_id uuid default null)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare fid uuid; w public.rewards; price int; rid uuid := coalesce(p_id, gen_random_uuid());
begin
  select c.family_id into fid from public.children c where c.id = p_child;
  if fid is null or not private.is_member(fid) then raise exception 'SF:access_denied'; end if;
  select * into w from public.rewards where id = p_reward and family_id = fid and active
    and (child_id is null or child_id = p_child);
  if not found then raise exception 'SF:reward_not_found'; end if;
  price := private.reward_cost(w, p_child);            -- prix lu en base, jamais envoyé par l'écran
  if price is null or price <= 0 then raise exception 'SF:bad_price'; end if;
  if coalesce(private.balance(p_child), 0) < price then raise exception 'SF:not_enough_stars'; end if;
  insert into public.redemptions(id, family_id, child_id, reward_id, title, emoji, cost)
  values (rid, fid, p_child, w.id, w.title, w.emoji, price);   -- auteur posé par redemptions_author (auth.uid())
  return json_build_object('ok', true, 'id', rid, 'cost', price);
end $function$;

-- ============================================================================
-- 5. Droits et données
-- ============================================================================
-- DT02-05 (DEC-31) : le nom d'utilisateur ne se change que sur sa propre fiche (auth.uid() vide = opération d'administration)
create or replace function private.protect_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare nparents int;
begin
  select count(*) into nparents from public.family_members where family_id = old.family_id and role = 'parent';
  if tg_op = 'DELETE' then
    if old.role = 'parent' and nparents <= 1 and pg_trigger_depth() = 1 then raise exception 'SF:last_parent'; end if;
    return old;
  end if;
  new.family_id := old.family_id; new.user_id := old.user_id;
  if new.display_name is distinct from old.display_name and auth.uid() is not null and old.user_id <> auth.uid() then
    raise exception 'SF:not_your_name';
  end if;
  if new.role is distinct from old.role then
    if not private.is_parent(old.family_id) then raise exception 'SF:rights_parent_only'; end if;
    if old.role = 'parent' and nparents <= 1 then raise exception 'SF:last_parent'; end if;
  end if;
  return new;
end $function$;

-- DT11-07 (DEC-23) : les abonnements aux rappels d'un membre retiré ou parti sont supprimés
create or replace function private.member_left()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  delete from public.push_subscriptions where family_id = old.family_id and user_id = old.user_id;
  return old;
end $function$;

create trigger family_members_left after delete on public.family_members
  for each row execute function private.member_left();

-- reminders_due : identique à l'actuelle, mais les adultes ne reçoivent que s'ils sont membres actuels de la famille
-- (les clés des rappels restent dans private.config : ADR-45, à part)
create or replace function public.reminders_due(p_secret text)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare items json;
begin
  if p_secret is null or p_secret is distinct from (select value from private.config where key = 'cron_secret') then
    raise exception 'SF:access_denied';
  end if;
  with fam as (
    select f.id, (now() at time zone f.timezone) as now_l from public.families f
  ),
  due as (
    select s.* from public.push_subscriptions s join fam on fam.id = s.family_id
    where (s.child_device_id is not null
           or exists (select 1 from public.family_members m where m.family_id = s.family_id and m.user_id = s.user_id))
      and exists (select 1 from unnest(s.reminder_times) t
                  where t ~ '^\d{2}:\d{2}$' and fam.now_l::time >= t::time and fam.now_l::time < t::time + interval '15 minutes')
  ),
  todo as (
    select c.id as child_id, c.family_id, c.name,
      (select count(*) from private.routine_rules(c.id, fam.now_l::date) rr where not rr.is_bonus) as total,
      (select count(*) from private.routine_rules(c.id, fam.now_l::date) rr where not rr.is_bonus
        and exists (select 1 from public.completions x where x.routine_id = rr.routine_id and x.day = fam.now_l::date)) as done,
      (select count(*) from public.completions x where x.child_id = c.id and x.validated_at is null) as pending
    from public.children c
    join fam on fam.id = c.family_id
    where exists (select 1 from due d where d.family_id = c.family_id)
  )
  select coalesce(json_agg(json_build_object(
    'endpoint', d.endpoint, 'p256dh', d.p256dh, 'auth', d.auth, 'locale', d.locale,
    'kind', case when d.child_device_id is not null then 'child' else 'parent' end,
    'left', case when d.child_device_id is not null then
        (select t.total - t.done from todo t join public.child_devices cd on cd.child_id = t.child_id where cd.id = d.child_device_id) end,
    'children', case when d.child_device_id is null then
        (select json_agg(json_build_object('name', t.name, 'done', t.done, 'total', t.total, 'pending', t.pending) order by t.name)
         from todo t where t.family_id = d.family_id and (t.total > 0 or t.pending > 0)) end
  )), '[]'::json) into items from due d;
  return json_build_object(
    'vapid_public', (select value from private.config where key = 'vapid_public'),
    'vapid_private', (select value from private.config where key = 'vapid_private'),
    'subject', (select value from private.config where key = 'vapid_subject'),
    'items', items);
end $function$;

-- DT03-03, DT02-02 : child_state ne renvoie plus le prénom d'un adulte, seulement la clé de son lien (validated_rel) ;
-- validated_label vaut 'auto' (validation automatique), 'member' (un membre actuel a validé) ou vide (membre retiré, affiché « Validée »).
-- Le reste est identique à la version actuelle.
create or replace function public.child_state(p_token text)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare d record; today date; res json;
begin
  select * into d from private.device_child(p_token);
  today := private.family_today(d.family_id);
  select json_build_object(
    'today', today,
    'premium', private.is_premium(d.family_id),
    'child', (select row_to_json(c) from (select id, name, emoji, color, garden_start from public.children where id = d.child_id) c),
    'routines', coalesce((select json_agg(r order by r.position, r.created_at) from
        (select id, title, emoji, place, moment, stars, days, is_bonus, timer_minutes, position, created_at, kind, start_day, end_day, holiday_period_id
         from public.routines where child_id = d.child_id and active and (kind = 'regular' or end_day >= today - 2)) r), '[]'::json),
    'holidays', coalesce((select json_agg(h order by h.start_day) from
        (select p.id, p.name, p.start_day, p.end_day,
           coalesce((select json_agg(json_build_object('routine_id', o.routine_id, 'status', o.status, 'days', o.days, 'stars', o.stars))
                     from public.holiday_overrides o where o.period_id = p.id), '[]'::json) as overrides
         from public.holiday_periods p where p.child_id = d.child_id and p.active and p.end_day >= today - 60) h), '[]'::json),
    'completions', coalesce((select json_agg(x) from
        (select routine_id, day, stars, source, validated_at is not null as validated,
           case when validated_at is null then null when validated_by is null then 'auto'
                when exists (select 1 from public.family_members m where m.family_id = d.family_id and m.user_id = validated_by) then 'member' end as validated_label,
           case when validated_at is not null and validated_by is not null
                then (select m.relation_key from public.family_members m where m.family_id = d.family_id and m.user_id = validated_by) end as validated_rel
         from public.completions where child_id = d.child_id and day >= today - 60) x), '[]'::json),
    'oneoff_done', (select count(*) from public.completions c join public.routines r on r.id = c.routine_id
                    where c.child_id = d.child_id and r.kind = 'oneoff' and c.validated_at is not null),
    'rewards', coalesce((select json_agg(w order by w.cost) from
        (select id, title, emoji, tier, event_date, place, private.reward_cost(rw, d.child_id) as cost
         from public.rewards rw where family_id = d.family_id and active and (child_id is null or child_id = d.child_id)
           and (event_date is null or event_date >= today)) w), '[]'::json),
    'redemptions', coalesce((select json_agg(z order by z.created_at desc) from
        (select id, title, emoji, cost, created_at from public.redemptions where child_id = d.child_id
         order by created_at desc limit 30) z), '[]'::json),
    'penalties', coalesce((select json_agg(p order by p.created_at desc) from
        (select id, title, emoji, stars, created_at from public.penalty_events where child_id = d.child_id
         order by created_at desc limit 30) p), '[]'::json),
    'badges', coalesce((select json_agg(b.badge_key) from public.child_badges b where b.child_id = d.child_id), '[]'::json),
    'badge_dates', coalesce((select json_object_agg(b.badge_key, b.earned_at) from public.child_badges b where b.child_id = d.child_id), '{}'::json),
    'stats', (select row_to_json(s) from (select earned, done_count, pending_stars, pending_count, spent, redeemed_count, broken, broken_count
              from public.child_stats where child_id = d.child_id) s),
    'garden', private.garden_payload(d.child_id),
    'family', (select json_build_object('week_start', week_start, 'weekend_days', weekend_days, 'timezone', timezone) from public.families where id = d.family_id)
  ) into res;
  return res;
end $function$;
