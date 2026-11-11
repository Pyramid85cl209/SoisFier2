-- Test des migrations ep09a (thème A d'EP-09) : à lancer AVANT d'appliquer les migrations, dans l'éditeur SQL de Supabase (elle contient des drop et des revoke :
-- le connecteur demande une confirmation). Tout se passe dans une transaction annulée : famille, enfant, utilisateurs, appareils fictifs, rien n'est conservé.
-- Contenu : migration 1 (20261111210000), cas 1 à 23 (dont 20b, 20c), migration 2 (20261111210100), cas 24 à 29. Fichier composé : à régénérer si une migration ou un cas change
--   cat migrations/20261111210000_ep09a_controles_serveur.sql tests/ep09a_cases.sql migrations/20261111210100_ep09a_droits_retraits.sql tests/ep09a_cases_2.sql
-- Résultat attendu : une seule ligne d'erreur « RESULT: … » contenant, dans l'ordre :
--  1.due=ok 2.j-7=SF:day_locked 2b.j-6=ok 3.futur=SF:day_locked 4.pas_due=SF:not_due 5.oneoff=ok 5b.autre_jour=SF:already_done 5c.hors_dates=SF:oneoff_out_of_range
--  6.vacances_hors=SF:holiday_out_of_range 6b.proche=SF:not_due 22a.proche_ici=SF:device_parent_only 22b.code_garde=oui 7.enfant_due=ok 7b.enfant_pas_due=SF:not_due 8.report=reported
--  9.echange=3/auteur=parent 10.solde=SF:not_enough_stars 11.membre_ok=ok 11b.autre_famille=SF:access_denied 11c.sans_famille=SF:access_denied 11d.proche=ok 12.prix_nul=SF:bad_price
--  13.faux=5_nuls 13b=SF:code_locked:15 13c.apres_blocage=ok 14.deja_membre=SF:already_member 14b.code_non_consomme=oui
--  15.faux=5_bad_code 15b=SF:code_locked:15 15c.meme_64=SF:code_locked:15 15d.autre_64=ok 15e.ipv4=SF:code_locked:15 15f=bad_code 15g.cf_prioritaire=bad_code 15h.sans_ip=bad_code
--  16.perime=SF:device_expired 16b.2m29j=ok 17.unpair_perime=ok/0 17b=ok 17c.apres=SF:device_unknown 17d.jamais_rouvert=SF:device_expired 18.purge=0_vieux/0_echecs/1_recent 18b.cron=25 3 * * *
--  19.nom_autre=SF:not_your_name 19b=ok 19c=ok 20.lien=mom/member/prenom_present=false 20b.libre=sans_cle/Nounou Test 20c.retire=null/null/null 21.rappels_avant=2_envois 21b=0_reste/1_parent 21c=1_envois 23.echange_direct_avant=ok
--  24.echange_direct_apres=new row violates row-level security policy for table "redemptions" 24b.echange_serveur=ok 25.suppression_routine=1_reste_sur_1 25b.arret=ok
--  28.coche=ok 28b.fuseau=ok 28c.lien=ok/aunt 28d.rls_lecture=true 28e=ok 28f=ok 28g=ok 28h=ok 28i=ok 28j.anon_routines=permission denied for table routines
--  26.droits=rules_auth:false/is_member:true/valid_tz:true/relation_key:true/anon_toggle:true/anon_unpair:true/anon_redeem:false/auth_redeem:true/anon_pair_here:false/anon_routines:false/anon_tips:true/anon_tips_insert:false/sauvegarde_code_failures:true/fonctions_retirees:true
--  27.politiques_vacances=0_hors_authenticated/8_total 29.fonctions_private_exposees=0
-- Lancé jusqu'ici sur une réplique locale du schéma (PostgreSQL 16), pas sur la base de production (connecteur : confirmation annulée).
begin;
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
-- validated_custom : libellé libre du lien quand il n'a pas de clé ; validated_label vaut 'auto' (validation automatique), 'member' (un membre actuel a validé) ou vide (membre retiré, affiché « Validée »).
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
                then (select m.relation_key from public.family_members m where m.family_id = d.family_id and m.user_id = validated_by) end as validated_rel,
           -- libellé personnalisé (« Autre… », sans clé) : affiché tel quel (F02-04 CA5)
           case when validated_at is not null and validated_by is not null
                then (select nullif(btrim(m.relation), '') from public.family_members m where m.family_id = d.family_id and m.user_id = validated_by and m.relation_key is null) end as validated_custom
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
do $t$
declare
  u_par uuid := gen_random_uuid(); u_help uuid := gen_random_uuid(); u_par2 uuid := gen_random_uuid(); u_out uuid := gen_random_uuid();
  fid uuid; fid2 uuid; c1 uuid; c2 uuid;
  rReg uuid; rB uuid; rMon uuid; rOne uuid; rHol uuid; rReg2 uuid; hp uuid;
  w uuid; wBig uuid; wZero uuid;
  td date; d_non date; d2 date; cur date; ws int; i int;
  res text := ''; v text; v2 text; n int; tok text; tok2 text; tok3 text; v_code text; v_code2 text; sec text; j json;
