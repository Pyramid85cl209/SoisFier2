-- Test du jeu de cas partagé (EP-09 thème C, DT10-01) : à lancer dans l'éditeur SQL de Supabase AVANT d'appliquer la migration ep09c_reglages_historises
-- (elle contient des revoke : confirmation demandée). Transaction annulée : familles, enfants, routines fictifs, rien n'est conservé.
-- Suppose la migration ep09a_controles_serveur appliquée (ou lancée avant dans la même transaction).
-- Fichier composé : cat migrations/20261112120000_ep09c_reglages_historises.sql tests/ep09c_regles_cases.sql
-- Les 30 cas de supabase/tests/regles_cas.json (79 vérifications) sont rejoués ici contre private.routine_rules et private.garden_days ; les mêmes cas sont joués contre rules.js :
-- node supabase/tests/regles_cas.test.js (153 vérifications).
-- Résultat attendu : une seule ligne d'erreur « RESULT: 79 vérifications, 0 échec(s) | … » avec, dans l'ordre, un contrôle nommé par cas du jeu partagé :
--  R01=ok R02=ok R03=ok R04=ok R05=ok R06=ok R07=ok R08=ok R09=ok R10=ok R11=ok R12=ok R13=ok R14=ok R15=ok R16=ok R17=ok R18=ok R19=ok R20=ok R21=ok R22=ok O01=ok O02=ok O03=ok O04=ok O05=ok O06=ok O07=ok O08=ok
begin;
-- EP-09 thème C (1/3) : réglages des routines historisés (ADR-42, DEC-33, DT04-02, DT04-04, DT10-11).
-- À appliquer SEULE, avant la publication de l'application, après répétition sur les données réelles dans une transaction annulée
-- (supabase/tests/ep09c_repetition_reglages.sql : les routines dues doivent rester identiques sur 60 jours).
-- Contient des revoke (droits de la nouvelle table) et des drop de ses propres déclencheurs et politique : à lancer dans l'ÉDITEUR SQL de Supabase,
-- puis à enregistrer dans supabase_migrations.schema_migrations (version 20261112120000, nom ep09c_reglages_historises).
-- Compatible avec l'ancienne version de l'application : elle ignore la table ; les routines modifiées gardent leurs jours passés.
--
-- Une ligne par routine habituelle (et de vacances) et par changement de jours, de statut bonus ou d'étoiles, valable à partir du
-- jour de la famille où le changement est fait ; la première ligne vaut dès le jour de création. Les jours passés gardent leurs réglages.

