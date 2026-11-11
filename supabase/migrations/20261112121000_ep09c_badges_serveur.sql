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