begin
  -- Aides
  create or replace function pg_temp.as_user(u uuid) returns void language plpgsql as $f$
  begin
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', case when u is null then '' else json_build_object('sub', u, 'role', 'authenticated')::text end, true);
    perform set_config('role', case when u is null then 'anon' else 'authenticated' end, true);
  end $f$;
  create or replace function pg_temp.try(q text) returns text language plpgsql as $f$
  begin execute q; return 'ok'; exception when others then return sqlerrm; end $f$;
  create or replace function pg_temp.sup(q text) returns text language plpgsql as $f$
  declare old text := current_setting('role'); x text;
  begin perform set_config('role', 'postgres', true); execute q into x; perform set_config('role', old, true); return x; end $f$;
  create or replace function pg_temp.supdo(q text) returns void language plpgsql as $f$
  declare old text := current_setting('role');
  begin perform set_config('role', 'postgres', true); execute q; perform set_config('role', old, true); end $f$;
  create or replace function pg_temp.tq(q text) returns text language plpgsql as $f$ declare x text; begin execute q into x; return x; exception when others then return sqlerrm; end $f$;
  create or replace function pg_temp.hdr(x text) returns void language sql as $f$ select set_config('request.headers', x, true) $f$;

  -- Données fictives (aucun vrai e-mail ni prénom)
  insert into auth.users(id, email) values (u_par, 'parent.test@example.invalid'), (u_help, 'proche.test@example.invalid'),
    (u_par2, 'parent2.test@example.invalid'), (u_out, 'hors.test@example.invalid');
  insert into public.families(name) values ('Famille test EP-09A') returning id into fid;
  insert into public.families(name) values ('Famille test EP-09A bis') returning id into fid2;
  update public.families set plan = 'premium' where id = fid;
  insert into public.family_members(family_id, user_id, role, display_name, relation)
    values (fid, u_par, 'parent', 'Prenom Test Parent', 'Maman'), (fid, u_help, 'helper', 'Prenom Test Proche', null), (fid2, u_par2, 'parent', null, null);
  insert into public.children(family_id, name) values (fid, 'Enfant 1') returning id into c1;
  insert into public.children(family_id, name) values (fid2, 'Enfant 2') returning id into c2;
  td := private.family_today(fid);
  insert into public.routines(family_id, child_id, title, stars, created_at) values (fid, c1, 'Routine A', 20, now() - interval '30 days') returning id into rReg;
  insert into public.routines(family_id, child_id, title, stars, created_at) values (fid, c1, 'Routine B', 1, now() - interval '30 days') returning id into rB;
  insert into public.routines(family_id, child_id, title, stars, created_at) values (fid, c1, 'Routine C', 1, now() - interval '30 days') returning id into rReg2;
  insert into public.routines(family_id, child_id, title, stars, days, created_at) values (fid, c1, 'Lundi seul', 1, '{1}', now() - interval '30 days') returning id into rMon;
  insert into public.routines(family_id, child_id, title, stars, kind, start_day, end_day) values (fid, c1, 'Exceptionnelle', 1, 'oneoff', td - 3, td) returning id into rOne;
  insert into public.holiday_periods(family_id, child_id, name, start_day, end_day) values (fid, c1, 'Vacances test', td + 10, td + 20) returning id into hp;
  insert into public.routines(family_id, child_id, title, stars, holiday_period_id) values (fid, c1, 'Routine de vacances', 1, hp) returning id into rHol;
  insert into public.rewards(family_id, title, cost) values (fid, 'Récompense test', 3) returning id into w;
  insert into public.rewards(family_id, title, cost) values (fid, 'Récompense chère', 999) returning id into wBig;
  for i in 0..6 loop if d_non is null and extract(isodow from td - i) <> 1 then d_non := td - i; end if; end loop;
  for i in 0..2 loop if d2 is null and extract(isodow from td - i) <> 1 then d2 := td - i; end if; end loop;

  -- ===================== A. Coches (ADR-41) =====================
  perform pg_temp.as_user(u_par);
  res := res || ' 1.due=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rReg, td));
  res := res || ' 2.j-7=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rReg, td - 7));
  res := res || ' 2b.j-6=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rReg, td - 6));
  res := res || ' 3.futur=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rReg, td + 1));
  res := res || ' 4.pas_due=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rMon, d_non));
  res := res || ' 5.oneoff=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rOne, td - 1));
  res := res || ' 5b.autre_jour=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rOne, td));
  res := res || ' 5c.hors_dates=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rOne, td - 5));
  res := res || ' 6.vacances_hors=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rHol, td));
  -- Proche : mêmes contrôles
  perform pg_temp.as_user(u_help);
  res := res || ' 6b.proche=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rMon, d_non));
  -- Téléphone de l'enfant : Mode enfant ici (child_pair_here), contrôle du jour déjà fait par child_toggle, routine due ajoutée par le déclencheur
  perform pg_temp.as_user(u_help);
  res := res || ' 22a.proche_ici=' || pg_temp.try(format('select public.child_pair_here(%L, null)', c1));
  perform pg_temp.as_user(u_par);
  v_code := public.create_child_code(c1);                                   -- code en attente, à ne pas perdre
  tok := (public.child_pair_here(c1, 'Téléphone test') ->> 'token');
  res := res || ' 22b.code_garde=' || coalesce(pg_temp.sup(format('select ''oui'' from public.child_device_codes where code = %L', v_code)), 'non');
  perform pg_temp.as_user(null);
  res := res || ' 7.enfant_due=' || pg_temp.try(format('select public.child_toggle(%L, %L, %L, true, ''child'')', tok, rB, td));
  res := res || ' 7b.enfant_pas_due=' || pg_temp.try(format('select public.child_toggle(%L, %L, %L, true, ''child'')', tok, rMon, d2));
  -- report_sheet : jours de la semaine précédente (plus de 6 jours en arrière) exemptés
  perform pg_temp.as_user(u_par);
  select week_start into ws from public.families where id = fid;
  cur := td - (((extract(isodow from td)::int - ws) + 7) % 7);
  res := res || ' 8.report=' || coalesce((public.report_sheet(c1, cur - 7, jsonb_build_array(jsonb_build_object('routine', rReg2, 'day', cur - 7))) -> 0 ->> 'status'), 'vide');

  -- ===================== B. Échange de l'adulte (ADR-43) =====================
  perform pg_temp.as_user(u_par);
  j := public.redeem(c1, w, null);
  res := res || ' 9.echange=' || coalesce(j ->> 'cost', 'null') || '/auteur=' || (select case when created_by = u_par then 'parent' else coalesce(created_by::text, 'vide') end from public.redemptions where id = (j ->> 'id')::uuid);
  res := res || ' 10.solde=' || pg_temp.try(format('select public.redeem(%L, %L, null)', c1, wBig));
  res := res || ' 11.membre_ok=' || pg_temp.try(format('select public.redeem(%L, %L, null)', c1, w));   
  perform pg_temp.as_user(u_par2);
  res := res || ' 11b.autre_famille=' || pg_temp.try(format('select public.redeem(%L, %L, null)', c1, w));
  perform pg_temp.as_user(u_out);
  res := res || ' 11c.sans_famille=' || pg_temp.try(format('select public.redeem(%L, %L, null)', c1, w));
  perform pg_temp.as_user(u_help);
  res := res || ' 11d.proche=' || pg_temp.try(format('select public.redeem(%L, %L, null)', c1, w));
  perform pg_temp.supdo(format('update public.rewards set costs = jsonb_build_object(%L, 0) where id = %L', c1::text, wBig));
  res := res || ' 12.prix_nul=' || pg_temp.try(format('select public.redeem(%L, %L, null)', c1, wBig));
  perform pg_temp.supdo(format('update public.rewards set costs = ''{}'' where id = %L', wBig));

  -- ===================== C. Essais limités (ADR-36) =====================
  perform pg_temp.supdo(format('insert into public.invites(code, family_id, created_by, expires_at, role) values (''AAAAAA'', %L, %L, now() + interval ''1 day'', ''parent''), (''BBBBBB'', %L, %L, now() + interval ''1 day'', ''helper'')', fid, u_par, fid, u_par));
  perform pg_temp.as_user(u_out);
  n := 0;
  for i in 1..5 loop if public.join_family('ZZZZZ' || i, 'x') is null then n := n + 1; end if; end loop;
  res := res || ' 13.faux=' || n || '_nuls';
  res := res || ' 13b.bon_pendant_blocage=' || pg_temp.try(format('select public.join_family(%L, ''x'')', 'AAAAAA'));
  perform pg_temp.supdo('update private.code_failures set at = at - interval ''16 minutes'', locked_until = locked_until - interval ''16 minutes''');
  res := res || ' 13c.apres_blocage=' || coalesce((select 'ok' from (select public.join_family('AAAAAA', 'x') as f) q where q.f = fid), 'ko');
  perform pg_temp.as_user(u_par);
  res := res || ' 14.deja_membre=' || pg_temp.try(format('select public.join_family(%L, ''x'')', 'BBBBBB'));
  res := res || ' 14b.code_non_consomme=' || coalesce(pg_temp.sup('select case when used_at is null then ''oui'' else ''non'' end from public.invites where code = ''BBBBBB'''), 'null');
  -- code enfant : clé = connexion internet
  perform pg_temp.hdr('{"x-forwarded-for":"2001:db8:1:2:aaaa::1, 10.0.0.1"}');
  perform pg_temp.as_user(null);
  n := 0;
  for i in 1..5 loop if (public.child_pair('ZZZZZ' || i, null) ->> 'error') = 'bad_code' then n := n + 1; end if; end loop;
  res := res || ' 15.faux=' || n || '_bad_code';
  perform pg_temp.as_user(u_par); v_code2 := public.create_child_code(c1); perform pg_temp.as_user(null);
  res := res || ' 15b.bon_bloque=' || pg_temp.try(format('select public.child_pair(%L, null)', v_code2));
  perform pg_temp.hdr('{"x-forwarded-for":"2001:db8:1:2:bbbb::9"}');
  res := res || ' 15c.meme_64=' || pg_temp.try(format('select public.child_pair(%L, null)', v_code2));
  perform pg_temp.hdr('{"x-forwarded-for":"2001:db8:1:3::1"}');
  res := res || ' 15d.autre_64=' || case when (public.child_pair(v_code2, 'Tel') ->> 'token') is not null then 'ok' else 'ko' end;
  perform pg_temp.hdr('{"x-forwarded-for":"203.0.113.5"}');
  for i in 1..5 loop perform public.child_pair('YYYYY' || i, null); end loop;
  res := res || ' 15e.ipv4=' || pg_temp.try('select public.child_pair(''YYYYY9'', null)');
  perform pg_temp.hdr('{"x-forwarded-for":"203.0.113.6"}');
  res := res || ' 15f.autre_ipv4=' || (public.child_pair('YYYYY9', null) ->> 'error');
  perform pg_temp.hdr('{"cf-connecting-ip":"198.51.100.1","x-forwarded-for":"203.0.113.5"}');
  res := res || ' 15g.cf_prioritaire=' || pg_temp.tq('select public.child_pair(''YYYYY9'', null) ->> ''error''');
  perform pg_temp.hdr('');
  res := res || ' 15h.sans_ip=' || (public.child_pair('YYYYY9', null) ->> 'error');

  -- ===================== D. Appareil : expiration, sortie, purge =====================
  perform pg_temp.as_user(u_par);
  tok2 := (public.child_pair_here(c1, 'Vieux') ->> 'token'); tok3 := (public.child_pair_here(c1, 'Presque') ->> 'token');
  perform pg_temp.supdo(format('update public.child_devices set last_seen = now() - interval ''4 months'' where token_hash = encode(extensions.digest(%L, ''sha256''), ''hex'')', tok2));
  perform pg_temp.supdo(format('update public.child_devices set last_seen = now() - interval ''2 months 29 days'' where token_hash = encode(extensions.digest(%L, ''sha256''), ''hex'')', tok3));
  perform pg_temp.as_user(null);
  res := res || ' 16.perime=' || pg_temp.try(format('select public.child_state(%L)', tok2));
  res := res || ' 16b.2m29j=' || pg_temp.try(format('select public.child_state(%L)', tok3));
  res := res || ' 17.unpair_perime=' || pg_temp.try(format('select public.child_unpair(%L)', tok2)) || '/' ||
    pg_temp.sup(format('select count(*) from public.child_devices where token_hash = encode(extensions.digest(%L, ''sha256''), ''hex'')', tok2));
  res := res || ' 17b.unpair_inconnu=' || pg_temp.try('select public.child_unpair(''inconnu'')');
  res := res || ' 17c.apres=' || pg_temp.try(format('select public.child_state(%L)', tok2));
  -- purge : appareil sans last_seen créé il y a 4 mois, échec vieux de 2 jours, appareil récent
  perform pg_temp.as_user(u_par); tok2 := (public.child_pair_here(c1, 'Jamais rouvert') ->> 'token');
  perform pg_temp.supdo(format('update public.child_devices set created_at = now() - interval ''4 months'', last_seen = null where token_hash = encode(extensions.digest(%L, ''sha256''), ''hex'')', tok2));
  perform pg_temp.supdo('insert into private.code_failures(kind, k, at) values (''pair'', ''vieux'', now() - interval ''2 days'')');
  perform pg_temp.as_user(null);
  res := res || ' 17d.jamais_rouvert=' || pg_temp.try(format('select public.child_state(%L)', tok2));
  perform pg_temp.supdo('select private.purge_daily()');
  res := res || ' 18.purge=' || pg_temp.sup('select count(*) from public.child_devices where created_at < now() - interval ''3 months''') || '_vieux/'
    || pg_temp.sup('select count(*) from private.code_failures where at < now() - interval ''1 day''') || '_echecs/'
    || pg_temp.sup(format('select count(*) from public.child_devices where token_hash = encode(extensions.digest(%L, ''sha256''), ''hex'')', tok3)) || '_recent';
  res := res || ' 18b.cron=' || coalesce(pg_temp.sup('select schedule from cron.job where jobname = ''soisfier-purge-daily'''), 'absent');

  -- ===================== E. Droits et données =====================
  perform pg_temp.as_user(u_par);
  res := res || ' 19.nom_autre=' || pg_temp.try(format('update public.family_members set display_name = ''Autre'' where family_id = %L and user_id = %L', fid, u_help));
  res := res || ' 19b.nom_propre=' || pg_temp.try(format('update public.family_members set display_name = ''Prenom Test Parent'' where family_id = %L and user_id = %L', fid, u_par));
  perform pg_temp.as_user(u_help);
  res := res || ' 19c.nom_proche=' || pg_temp.try(format('update public.family_members set display_name = ''Prenom Test Proche'' where family_id = %L and user_id = %L', fid, u_help));
  -- child_state : lien seul, jamais de prénom d'adulte
  perform pg_temp.as_user(null);
  j := public.child_state(tok);
  res := res || ' 20.lien=' || coalesce((select (x ->> 'validated_rel') || '/' || (x ->> 'validated_label') from json_array_elements(j -> 'completions') x where (x ->> 'routine_id')::uuid = rReg limit 1), 'vide')
    || '/prenom_present=' || (j::text like '%Prenom Test%');
  -- 20b : libellé personnalisé affiché tel quel (F02-04 CA5) ; 20c : validation par un membre retiré = « Validée » (F02-06 CA6)
  perform pg_temp.supdo(format('update public.family_members set relation = ''Nounou Test'' where family_id = %L and user_id = %L', fid, u_par));
  j := public.child_state(tok);
  res := res || ' 20b.libre=' || coalesce((select coalesce(x ->> 'validated_rel', 'sans_cle') || '/' || coalesce(x ->> 'validated_custom', 'vide') from json_array_elements(j -> 'completions') x where (x ->> 'routine_id')::uuid = rReg limit 1), 'vide');
  perform pg_temp.supdo(format('update public.family_members set relation = ''Maman'' where family_id = %L and user_id = %L', fid, u_par));
  perform pg_temp.supdo(format('update public.completions set validated_by = gen_random_uuid() where child_id = (select child_id from public.completions where routine_id = %L limit 1) and routine_id = %L', rReg, rReg));
  j := public.child_state(tok);
  res := res || ' 20c.retire=' || coalesce((select coalesce(x ->> 'validated_label', 'null') || '/' || coalesce(x ->> 'validated_rel', 'null') || '/' || coalesce(x ->> 'validated_custom', 'null') from json_array_elements(j -> 'completions') x where (x ->> 'routine_id')::uuid = rReg limit 1), 'vide');
  -- rappels d'un membre parti
  perform pg_temp.supdo(format('insert into public.push_subscriptions(family_id, user_id, endpoint, p256dh, auth) values (%L, %L, ''https://example.invalid/proche'', ''k'', ''a''), (%L, %L, ''https://example.invalid/parent'', ''k'', ''a''), (%L, %L, ''https://example.invalid/hors'', ''k'', ''a'')', fid, u_help, fid, u_par, fid, u_par2));
  perform pg_temp.supdo(format('update public.push_subscriptions set reminder_times = array[to_char(date_trunc(''minute'', now() at time zone (select timezone from public.families where id = %L)), ''HH24:MI'')] where family_id = %L', fid, fid));
  sec := pg_temp.sup('select value from private.config where key = ''cron_secret''');
  res := res || ' 21.rappels_avant=' || coalesce(pg_temp.sup(format('select json_array_length(public.reminders_due(%L) -> ''items'')', sec)), 'null') || '_envois';
  perform pg_temp.as_user(u_par);
  perform pg_temp.supdo(format('delete from public.family_members where family_id = %L and user_id = %L', fid, u_help));
  res := res || ' 21b.abonnement_membre_parti=' || pg_temp.sup(format('select count(*) from public.push_subscriptions where user_id = %L', u_help)) || '_reste/'
    || pg_temp.sup(format('select count(*) from public.push_subscriptions where user_id = %L', u_par)) || '_parent';
  res := res || ' 21c.non_membre_exclu=' || pg_temp.sup(format('select json_array_length(public.reminders_due(%L) -> ''items'')', sec)) || '_envois';

  -- ===================== F. Avant la migration 2 =====================
  perform pg_temp.as_user(u_par);
  res := res || ' 23.echange_direct_avant=' || pg_temp.try(format('insert into public.redemptions(family_id, child_id, reward_id, title, cost) values (%L, %L, %L, ''x'', 1)', fid, c1, w));
  perform set_config('role', 'postgres', true);
  perform set_config('t.res', res, true);
  perform set_config('t.tok', tok, true);
