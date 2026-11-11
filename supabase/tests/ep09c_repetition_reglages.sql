-- Répétition de la migration ep09c_reglages_historises sur les DONNÉES RÉELLES, dans une transaction annulée (DEC-33, ADR-42).
-- À lancer dans l'éditeur SQL de Supabase AVANT d'appliquer la migration, avec l'accord de la personne qui pilote (le script écrit puis annule tout).
-- Il prend une photo des routines dues (private.routine_rules) de chaque enfant sur les 70 jours passés et les 7 jours à venir, applique la migration,
-- reprend la photo et compare. Résultat attendu : une seule ligne d'erreur « RESULT: … » avec  differences_routines_dues=0  differences_historique=0
-- et reglages = nombre de routines habituelles (routines_habituelles). differences_jours_jardin peut être > 0 seulement pour des exceptionnelles arrêtées
-- (elles gardent désormais leur place dans les jours passés, DT04-04) : la liste est donnée dans « jardin ».
-- Fichier composé : photo avant + migration 20261112120000 + comparaison. Rien n'est conservé (la ligne d'erreur finale annule la transaction).
begin;
create temp table avant_regles on commit drop as
  select c.id as child_id, g::date as day, rr.routine_id, rr.stars, rr.is_bonus, rr.moment
  from public.children c cross join generate_series(current_date - 70, current_date + 7, interval '1 day') g
  cross join lateral private.routine_rules(c.id, g::date) rr;
create temp table avant_jardin on commit drop as
  select c.id as child_id, gd.day, gd.due, gd.earned, gd.paused, gd.good
  from public.children c cross join lateral private.garden_days(c.id, current_date - 70, current_date + 7) gd;
create temp table avant_histo on commit drop as select c.id as child_id, private.history_counters(c.id) as h from public.children c where c.garden_start is not null;

-- [migration] EP-09 thème C (1/3) : réglages des routines historisés (ADR-42, DEC-33, DT04-02, DT04-04, DT10-11).
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
declare dr int; dj int; dh int; nr int; ns int; nb int; na int; lst text;
begin
  create temp table apres_regles on commit drop as
    select c.id as child_id, g::date as day, rr.routine_id, rr.stars, rr.is_bonus, rr.moment
    from public.children c cross join generate_series(current_date - 70, current_date + 7, interval '1 day') g
    cross join lateral private.routine_rules(c.id, g::date) rr;
  select count(*) into na from avant_regles; select count(*) into nb from apres_regles;
  select count(*) into dr from ((select * from avant_regles except select * from apres_regles) union all (select * from apres_regles except select * from avant_regles)) x;
  create temp table apres_jardin on commit drop as
    select c.id as child_id, gd.day, gd.due, gd.earned, gd.paused, gd.good
    from public.children c cross join lateral private.garden_days(c.id, current_date - 70, current_date + 7) gd;
  select count(*), string_agg(distinct child_id::text || ':' || day::text, ',') into dj, lst from ((select * from avant_jardin except select * from apres_jardin) union all (select * from apres_jardin except select * from avant_jardin)) x;
  select count(*) into dh from avant_histo a join lateral (select private.history_counters(a.child_id) as h2) z on true where a.h is distinct from z.h2;
  select count(*) into nr from public.routines where kind = 'regular';
  select count(*) into ns from public.routine_settings;
  raise exception 'RESULT: routines_dues_avant=% routines_dues_apres=% differences_routines_dues=% differences_historique=% differences_jours_jardin=% routines_habituelles=% reglages=% jardin=%', na, nb, dr, dh, dj, nr, ns, coalesce(left(lst, 400), '-');
end $t$;
