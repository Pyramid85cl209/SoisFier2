-- Test des migrations ep09c (thème C : réglages historisés, badges par le serveur) : à lancer AVANT d'appliquer les migrations, dans l'éditeur SQL de Supabase
-- (elle contient des revoke et des drop : confirmation demandée). Transaction annulée : familles, enfants, utilisateurs, badges fictifs, rien n'est conservé.
-- Suppose la migration ep09a_controles_serveur appliquée (ou lancée avant dans la même transaction).
-- Contenu : migration 1 (20261112120000), migration 2 (20261112121000), cas T1 à B7c, migration 3 (20261112122000, retraits), cas B8 à B8c.
-- Résultat attendu : une seule ligne d'erreur « RESULT: … » contenant, dans l'ordre :
--  T1.creation=1/true T2.titre_seul=1 T2b.etoiles=2/true/6 T2c.meme_jour=2/7:1,2,3 T2d.inchange=2 T3.ecriture_directe=permission denied for table routine_settings T3b.lecture_membre=2
--  T3c.anon=permission denied for table routine_settings T4.passe_fige=true/best=12
--  B1.badges=calme14,calme30,calme7,f1,first,full1,matin,patience30,r10,s25,save50 B1b.annonce=11 B2.idempotent=0
--  B3.gratuit=calme14:true,calme30:true,calme7:true,first:false,full1:true,matin:true,patience30:true,timer:true B3b.premium=true
--  B4.jardin=big,big5,f1,f10,f5,first,full1,jardin,jardin2,jcomplet,p_automne,p_ete,p_hiver,p_printemps,parfait,parterre,parterre5 B5.bonus_selon_le_jour=1
--  B6.etat=nouveaux:26/reglages:2 B6b.apres_vu=0 B7.anon_attribution=permission denied for schema private B7b.auth_attribution=permission denied for function award_badges
--  B7c.insertion_directe_avant=ok B8.fonction_retiree=true B8b.insertion_directe_apres=new row violates row-level security policy for table "child_badges" B8c.lecture=true
-- Lancé jusqu'ici sur une réplique locale du schéma (PostgreSQL 16), pas sur la base de production.
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

-- EP-09 thème C (2/3) : badges calculés et enregistrés par le serveur (ADR-44, DT09-01, DT09-02, DT09-03).
-- Ajouts et remplacements, une colonne et des fonctions : aucun drop ni delete exécuté (revoke d'exécution sur des fonctions neuves seulement).
-- À appliquer APRÈS ep09c_reglages_historises ; compatible avec l'ancienne application (elle continue d'enregistrer ses badges, sans doublon).
-- Les retraits (child_award_badges, badges_insert) sont dans ep09c_retraits_badges, à lancer quand la nouvelle application est en ligne.
-- À tester dans une transaction annulée (supabase/tests/ep09c_badges_test.sql).
--
-- Catalogue de 92 badges porté en SQL (mêmes clés que rules.js : buildBadges), mérite calculé comme badgeStats ; badges Premium d'une famille gratuite
-- enregistrés sans annonce (shown_at renseigné), comme avant. Jours neutres ignorés (history_counters), jour et dates de la famille.

alter table public.child_badges add column if not exists shown_at timestamptz;
-- badges déjà enregistrés : déjà connus de l'enfant, pas d'annonce
update public.child_badges set shown_at = earned_at where shown_at is null;