end $t$;
-- EP-09 thème A (2/2) : retraits et droits par défaut. CONTIENT drop ET revoke : à lancer dans l'ÉDITEUR SQL de Supabase (ADR-07), après ep09a_controles_serveur,
-- et SEULEMENT quand la nouvelle version de l'application est en ligne (elle appelle public.redeem au lieu d'insérer dans redemptions).
-- À tester dans une transaction annulée (supabase/tests/ep09a_controles_test.sql, cas 20 à 27) avant d'appliquer.
--
-- DT04-05  politique routines_delete retirée : l'arrêt (ended_at) reste la seule voie
-- DT06-02  politique redemptions_insert retirée : l'échange passe par public.redeem (ADR-43)
-- DT00-07  fonctions inutilisées private.paris_today, period_bounds, first_end retirées
-- DT00-08  politiques holiday_periods et holiday_overrides recréées pour authenticated (rôle public avant)
-- DT00-22  droits par défaut : EXECUTE retiré sur les fonctions de private, sauf ce qu'appellent les RLS et les contraintes ;
--          droits d'anon retirés sur les tables de public hors languages et tips (lecture seule) ; droits par défaut alignés.
-- Non fait ici : DT11-05 (secrets des rappels, ADR-45), à part.

-- 1. Politiques retirées
drop policy redemptions_insert on public.redemptions;
drop policy routines_delete on public.routines;