-- 1. Table (écrite par déclencheur seulement : aucune politique d'écriture)
create table if not exists public.routine_settings (
  routine_id uuid not null references public.routines(id) on delete cascade,
  family_id  uuid not null,
  valid_from date not null,
  days       smallint[] not null,
  is_bonus   boolean not null,
  stars      integer not null,
  primary key (routine_id, valid_from)
);
create index if not exists routine_settings_family_idx on public.routine_settings (family_id);
alter table public.routine_settings enable row level security;
drop policy if exists routine_settings_select on public.routine_settings;
create policy routine_settings_select on public.routine_settings for select to authenticated using ((select private.is_member(family_id)));
revoke all on public.routine_settings from public, anon, authenticated;
grant select on public.routine_settings to authenticated;

-- 2. Reprise de l'existant : réglages actuels, valables dès la création (aucun changement de comportement)
insert into public.routine_settings (routine_id, family_id, valid_from, days, is_bonus, stars)
select r.id, r.family_id, (r.created_at at time zone private.family_tz(r.family_id))::date, r.days, r.is_bonus, r.stars
from public.routines r where r.kind = 'regular'
on conflict (routine_id, valid_from) do nothing;

-- 3. Déclencheurs : écriture à la création et à chaque changement des jours, du statut bonus ou des étoiles
create or replace function private.routine_settings_write() returns trigger
language plpgsql security definer set search_path = '' as $$
declare d date;
begin
  if new.kind <> 'regular' then return null; end if;
  if tg_op = 'INSERT' then
    d := (new.created_at at time zone private.family_tz(new.family_id))::date;
  else
    if new.days is not distinct from old.days and new.is_bonus is not distinct from old.is_bonus and new.stars is not distinct from old.stars then return null; end if;
    d := private.family_today(new.family_id);
  end if;
  insert into public.routine_settings (routine_id, family_id, valid_from, days, is_bonus, stars)
  values (new.id, new.family_id, d, new.days, new.is_bonus, new.stars)
  on conflict (routine_id, valid_from) do update set days = excluded.days, is_bonus = excluded.is_bonus, stars = excluded.stars;
  return null;
end $$;
revoke execute on function private.routine_settings_write() from public, anon, authenticated;
drop trigger if exists routines_settings_ins on public.routines;
create trigger routines_settings_ins after insert on public.routines for each row execute function private.routine_settings_write();
drop trigger if exists routines_settings_upd on public.routines;
create trigger routines_settings_upd after update of days, is_bonus, stars on public.routines for each row execute function private.routine_settings_write();

-- 4. routine_rules lit la ligne valable au jour demandé (à défaut, la plus ancienne, puis la routine elle-même)
create or replace function private.routine_rules(p_child uuid, p_day date)
returns table(routine_id uuid, stars integer, is_bonus boolean, moment text)
language sql stable security definer set search_path = '' as $$
  with z as (select private.family_tz(c.family_id) as tz from public.children c where c.id = p_child),
  hp as (select p.id from public.holiday_periods p
         where p.child_id = p_child and p.active and p_day between p.start_day and p.end_day limit 1)
  select r.id, coalesce(o.stars, sa.stars, sb.stars, r.stars)::int,
    case o.status when 'bonus' then true when 'required' then false else coalesce(sa.is_bonus, sb.is_bonus, r.is_bonus) end, r.moment
  from public.routines r
  left join lateral (select rs.* from public.routine_settings rs where rs.routine_id = r.id and rs.valid_from <= p_day order by rs.valid_from desc limit 1) sa on true
  left join lateral (select rs.* from public.routine_settings rs where rs.routine_id = r.id order by rs.valid_from limit 1) sb on true
  left join public.holiday_overrides o on o.routine_id = r.id and o.period_id = (select id from hp)
  where r.child_id = p_child and r.kind = 'regular'
    and (r.created_at at time zone (select tz from z))::date <= p_day
    and (r.ended_at is null or (r.ended_at at time zone (select tz from z))::date > p_day)
    and coalesce(o.days, sa.days, sb.days, r.days) @> array[extract(isodow from p_day)::smallint]
    and case when r.holiday_period_id is null then o.status is distinct from 'off'
             else r.holiday_period_id = (select id from hp) end
$$;

-- 5. Exceptionnelle arrêtée (DT04-04) : elle garde sa place dans les jours passés (jusqu'au jour de l'arrêt exclu)
create or replace function private.garden_days(p_child uuid, p_from date, p_to date)
returns table(day date, due integer, earned integer, paused boolean, good boolean)
language sql stable security definer set search_path = '' as $$
  with d as (
    select g::date as day,
      (coalesce((select sum(rr.stars) from private.routine_rules(p_child, g::date) rr where not rr.is_bonus), 0)
      + coalesce((select sum(r.stars) from public.routines r
        where r.child_id = p_child and r.kind = 'oneoff' and not r.is_bonus
          and case when r.ended_at is not null then (r.ended_at at time zone private.family_tz(r.family_id))::date > g::date else r.active end
          and g::date between r.start_day and r.end_day
          and (exists (select 1 from public.completions c where c.routine_id = r.id and c.day = g::date)
               or (g::date = r.end_day and not exists (select 1 from public.completions c where c.routine_id = r.id)))), 0))::int as due,
      coalesce((select sum(c.stars) from public.completions c
        where c.child_id = p_child and c.day = g::date and c.validated_at is not null), 0)::int as earned,
      exists (select 1 from public.pauses p where p.child_id = p_child and g::date between p.start_day and p.end_day) as paused
    from generate_series(p_from, p_to, interval '1 day') g
  )
  select day, due, earned, paused, (not paused and due > 0 and earned >= ceil(due * 0.75)) as good from d;
$$;

-- 6. child_state : les réglages de chaque routine (historique) pour l'écran de l'enfant. Le reste est identique à la version de ep09a.
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
        (select id, title, emoji, place, moment, stars, days, is_bonus, timer_minutes, position, created_at, kind, start_day, end_day, holiday_period_id,
           coalesce((select json_agg(json_build_object('valid_from', s.valid_from, 'days', s.days, 'is_bonus', s.is_bonus, 'stars', s.stars) order by s.valid_from)
                     from public.routine_settings s where s.routine_id = routines.id), '[]'::json) as settings
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
  b0 int; per text := '';
  doc jsonb := $json${
 "version": 1,
 "description": "Jeu de cas partagé (EP-09, DT10-01) : routines dues, réglages valables au jour demandé, vacances, exceptionnelles dans le compteur du jour. Joué en SQL (supabase/tests/ep09c_regles_test.sql) et sous Node (supabase/tests/regles_cas.test.js). Fuseau par défaut Europe/Paris ; jours 1 = lundi à 7 = dimanche.",
 "timezone": "Europe/Paris",
 "cases": [
  {"id": "R01", "kind": "regular", "title": "Jours choisis, avant et après la création (créée le mardi 1er septembre)", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false, "moment": "matin"}, "checks": [{"day": "2026-08-31", "due": false}, {"day": "2026-09-01", "due": true, "stars": 2, "bonus": false}, {"day": "2026-09-05", "due": false}, {"day": "2026-09-07", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R02", "kind": "regular", "title": "Création le soir (UTC) = jour suivant à Paris", "routine": {"created": "2026-09-06T22:30:00Z", "ended": null, "days": [1, 2, 3, 4, 5, 6, 7], "stars": 2, "bonus": false, "moment": "matin"}, "checks": [{"day": "2026-09-06", "due": false}, {"day": "2026-09-07", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R03", "kind": "regular", "title": "Arrêtée le jeudi 10 : due jusqu'au mercredi", "routine": {"created": "2026-09-01T08:00:00Z", "ended": "2026-09-10T10:00:00Z", "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false, "moment": "matin"}, "checks": [{"day": "2026-09-09", "due": true, "stars": 2, "bonus": false}, {"day": "2026-09-10", "due": false}, {"day": "2026-09-11", "due": false}]},
  {"id": "R04", "kind": "regular", "title": "Arrêt le soir (UTC) = jour suivant à Paris", "routine": {"created": "2026-09-01T08:00:00Z", "ended": "2026-09-09T22:30:00Z", "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false, "moment": "matin"}, "checks": [{"day": "2026-09-09", "due": true, "stars": 2, "bonus": false}, {"day": "2026-09-10", "due": false}]},
  {"id": "R05", "kind": "regular", "title": "Jours changés le jeudi 8 octobre : les jours avant gardent lundi à vendredi", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1], "stars": 2, "bonus": false, "moment": "matin"}, "settings": [{"from": "2026-09-01", "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false}, {"from": "2026-10-08", "days": [1], "stars": 2, "bonus": false}], "checks": [{"day": "2026-10-06", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-07", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-08", "due": false}, {"day": "2026-10-12", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-13", "due": false}]},
  {"id": "R06", "kind": "regular", "title": "Statut bonus changé le jeudi 8 octobre", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": true, "moment": "matin"}, "settings": [{"from": "2026-09-01", "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false}, {"from": "2026-10-08", "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": true}], "checks": [{"day": "2026-10-07", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-08", "due": true, "stars": 2, "bonus": true}]},
  {"id": "R07", "kind": "regular", "title": "Étoiles changées le jeudi 8 octobre (2 puis 5)", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5], "stars": 5, "bonus": false, "moment": "matin"}, "settings": [{"from": "2026-09-01", "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false}, {"from": "2026-10-08", "days": [1, 2, 3, 4, 5], "stars": 5, "bonus": false}], "checks": [{"day": "2026-10-07", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-08", "due": true, "stars": 5, "bonus": false}]},
  {"id": "R08", "kind": "regular", "title": "Première ligne postérieure à la création : la plus ancienne sert aux jours d'avant", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false, "moment": "matin"}, "settings": [{"from": "2026-09-10", "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false}], "checks": [{"day": "2026-09-03", "due": true, "stars": 2, "bonus": false}, {"day": "2026-09-10", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R09", "kind": "regular", "title": "Sans historique : la routine elle-même", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [3], "stars": 2, "bonus": false, "moment": "matin"}, "settings": [], "checks": [{"day": "2026-09-02", "due": true, "stars": 2, "bonus": false}, {"day": "2026-09-03", "due": false}]},
  {"id": "R10", "kind": "regular", "title": "Vacances : routine mise en pause (off)", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false, "moment": "matin"}, "period": {"start": "2026-10-05", "end": "2026-10-11"}, "override": {"status": "off"}, "checks": [{"day": "2026-10-06", "due": false}, {"day": "2026-10-12", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R11", "kind": "regular", "title": "Vacances : routine passée en bonus", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false, "moment": "matin"}, "period": {"start": "2026-10-05", "end": "2026-10-11"}, "override": {"status": "bonus"}, "checks": [{"day": "2026-10-06", "due": true, "stars": 2, "bonus": true}, {"day": "2026-10-12", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R12", "kind": "regular", "title": "Vacances : routine bonus rendue obligatoire", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": true, "moment": "matin"}, "period": {"start": "2026-10-05", "end": "2026-10-11"}, "override": {"status": "required"}, "checks": [{"day": "2026-10-06", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-12", "due": true, "stars": 2, "bonus": true}]},
  {"id": "R13", "kind": "regular", "title": "Vacances : jours remplacés par le week-end", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false, "moment": "matin"}, "period": {"start": "2026-10-05", "end": "2026-10-11"}, "override": {"days": [6, 7]}, "checks": [{"day": "2026-10-06", "due": false}, {"day": "2026-10-10", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-12", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R14", "kind": "regular", "title": "Vacances : étoiles remplacées", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false, "moment": "matin"}, "period": {"start": "2026-10-05", "end": "2026-10-11"}, "override": {"stars": 7}, "checks": [{"day": "2026-10-06", "due": true, "stars": 7, "bonus": false}, {"day": "2026-10-12", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R15", "kind": "regular", "title": "Routine de vacances : due seulement dans sa période", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5, 6, 7], "stars": 2, "bonus": false, "moment": "matin"}, "period": {"start": "2026-10-05", "end": "2026-10-11"}, "holiday_routine": true, "checks": [{"day": "2026-10-04", "due": false}, {"day": "2026-10-05", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-11", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-12", "due": false}]},
  {"id": "R16", "kind": "regular", "title": "Routine de vacances sans période active : jamais due", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5, 6, 7], "stars": 2, "bonus": false, "moment": "matin"}, "period": {"start": "2026-10-05", "end": "2026-10-11", "active": false}, "holiday_routine": true, "checks": [{"day": "2026-10-06", "due": false}, {"day": "2026-10-12", "due": false}]},
  {"id": "R17", "kind": "regular", "title": "Vacances désactivées : la routine garde son rythme", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false, "moment": "matin"}, "period": {"start": "2026-10-05", "end": "2026-10-11", "active": false}, "override": {"status": "off"}, "checks": [{"day": "2026-10-06", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R18", "kind": "regular", "title": "Tous les jours, week-end compris", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5, 6, 7], "stars": 2, "bonus": false, "moment": "matin"}, "checks": [{"day": "2026-09-05", "due": true, "stars": 2, "bonus": false}, {"day": "2026-09-06", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R19", "kind": "regular", "title": "Trois réglages successifs", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [5], "stars": 2, "bonus": false, "moment": "matin"}, "settings": [{"from": "2026-09-01", "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false}, {"from": "2026-09-14", "days": [1, 3], "stars": 2, "bonus": false}, {"from": "2026-10-05", "days": [5], "stars": 2, "bonus": false}], "checks": [{"day": "2026-09-11", "due": true, "stars": 2, "bonus": false}, {"day": "2026-09-14", "due": true, "stars": 2, "bonus": false}, {"day": "2026-09-15", "due": false}, {"day": "2026-09-16", "due": true, "stars": 2, "bonus": false}, {"day": "2026-09-18", "due": false}, {"day": "2026-10-05", "due": false}, {"day": "2026-10-09", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R20", "kind": "regular", "title": "Fuseau lointain : création le lundi matin à Auckland", "routine": {"created": "2026-09-06T20:00:00Z", "ended": null, "days": [1, 2, 3, 4, 5, 6, 7], "stars": 2, "bonus": false, "moment": "matin"}, "timezone": "Pacific/Auckland", "checks": [{"day": "2026-09-06", "due": false}, {"day": "2026-09-07", "due": true, "stars": 2, "bonus": false}]},
  {"id": "R21", "kind": "regular", "title": "Réglage et vacances ensemble : les jours de vacances l'emportent sur les réglages", "routine": {"created": "2026-09-01T08:00:00Z", "ended": null, "days": [1], "stars": 2, "bonus": false, "moment": "matin"}, "settings": [{"from": "2026-09-01", "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false}, {"from": "2026-10-01", "days": [1], "stars": 2, "bonus": false}], "period": {"start": "2026-10-05", "end": "2026-10-11"}, "override": {"days": [2]}, "checks": [{"day": "2026-10-06", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-05", "due": false}]},
  {"id": "R22", "kind": "regular", "title": "Arrêtée avec des réglages : due jusqu'à la veille, avec les réglages du jour", "routine": {"created": "2026-09-01T08:00:00Z", "ended": "2026-10-14T09:00:00Z", "days": [1, 2, 3], "stars": 2, "bonus": false, "moment": "matin"}, "settings": [{"from": "2026-09-01", "days": [1, 2, 3, 4, 5], "stars": 2, "bonus": false}, {"from": "2026-10-08", "days": [1, 2, 3], "stars": 2, "bonus": false}], "checks": [{"day": "2026-10-07", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-09", "due": false}, {"day": "2026-10-13", "due": true, "stars": 2, "bonus": false}, {"day": "2026-10-14", "due": false}]},
  {"id": "O01", "kind": "oneoff", "title": "« Avant le » vendredi 9, non faite : comptée seulement le dernier jour", "oneoff": {"start": "2026-10-05", "end": "2026-10-09", "stars": 3, "bonus": false, "ended": null}, "completions": [], "checks": [{"day": "2026-10-05", "counted": false}, {"day": "2026-10-07", "counted": false}, {"day": "2026-10-09", "counted": true}]},
  {"id": "O02", "kind": "oneoff", "title": "« Avant le » vendredi 9, faite le mercredi 7 : comptée le mercredi", "oneoff": {"start": "2026-10-05", "end": "2026-10-09", "stars": 3, "bonus": false, "ended": null}, "completions": ["2026-10-07"], "checks": [{"day": "2026-10-06", "counted": false}, {"day": "2026-10-07", "counted": true}, {"day": "2026-10-09", "counted": false}]},
  {"id": "O03", "kind": "oneoff", "title": "Exceptionnelle d'un seul jour, non faite", "oneoff": {"start": "2026-10-07", "end": "2026-10-07", "stars": 3, "bonus": false, "ended": null}, "completions": [], "checks": [{"day": "2026-10-06", "counted": false}, {"day": "2026-10-07", "counted": true}, {"day": "2026-10-08", "counted": false}]},
  {"id": "O04", "kind": "oneoff", "title": "Hors de ses dates", "oneoff": {"start": "2026-10-05", "end": "2026-10-09", "stars": 3, "bonus": false, "ended": null}, "completions": [], "checks": [{"day": "2026-10-04", "counted": false}, {"day": "2026-10-10", "counted": false}]},
  {"id": "O05", "kind": "oneoff", "title": "Exceptionnelle bonus : jamais comptée", "oneoff": {"start": "2026-10-05", "end": "2026-10-09", "stars": 3, "bonus": true, "ended": null}, "completions": [], "checks": [{"day": "2026-10-07", "counted": false}, {"day": "2026-10-09", "counted": false}]},
  {"id": "O06", "kind": "oneoff", "title": "Arrêtée le jeudi 8 après une coche le mercredi 7 : le passé reste", "oneoff": {"start": "2026-10-05", "end": "2026-10-09", "stars": 3, "bonus": false, "ended": "2026-10-08T10:00:00Z"}, "completions": ["2026-10-07"], "checks": [{"day": "2026-10-07", "counted": true}, {"day": "2026-10-08", "counted": false}, {"day": "2026-10-09", "counted": false}]},
  {"id": "O07", "kind": "oneoff", "title": "Arrêtée le jeudi 8, dernier jour le mercredi 7, non faite : comptée son dernier jour", "oneoff": {"start": "2026-10-05", "end": "2026-10-07", "stars": 3, "bonus": false, "ended": "2026-10-08T10:00:00Z"}, "completions": [], "checks": [{"day": "2026-10-07", "counted": true}, {"day": "2026-10-08", "counted": false}]},
  {"id": "O08", "kind": "oneoff", "title": "Faite le dernier jour : comptée ce jour-là", "oneoff": {"start": "2026-10-05", "end": "2026-10-09", "stars": 3, "bonus": false, "ended": null}, "completions": ["2026-10-09"], "checks": [{"day": "2026-10-08", "counted": false}, {"day": "2026-10-09", "counted": true}]}
 ]
}$json$::jsonb;
  c jsonb; k jsonb; s jsonb; fid uuid; cid uuid; rid uuid; pid uuid; tz text; r jsonb; d text; o jsonb;
  n int := 0; bad int := 0; detail text := ''; got boolean; gs int; gb boolean; cnt int; v int;
begin
  perform set_config('sf.via_report', 'on', true);   -- jours anciens : exemption de check_completion (report de feuille)
  execute 'alter table public.holiday_periods disable trigger holiday_periods_check';   -- périodes aux dates fixes, quelle que soit la date du jour
  for c in select * from jsonb_array_elements(doc -> 'cases') loop
    b0 := bad;
    tz := coalesce(c ->> 'timezone', doc ->> 'timezone');
    insert into public.families(name, plan, timezone) values ('Famille cas ' || (c ->> 'id'), 'premium', tz) returning id into fid;
    insert into public.children(family_id, name) values (fid, 'Enfant') returning id into cid;
    if c ->> 'kind' = 'regular' then
      r := c -> 'routine';
      if c ? 'period' then
        insert into public.holiday_periods(family_id, child_id, name, start_day, end_day, active)
        values (fid, cid, 'P', (c #>> '{period,start}')::date, (c #>> '{period,end}')::date, coalesce((c #>> '{period,active}')::boolean, true)) returning id into pid;
      end if;
      insert into public.routines(family_id, child_id, title, moment, stars, days, is_bonus, created_at, ended_at, active, holiday_period_id)
      values (fid, cid, 'R', r ->> 'moment', (r ->> 'stars')::int, array(select jsonb_array_elements_text(r -> 'days')::smallint)::smallint[], (r ->> 'bonus')::boolean,
              (r ->> 'created')::timestamptz, (r ->> 'ended')::timestamptz, (r ->> 'ended') is null, case when c ? 'holiday_routine' then pid end) returning id into rid;
      if c ? 'settings' then
        delete from public.routine_settings where routine_id = rid;
        for s in select * from jsonb_array_elements(c -> 'settings') loop
          insert into public.routine_settings(routine_id, family_id, valid_from, days, is_bonus, stars)
          values (rid, fid, (s ->> 'from')::date, array(select jsonb_array_elements_text(s -> 'days')::smallint)::smallint[], (s ->> 'bonus')::boolean, (s ->> 'stars')::int);
        end loop;
      end if;
      if c ? 'override' then
        insert into public.holiday_overrides(period_id, routine_id, child_id, family_id, status, days, stars)
        values (pid, rid, cid, fid, c #>> '{override,status}', case when c #> '{override,days}' is null then null else array(select jsonb_array_elements_text(c #> '{override,days}')::smallint)::smallint[] end, (c #>> '{override,stars}')::int);
      end if;
      for k in select * from jsonb_array_elements(c -> 'checks') loop
        n := n + 1;
        select count(*), max(rr.stars), bool_or(rr.is_bonus) into cnt, gs, gb from private.routine_rules(cid, (k ->> 'day')::date) rr where rr.routine_id = rid;
        if (cnt = 1) is distinct from (k ->> 'due')::boolean then bad := bad + 1; detail := detail || ' ' || (c ->> 'id') || '/' || (k ->> 'day') || ':due=' || (cnt = 1); continue; end if;
        if cnt = 1 and k ? 'stars' and gs is distinct from (k ->> 'stars')::int then bad := bad + 1; detail := detail || ' ' || (c ->> 'id') || '/' || (k ->> 'day') || ':stars=' || gs; end if;
        if cnt = 1 and k ? 'bonus' and gb is distinct from (k ->> 'bonus')::boolean then bad := bad + 1; detail := detail || ' ' || (c ->> 'id') || '/' || (k ->> 'day') || ':bonus=' || gb; end if;
      end loop;
    else
      o := c -> 'oneoff';
      insert into public.routines(family_id, child_id, title, stars, is_bonus, kind, start_day, end_day, created_at)
      values (fid, cid, 'E', (o ->> 'stars')::int, (o ->> 'bonus')::boolean, 'oneoff', (o ->> 'start')::date, (o ->> 'end')::date, (o ->> 'start')::date) returning id into rid;
      if (o ->> 'ended') is not null then
        update public.routines set active = false where id = rid;
        update public.routines set ended_at = (o ->> 'ended')::timestamptz where id = rid;
      end if;
      for d in select jsonb_array_elements_text(c -> 'completions') loop
        insert into public.completions(family_id, child_id, routine_id, day, source) values (fid, cid, rid, d::date, 'parent');
      end loop;
      for k in select * from jsonb_array_elements(c -> 'checks') loop
        n := n + 1;
        select gd.due into v from private.garden_days(cid, (k ->> 'day')::date, (k ->> 'day')::date) gd;
        if (v > 0) is distinct from (k ->> 'counted')::boolean then bad := bad + 1; detail := detail || ' ' || (c ->> 'id') || '/' || (k ->> 'day') || ':compte=' || v; end if;
      end loop;
    end if;
    per := per || ' ' || (c ->> 'id') || '=' || case when bad = b0 then 'ok' else 'KO' end;
  end loop;
  execute 'alter table public.holiday_periods enable trigger holiday_periods_check';
  raise exception 'RESULT: % vérifications, % échec(s)% |%', n, bad, detail, per;
end $t$;
rollback;