-- Compteur des routines bonus, selon le statut bonus valable le jour de chaque coche (réglages historisés, DEC-33)
create or replace function private.bonus_count(p_child uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::int
  from public.completions x
  join public.routines r on r.id = x.routine_id
  left join lateral (select rs.is_bonus from public.routine_settings rs where rs.routine_id = r.id and rs.valid_from <= x.day order by rs.valid_from desc limit 1) sa on true
  left join lateral (select rs.is_bonus from public.routine_settings rs where rs.routine_id = r.id order by rs.valid_from limit 1) sb on true
  where x.child_id = p_child and x.validated_at is not null and coalesce(sa.is_bonus, sb.is_bonus, r.is_bonus)
$$;

-- Badges mérités d'un enfant, enregistrés une fois pour toutes ; renvoie le nombre de badges nouveaux
create or replace function private.award_badges(p_child uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  c record; today date; h jsonb; tg record; cur int; s record; m jsonb; n int := 0; prem boolean;
  cur_s text; cur_y text; fl int; big int; beds int; gardens int; perfect_beds int; full_gardens int;
  lastr date; lastp date; start_d date; patience int; calm int; mt boolean; ev boolean; ft boolean; seas text[];
begin
  select * into c from public.children where id = p_child;
  if not found then return 0; end if;
  today := private.family_today(c.family_id);
  prem := private.is_premium(c.family_id);
  if c.stats_day is distinct from today or c.stats_cache is null then
    h := private.history_counters(p_child);
    update public.children set stats_cache = h, stats_day = today where id = p_child;
  else h := c.stats_cache; end if;
  select * into tg from private.garden_days(p_child, today, today);
  cur := coalesce((h ->> 'trail')::int, 0) + case when tg.good then 1 else 0 end;
  select * into s from public.child_stats where child_id = p_child;
  cur_s := private.season_of(today); cur_y := private.garden_year_of(today);
  -- fleurs closes (jardin)
  select count(*), count(*) filter (where grade = 3) into fl, big from public.flowers where child_id = p_child and grade is not null;
  with f as (select season, garden_year, grade from public.flowers where child_id = p_child and grade is not null),
  g as (select garden_year, season, count(*) as k, bool_and(grade = 3) as all3 from f where season <> cur_s or garden_year <> cur_y group by garden_year, season)
  select count(*), count(*) filter (where k >= 6 and all3) into beds, perfect_beds from g;
  select count(distinct garden_year) into gardens from public.flowers where child_id = p_child and grade is not null and garden_year <> cur_y;
  select count(*) into full_gardens from (
    select garden_year from public.flowers where child_id = p_child and grade is not null and garden_year <> cur_y
    group by garden_year having count(distinct season) filter (where season in ('printemps', 'ete', 'automne', 'hiver')) = 4) y;
  select coalesce(array_agg(distinct season), '{}') into seas from public.flowers where child_id = p_child and grade is not null and (season <> cur_s or garden_year <> cur_y);
  -- journée du jour : matin, soir et journée complète si tout est validé
  select coalesce(bool_or(dm > 0 and dm = vm), false), coalesce(bool_or(ds > 0 and ds = vs), false), coalesce(bool_or(da > 0 and da = va), false) into mt, ev, ft from (
    select count(*) filter (where rr.moment = 'matin' and not rr.is_bonus) as dm, count(*) filter (where rr.moment = 'matin' and not rr.is_bonus and cp.id is not null) as vm,
           count(*) filter (where rr.moment = 'soir' and not rr.is_bonus) as ds, count(*) filter (where rr.moment = 'soir' and not rr.is_bonus and cp.id is not null) as vs,
           count(*) as da, count(*) filter (where cp.id is not null) as va
    from private.routine_rules(p_child, today) rr
    left join public.completions cp on cp.routine_id = rr.routine_id and cp.day = today and cp.validated_at is not null) t;
  -- épargne et sérénité
  start_d := coalesce(c.garden_start, today);
  select max((created_at at time zone private.family_tz(c.family_id))::date) into lastr from public.redemptions where child_id = p_child;
  select max((created_at at time zone private.family_tz(c.family_id))::date) into lastp from public.penalty_events where child_id = p_child;
  patience := greatest(0, today - case when lastr is not null and lastr > start_d then lastr else start_d end);
  calm := greatest(0, today - case when lastp is not null and lastp > start_d then lastp else start_d end);
  m := jsonb_build_object(
    'done', s.done_count, 'earned', s.earned, 'best', greatest(coalesce((h ->> 'best')::int, 0), cur),
    'flowers', fl, 'big', big, 'beds', beds, 'gardens', gardens, 'perfect_beds', perfect_beds, 'full_gardens', full_gardens,
    'p_printemps', (seas @> array['printemps'])::int, 'p_ete', (seas @> array['ete'])::int, 'p_automne', (seas @> array['automne'])::int, 'p_hiver', (seas @> array['hiver'])::int,
    'timers', (select count(*) from public.completions where child_id = p_child and source = 'timer' and validated_at is not null),
    'bonus', private.bonus_count(p_child),
    'oneoff', (select count(*) from public.completions x join public.routines r on r.id = x.routine_id where x.child_id = p_child and r.kind = 'oneoff' and x.validated_at is not null),
    'matin', coalesce((h ->> 'matin')::int, 0) + mt::int, 'soir', coalesce((h ->> 'soir')::int, 0) + ev::int, 'full', coalesce((h ->> 'full')::int, 0) + ft::int,
    'weekends', coalesce((h ->> 'weekends')::int, 0), 'weeks', coalesce((h ->> 'weeks')::int, 0),
    'balance', greatest(0, s.earned - s.spent - s.broken),
    'outings', (select count(*) from public.redemptions z join public.rewards w on w.id = z.reward_id where z.child_id = p_child and w.tier = 'sortie'),
    'big_projects', (select count(*) from public.redemptions z join public.rewards w on w.id = z.reward_id where z.child_id = p_child and w.tier = 'grand'),
    'patience', patience, 'calm', calm);
  insert into public.child_badges (child_id, family_id, badge_key, shown_at)
  select p_child, c.family_id, k.key, case when prem or k.key ~ '^(first|r[0-9]+|s[0-9]+|st[0-9]+|f[0-9]+)$' then null else now() end
  from (values
('first','done',1),('r10','done',10),('r50','done',50),('r100','done',100),('r250','done',250),('r500','done',500),('r1000','done',1000),('r2500','done',2500),('r5000','done',5000),('r10000','done',10000),('r15000','done',15000),
('s25','earned',25),('s100','earned',100),('s250','earned',250),('s500','earned',500),('s1000','earned',1000),('s2500','earned',2500),('s5000','earned',5000),('s10000','earned',10000),('s15000','earned',15000),
('st3','best',3),('st7','best',7),('st14','best',14),('st30','best',30),('st60','best',60),('st100','best',100),('st200','best',200),('st365','best',365),('st500','best',500),
('f1','flowers',1),('f5','flowers',5),('f10','flowers',10),('f25','flowers',25),('f50','flowers',50),('f75','flowers',75),
('big','big',1),('big5','big',5),('big10','big',10),('big25','big',25),('big50','big',50),
('parterre','beds',1),('parterre5','beds',5),('parterre10','beds',10),('parterre15','beds',15),
('p_printemps','p_printemps',1),('p_ete','p_ete',1),('p_automne','p_automne',1),('p_hiver','p_hiver',1),
('jardin','gardens',1),('jardin2','gardens',2),('jardin5','gardens',5),('parfait','perfect_beds',1),('jcomplet','full_gardens',1),
('timer','timers',1),('timer10','timers',10),('timer50','timers',50),('bonus','bonus',1),('bonus10','bonus',10),('bonus50','bonus',50),
('oneoff1','oneoff',1),('oneoff10','oneoff',10),('oneoff25','oneoff',25),
('matin','matin',1),('matin10','matin',10),('matin50','matin',50),('soir','soir',1),('soir10','soir',10),('soir50','soir',50),
('full1','full',1),('full10','full',10),('we1','weekends',1),('we10','weekends',10),('week1','weeks',1),
('save50','balance',50),('save100','balance',100),('save250','balance',250),('save500','balance',500),('save1000','balance',1000),
('sortie1','outings',1),('sortie5','outings',5),('grand1','big_projects',1),('grand3','big_projects',3),
('patience30','patience',30),('patience90','patience',90),
('calme7','calm',7),('calme14','calm',14),('calme30','calm',30),('calme60','calm',60),('calme100','calm',100),('calme200','calm',200),('calme365','calm',365),('calme500','calm',500)
  ) as k(key, metric, target)
  where coalesce((m ->> k.metric)::int, 0) >= k.target
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- Clôture des périodes : appelle les badges (tâche horaire soisfier-close-periods, garden_payload, child_state)
create or replace function private.close_periods(p_child uuid) returns integer language plpgsql security definer set search_path = '' as $$
declare
  c record; today date; ps date; pe date; n int := 0; last_dow int;
  act int; gd int; g smallint; sea text; yr text; idx int; lst text[]; sp text;
begin
  select * into c from public.children where id = p_child;
  if c.garden_start is null then return 0; end if;
  perform private.auto_validate();
  today := private.family_today(c.family_id); last_dow := private.family_last_dow(c.family_id);
  select coalesce(max(period_end) + 1, c.garden_start) into ps from public.flowers where child_id = p_child and period_start >= c.garden_start;
  loop
    pe := private.period_end_of(ps, c.garden_start, last_dow);
    exit when pe >= today or n >= 60;
    select count(*) filter (where not paused and due > 0), count(*) filter (where good) into act, gd from private.garden_days(p_child, ps, pe);
    g := case when act = 0 then null when gd::numeric / act >= 0.9 then 3 when gd::numeric / act >= 0.65 then 2 when gd::numeric / act >= 0.35 then 1 else 0 end;
    sea := private.season_of(pe); yr := private.garden_year_of(pe);
    lst := case sea when 'printemps' then array['tulipe-rose','marguerite','tulipe-jaune','tulipe-violette'] when 'ete' then array['tournesol','cosmos-rose','marguerite','tournesol']
                    when 'automne' then array['cosmos-orange','tournesol','cosmos-rouge','marguerite'] else array['hellebore','tulipe-rouge','hellebore','marguerite'] end;
    select count(*) into idx from public.flowers where child_id = p_child and season = sea and garden_year = yr and grade is not null;
    sp := case when g is null then null else lst[(idx % array_length(lst, 1)) + 1] end;
    insert into public.flowers(family_id, child_id, period_start, period_end, species, grade, good_days, active_days, season, garden_year)
    values (c.family_id, p_child, ps, pe, sp, g, gd, act, sea, yr) on conflict (child_id, period_start) do nothing;
    ps := pe + 1; n := n + 1;
  end loop;
  perform private.award_badges(p_child);   -- EP-09 (ADR-44) : badges mérités, enregistrés par le serveur
  return n;
end $$;

-- Jardin : compteur des bonus selon les réglages valables chaque jour
create or replace function private.garden_payload(p_child uuid) returns json language plpgsql security definer set search_path = '' as $$
declare c record; today date; h jsonb; tg record; cur int; res json; ps date; pe date;
begin
  perform private.close_periods(p_child);
  select * into c from public.children where id = p_child;
  today := private.family_today(c.family_id);
  if c.stats_day is distinct from today or c.stats_cache is null then
    h := private.history_counters(p_child);
    update public.children set stats_cache = h, stats_day = today where id = p_child;
  else h := c.stats_cache; end if;
  select * into tg from private.garden_days(p_child, today, today);
  cur := (h ->> 'trail')::int + case when tg.good then 1 else 0 end;
  select coalesce(max(period_end) + 1, c.garden_start) into ps from public.flowers where child_id = p_child and period_start >= c.garden_start;
  pe := private.period_end_of(ps, c.garden_start, private.family_last_dow(c.family_id));
  select json_build_object(
    'today', today, 'period_start', ps, 'period_end', pe, 'period_len', pe - ps + 1,
    'season', private.season_of(today), 'garden_year', private.garden_year_of(today),
    'days', coalesce((select json_agg(x order by x.day) from private.garden_days(p_child, ps, least(today, pe)) x), '[]'::json),
    'flowers', coalesce((select json_agg(f order by f.period_start) from (select id, period_start, period_end, species, grade, good_days, active_days, season, garden_year from public.flowers where child_id = p_child and grade is not null) f), '[]'::json),
    'pauses', coalesce((select json_agg(p order by p.start_day) from (select id, start_day, end_day, reason from public.pauses where child_id = p_child and end_day >= today) p), '[]'::json),
    'streak', cur, 'best_streak', greatest((h ->> 'best')::int, cur),
    'counters', json_build_object(
      'timers', (select count(*) from public.completions where child_id = p_child and source = 'timer' and validated_at is not null),
      'bonus', private.bonus_count(p_child),
      'oneoff', (select count(*) from public.completions x join public.routines r on r.id = x.routine_id where x.child_id = p_child and r.kind = 'oneoff' and x.validated_at is not null),
      'sortie', (select count(*) from public.redemptions z join public.rewards w on w.id = z.reward_id where z.child_id = p_child and w.tier = 'sortie'),
      'grand', (select count(*) from public.redemptions z join public.rewards w on w.id = z.reward_id where z.child_id = p_child and w.tier = 'grand'),
      'last_redeem', (select max(created_at) from public.redemptions where child_id = p_child),
      'matin', (h ->> 'matin')::int, 'soir', (h ->> 'soir')::int, 'full', (h ->> 'full')::int, 'weeks', (h ->> 'weeks')::int, 'weekends', (h ->> 'weekends')::int)
  ) into res;
  return res;
end $$;

-- L'enfant a vu l'annonce : les badges ne sont plus « à annoncer »
create or replace function public.child_badges_seen(p_token text, p_keys text[]) returns void
language plpgsql security definer set search_path = '' as $$
declare d record;
begin
  select * into d from private.device_child(p_token);
  update public.child_badges set shown_at = now() where child_id = d.child_id and badge_key = any(p_keys) and shown_at is null;
end $$;
revoke execute on function public.child_badges_seen(text, text[]) from public;
grant execute on function public.child_badges_seen(text, text[]) to anon, authenticated;
revoke execute on function private.award_badges(uuid), private.bonus_count(uuid) from public, anon, authenticated;

-- État de l'enfant : réglages historisés, badges à annoncer ; fleurs closes et badges mis à jour avant la lecture
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
  perform private.close_periods(d.child_id);   -- fleurs closes et badges mérités avant de lire l'état (EP-09, ADR-44)
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
    'badges_new', coalesce((select json_agg(b.badge_key) from public.child_badges b where b.child_id = d.child_id and b.shown_at is null), '[]'::json),
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
  u_par uuid := gen_random_uuid(); u_help uuid := gen_random_uuid();
  fid uuid; fidF uuid; c1 uuid; c3 uuid; cF uuid; rA uuid; rB uuid; rM uuid; rF uuid; rBonus uuid; tok text; tokF text;
  td date; res text := ''; v text; n int; h1 jsonb; h2 jsonb; keys text; j json; w int;
begin
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
  grant execute on function pg_temp.try(text), pg_temp.as_user(uuid), pg_temp.sup(text), pg_temp.supdo(text) to public;
  perform set_config('sf.via_report', 'on', true);

  insert into auth.users(id, email) values (u_par, 'parent.test@example.invalid'), (u_help, 'proche.test@example.invalid');
  insert into public.families(name, plan, timezone) values ('Famille test EP-09C', 'premium', 'Europe/Paris') returning id into fid;
  insert into public.families(name, plan, timezone) values ('Famille gratuite test EP-09C', 'premium', 'Europe/Paris') returning id into fidF;
  insert into public.family_members(family_id, user_id, role) values (fid, u_par, 'parent'), (fidF, u_par, 'parent');
  td := private.family_today(fid);
  insert into public.children(family_id, name, garden_start) values (fid, 'Enfant 1', td - 30) returning id into c1;
  insert into public.children(family_id, name, garden_start) values (fidF, 'Enfant gratuit', td - 30) returning id into cF;
  insert into public.children(family_id, name, garden_start) values (fid, 'Enfant 3', td - 30) returning id into c3;
  update public.families set plan = 'free' where id = fidF;

  -- ===================== C1. Réglages historisés : déclencheurs =====================
  insert into public.routines(family_id, child_id, title, moment, stars, days, created_at) values (fid, c1, 'Routine A', 'matin', 4, '{1,2,3,4,5,6,7}', now() - interval '30 days') returning id into rA;
  res := res || ' T1.creation=' || (select count(*)::text || '/' || (min(valid_from) = td - 30)::text from public.routine_settings where routine_id = rA);
  perform pg_temp.supdo(format('update public.routines set title = ''Titre modifie'' where id = %L', rA));
  res := res || ' T2.titre_seul=' || (select count(*) from public.routine_settings where routine_id = rA);
  perform pg_temp.supdo(format('update public.routines set stars = 6 where id = %L', rA));
  res := res || ' T2b.etoiles=' || (select count(*)::text || '/' || (max(valid_from) = td)::text || '/' || (select stars from public.routine_settings where routine_id = rA and valid_from = td)::text from public.routine_settings where routine_id = rA);
  perform pg_temp.supdo(format('update public.routines set stars = 7, days = ''{1,2,3}'' where id = %L', rA));
  res := res || ' T2c.meme_jour=' || (select count(*) from public.routine_settings where routine_id = rA)::text || '/' || (select stars::text || ':' || array_to_string(days, ',') from public.routine_settings where routine_id = rA and valid_from = td);
  perform pg_temp.supdo(format('update public.routines set days = ''{1,2,3}'' where id = %L', rA));
  res := res || ' T2d.inchange=' || (select count(*) from public.routine_settings where routine_id = rA);
  perform pg_temp.as_user(u_par);
  res := res || ' T3.ecriture_directe=' || pg_temp.try(format('insert into public.routine_settings(routine_id, family_id, valid_from, days, is_bonus, stars) values (%L, %L, %L, ''{1}'', false, 1)', rA, fid, td + 1));
  res := res || ' T3b.lecture_membre=' || (select count(*) from public.routine_settings where routine_id = rA);
  perform pg_temp.as_user(null);
  res := res || ' T3c.anon=' || pg_temp.try('select count(*) from public.routine_settings');
  perform pg_temp.as_user(null); perform set_config('role', 'postgres', true);

  -- DT10-11 : modifier une routine aujourd'hui ne change pas les compteurs du passé
  insert into public.routines(family_id, child_id, title, moment, stars, days, created_at) values (fid, c3, 'Routine B', 'matin', 2, '{1,2,3,4,5,6,7}', now() - interval '30 days') returning id into rB;
  insert into public.completions(family_id, child_id, routine_id, day, source) select fid, c3, rB, td - g, 'parent' from generate_series(1, 12) g;
  h1 := private.history_counters(c3);
  perform pg_temp.supdo(format('update public.routines set days = ''{1}'', stars = 9, is_bonus = true where id = %L', rB));
  h2 := private.history_counters(c3);
  res := res || ' T4.passe_fige=' || (h1 = h2)::text || '/best=' || coalesce(h1 ->> 'best', 'null');

  -- ===================== C2. Badges par le serveur =====================
  insert into public.routines(family_id, child_id, title, moment, stars, days, created_at) values (fid, c1, 'Routine matin', 'matin', 30, '{1,2,3,4,5,6,7}', now() - interval '1 day') returning id into rM;
  insert into public.completions(family_id, child_id, routine_id, day, source) values (fid, c1, rM, td, 'parent');
  perform pg_temp.supdo(format('select private.close_periods(%L)', c1));
  select string_agg(badge_key, ',' order by badge_key) into keys from public.child_badges where child_id = c1;
  res := res || ' B1.badges=' || coalesce(keys, 'aucun');
  res := res || ' B1b.annonce=' || (select count(*) from public.child_badges where child_id = c1 and shown_at is null)::text;
  res := res || ' B2.idempotent=' || private.award_badges(c1)::text;
  -- Premium et gratuit : badge Premium d'une famille gratuite enregistré sans annonce
  insert into public.routines(family_id, child_id, title, moment, stars, days, created_at) values (fidF, cF, 'Routine gratuite', 'matin', 1, '{1,2,3,4,5,6,7}', now() - interval '1 day') returning id into rF;
  insert into public.completions(family_id, child_id, routine_id, day, source) values (fidF, cF, rF, td, 'parent');
  update public.completions set source = 'timer' where routine_id = rF;
  perform private.award_badges(cF);
  res := res || ' B3.gratuit=' || (select coalesce(string_agg(badge_key || ':' || (shown_at is not null)::text, ',' order by badge_key), 'aucun') from public.child_badges where child_id = cF);
  perform private.award_badges(c1);
  update public.completions set source = 'timer' where routine_id = rM;
  perform private.award_badges(c1);
  res := res || ' B3b.premium=' || (select coalesce(shown_at is null, false)::text from public.child_badges where child_id = c1 and badge_key = 'timer');
  -- Jardin : fleurs closes
  insert into public.flowers(family_id, child_id, period_start, period_end, species, grade, good_days, active_days, season, garden_year)
    select fid, c1, date '2020-01-01' + g * 14, date '2020-01-14' + g * 14, 'x', 3, 5, 5, 'printemps', '2019-2020' from generate_series(0, 5) g;
  insert into public.flowers(family_id, child_id, period_start, period_end, species, grade, good_days, active_days, season, garden_year)
    values (fid, c1, '2020-06-01', '2020-06-14', 'x', 2, 4, 5, 'ete', '2019-2020'), (fid, c1, '2020-10-01', '2020-10-14', 'x', 1, 3, 5, 'automne', '2020-2021'),
           (fid, c1, '2020-11-01', '2020-11-14', 'x', 2, 4, 5, 'hiver', '2019-2020'), (fid, c1, '2020-12-25', '2021-01-07', 'x', 2, 4, 5, 'hiver', '2020-2021'),
           (fid, c1, '2020-02-01', '2020-02-14', 'x', 2, 4, 5, 'automne', '2019-2020');
  perform private.award_badges(c1);
  select string_agg(badge_key, ',' order by badge_key) into keys from public.child_badges where child_id = c1 and badge_key ~ '^(f|big|parterre|parfait|jardin|jcomplet|p_)';
  res := res || ' B4.jardin=' || coalesce(keys, 'aucun');
  -- Bonus selon le statut valable le jour de la coche
  insert into public.routines(family_id, child_id, title, moment, stars, days, is_bonus, created_at) values (fid, c1, 'Routine bonus', 'soir', 1, '{1,2,3,4,5,6,7}', false, now() - interval '30 days') returning id into rBonus;
  delete from public.routine_settings where routine_id = rBonus;
  insert into public.routine_settings(routine_id, family_id, valid_from, days, is_bonus, stars) values (rBonus, fid, td - 30, '{1,2,3,4,5,6,7}', true, 1), (rBonus, fid, td - 4, '{1,2,3,4,5,6,7}', false, 1);
  insert into public.completions(family_id, child_id, routine_id, day, source) values (fid, c1, rBonus, td - 7, 'parent'), (fid, c1, rBonus, td - 2, 'parent');
  res := res || ' B5.bonus_selon_le_jour=' || private.bonus_count(c1)::text;
  -- État de l'enfant : badges à annoncer, réglages ; vu par l'enfant
  perform pg_temp.as_user(u_par);
  tok := (public.child_pair_here(c1, 'Telephone test') ->> 'token');
  perform pg_temp.as_user(null);
  j := public.child_state(tok);
  res := res || ' B6.etat=nouveaux:' || json_array_length(j -> 'badges_new')::text || '/reglages:' || (select json_array_length(r -> 'settings')::text from json_array_elements(j -> 'routines') r where r ->> 'title' = 'Titre modifie' limit 1);
  perform public.child_badges_seen(tok, array(select json_array_elements_text(j -> 'badges_new')));
  j := public.child_state(tok);
  res := res || ' B6b.apres_vu=' || json_array_length(j -> 'badges_new')::text;
  perform pg_temp.as_user(null);
  res := res || ' B7.anon_attribution=' || pg_temp.try(format('select private.award_badges(%L)', c1));
  perform pg_temp.as_user(u_par);
  res := res || ' B7b.auth_attribution=' || pg_temp.try(format('select private.award_badges(%L)', c1));
  res := res || ' B7c.insertion_directe_avant=' || pg_temp.try(format('insert into public.child_badges(child_id, family_id, badge_key) values (%L, %L, ''save1000'')', c1, fid));
  perform pg_temp.as_user(null); perform set_config('role', 'postgres', true);
  perform set_config('t.res', res, true);
end $t$;

-- EP-09 thème C (3/3) : retraits des badges écrits par l'application (ADR-44, DT09-02). CONTIENT drop : ÉDITEUR SQL de Supabase (ADR-07),
-- après ep09c_badges_serveur, et SEULEMENT quand la nouvelle version de l'application est en ligne (l'ancienne appelle child_award_badges
-- et enregistre ses badges dans child_badges).
-- À tester dans une transaction annulée (supabase/tests/ep09c_badges_test.sql, cas finaux).
--
-- DT09-02  plus aucun membre n'enregistre un badge à la main : le serveur seul décide du mérite

drop function if exists public.child_award_badges(text, text[]);
drop policy if exists badges_insert on public.child_badges;

do $t$
declare u_par uuid; fid uuid; c1 uuid; res text := current_setting('t.res', true);
begin
  select id into u_par from auth.users where email = 'parent.test@example.invalid';
  select id into fid from public.families where name = 'Famille test EP-09C';
  select id into c1 from public.children where family_id = fid and name = 'Enfant 1';
  res := res || ' B8.fonction_retiree=' || (to_regprocedure('public.child_award_badges(text,text[])') is null);
  perform pg_temp.as_user(u_par);
  res := res || ' B8b.insertion_directe_apres=' || pg_temp.try(format('insert into public.child_badges(child_id, family_id, badge_key) values (%L, %L, ''save1000'')', c1, fid));
  res := res || ' B8c.lecture=' || (select count(*) > 0 from public.child_badges where child_id = c1);
  perform pg_temp.as_user(null); perform set_config('role', 'postgres', true);
  raise exception 'RESULT:%', res;
end $t$;
rollback;