-- 2. Politiques de vacances pour authenticated (mêmes conditions qu'avant)
drop policy holiday_periods_select on public.holiday_periods;
drop policy holiday_periods_insert on public.holiday_periods;
drop policy holiday_periods_update on public.holiday_periods;
drop policy holiday_periods_delete on public.holiday_periods;
create policy holiday_periods_select on public.holiday_periods for select to authenticated using ((select private.is_member(holiday_periods.family_id)));
create policy holiday_periods_insert on public.holiday_periods for insert to authenticated with check ((select private.is_parent(holiday_periods.family_id)));
create policy holiday_periods_update on public.holiday_periods for update to authenticated using ((select private.is_parent(holiday_periods.family_id))) with check ((select private.is_parent(holiday_periods.family_id)));
create policy holiday_periods_delete on public.holiday_periods for delete to authenticated using ((select private.is_parent(holiday_periods.family_id)));

drop policy holiday_overrides_select on public.holiday_overrides;
drop policy holiday_overrides_insert on public.holiday_overrides;
drop policy holiday_overrides_update on public.holiday_overrides;
drop policy holiday_overrides_delete on public.holiday_overrides;
create policy holiday_overrides_select on public.holiday_overrides for select to authenticated using ((select private.is_member(holiday_overrides.family_id)));
create policy holiday_overrides_insert on public.holiday_overrides for insert to authenticated with check ((select private.is_parent(holiday_overrides.family_id)));
create policy holiday_overrides_update on public.holiday_overrides for update to authenticated using ((select private.is_parent(holiday_overrides.family_id))) with check ((select private.is_parent(holiday_overrides.family_id)));
create policy holiday_overrides_delete on public.holiday_overrides for delete to authenticated using ((select private.is_parent(holiday_overrides.family_id)));

-- 3. Fonctions inutilisées (period_bounds appelle first_end : dans cet ordre)
drop function private.period_bounds(date, date);
drop function private.first_end(date);
drop function private.paris_today();

-- 4. Fonctions de private : plus aucun droit d'exécution, sauf ce qu'exécutent les RLS (is_member, is_parent), la contrainte de
--    families.timezone (valid_tz) et le déclencheur set_relation_key, qui s'exécute avec les droits de l'appelant (relation_key).
--    Les fonctions SECURITY DEFINER s'appellent entre elles avec les droits de leur propriétaire ; les tâches pg_cron tournent en postgres ;
--    un déclencheur n'a besoin d'aucun droit d'exécution au moment où il se déclenche.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p
           where p.pronamespace = 'private'::regnamespace and p.prokind = 'f' loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('is_member', 'is_parent', 'valid_tz', 'relation_key') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;

-- 5. Fonctions nouvelles de public réservées aux comptes connectés (le droit par défaut les ouvrait aussi à anon)
revoke execute on function public.redeem(uuid, uuid, uuid) from public, anon;
revoke execute on function public.child_pair_here(uuid, text) from public, anon;

-- 6. Tables de public : plus aucun droit pour anon, sauf la lecture de languages et tips (seules tables lues sans compte)
revoke all on all tables in schema public from anon;
grant select on public.languages, public.tips to anon;
revoke all on all sequences in schema public from anon;

-- 7. Droits par défaut des objets créés à l'avenir par postgres (migrations) : rien pour anon, rien pour PUBLIC sur les fonctions
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from anon;
alter default privileges for role postgres revoke execute on functions from public;
do $t$
declare
  u_par uuid; fid uuid; c1 uuid; rB uuid; rReg2 uuid; w uuid; tok text := current_setting('t.tok', true);
  res text := current_setting('t.res', true); n int; nb int; td date;
begin
  select id into u_par from auth.users where email = 'parent.test@example.invalid';
  select id into fid from public.families where name = 'Famille test EP-09A';
  select id into c1 from public.children where family_id = fid;
  select id into rB from public.routines where child_id = c1 and title = 'Routine B';
  select id into rReg2 from public.routines where child_id = c1 and title = 'Routine C';
  select id into w from public.rewards where family_id = fid and title = 'Récompense test';

  td := private.family_today(fid);
  perform pg_temp.as_user(u_par);
  res := res || ' 24.echange_direct_apres=' || pg_temp.try(format('insert into public.redemptions(family_id, child_id, reward_id, title, cost) values (%L, %L, %L, ''x'', 1)', fid, c1, w));
  res := res || ' 24b.echange_serveur=' || pg_temp.try(format('select public.redeem(%L, %L, null)', c1, w));
  -- suppression d'une routine : refus silencieux, la routine reste ; l'arrêt reste possible
  select count(*) into n from public.routines where id = rB;
  delete from public.routines where id = rB;
  res := res || ' 25.suppression_routine=' || (select count(*) from public.routines where id = rB) || '_reste_sur_' || n;
  res := res || ' 25b.arret=' || pg_temp.try(format('update public.routines set active = false where id = %L', rReg2));
  -- parcours normaux avec les droits retirés
  res := res || ' 28.coche=' || pg_temp.try(format('insert into public.completions(family_id, child_id, routine_id, day, source) values (%L, %L, %L, %L, ''parent'')', fid, c1, rB, td - 1));
  res := res || ' 28b.fuseau=' || pg_temp.try(format('update public.families set timezone = ''Europe/Paris'' where id = %L', fid));
  res := res || ' 28c.lien=' || pg_temp.try(format('update public.family_members set relation = ''Tata'' where family_id = %L and user_id = %L', fid, u_par))
    || '/' || coalesce(pg_temp.sup(format('select relation_key from public.family_members where family_id = %L and user_id = %L', fid, u_par)), 'null');
  select count(*) into nb from public.routines where family_id = fid;
  res := res || ' 28d.rls_lecture=' || (nb > 0);
  res := res || ' 28e.routine_premium=' || pg_temp.try(format('insert into public.routines(family_id, child_id, title) values (%L, %L, ''Nouvelle'')', fid, c1));
  res := res || ' 28f.vacances=' || pg_temp.try(format('insert into public.holiday_periods(family_id, child_id, name, start_day, end_day) values (%L, %L, ''V2'', current_date + 40, current_date + 45)', fid, c1));
  perform pg_temp.as_user(null);
  res := res || ' 28g.enfant_etat=' || pg_temp.try(format('select public.child_state(%L)', tok));
  res := res || ' 28h.enfant_coche=' || pg_temp.try(format('select public.child_toggle(%L, %L, %L, true, ''child'')', tok, rB, td));
  res := res || ' 28i.anon_tips=' || pg_temp.try('select count(*) from public.tips');
  res := res || ' 28j.anon_routines=' || pg_temp.try('select count(*) from public.routines');
  perform set_config('role', 'postgres', true);
  res := res || ' 26.droits=rules_auth:' || has_function_privilege('authenticated', 'private.routine_rules(uuid,date)', 'execute')
    || '/is_member:' || has_function_privilege('authenticated', 'private.is_member(uuid)', 'execute')
    || '/valid_tz:' || has_function_privilege('authenticated', 'private.valid_tz(text)', 'execute')
    || '/relation_key:' || has_function_privilege('authenticated', 'private.relation_key(text)', 'execute')
    || '/anon_toggle:' || has_function_privilege('anon', 'public.child_toggle(text,uuid,date,boolean,text)', 'execute')
    || '/anon_unpair:' || has_function_privilege('anon', 'public.child_unpair(text)', 'execute')
    || '/anon_redeem:' || has_function_privilege('anon', 'public.redeem(uuid,uuid,uuid)', 'execute')
    || '/auth_redeem:' || has_function_privilege('authenticated', 'public.redeem(uuid,uuid,uuid)', 'execute')
    || '/anon_pair_here:' || has_function_privilege('anon', 'public.child_pair_here(uuid,text)', 'execute')
    || '/anon_routines:' || has_table_privilege('anon', 'public.routines', 'select')
    || '/anon_tips:' || has_table_privilege('anon', 'public.tips', 'select')
    || '/anon_tips_insert:' || has_table_privilege('anon', 'public.tips', 'insert')
    || '/sauvegarde_code_failures:' || has_table_privilege('soisfier_sauvegarde', 'private.code_failures', 'select')
    || '/fonctions_retirees:' || (to_regprocedure('private.paris_today()') is null and to_regprocedure('private.first_end(date)') is null and to_regprocedure('private.period_bounds(date,date)') is null);
  res := res || ' 27.politiques_vacances=' || (select count(*) from pg_policies where tablename in ('holiday_periods', 'holiday_overrides') and roles <> '{authenticated}') || '_hors_authenticated/'
    || (select count(*) from pg_policies where tablename in ('holiday_periods', 'holiday_overrides')) || '_total';
  res := res || ' 29.fonctions_private_exposees=' || (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace
      and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
      and p.proname not in ('is_member', 'is_parent', 'valid_tz', 'relation_key'));
  raise exception 'RESULT:%', res;
end $t$;
rollback;
