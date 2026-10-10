-- SoisFier : réglage de la semaine et fuseau horaire par famille (étape 1 du multilingue)
-- Familles existantes : lundi, week-end samedi-dimanche, Europe/Paris → comportement inchangé.

-- 1. Réglages de la famille --------------------------------------------------
create or replace function private.valid_tz(tz text) returns boolean
 language plpgsql stable set search_path to ''
as $$ begin perform now() at time zone tz; return true; exception when others then return false; end $$;

alter table public.families
  add column if not exists week_start smallint not null default 1,
  add column if not exists weekend_days smallint[] not null default '{6,7}',
  add column if not exists timezone text not null default 'Europe/Paris';

alter table public.families
  add constraint families_week_start_chk check (week_start between 1 and 7),
  add constraint families_weekend_chk check (weekend_days <@ array[1,2,3,4,5,6,7]::smallint[] and cardinality(weekend_days) <= 3),
  add constraint families_timezone_chk check (private.valid_tz(timezone));

comment on column public.families.week_start is 'Premier jour de la semaine (1 = lundi … 7 = dimanche)';
comment on column public.families.weekend_days is 'Jours de week-end (1 = lundi … 7 = dimanche)';
comment on column public.families.timezone is 'Fuseau horaire IANA de la famille (Europe/Paris, Asia/Dubai…)';

-- 2. Outils de date -------------------------------------------------------------
create or replace function private.family_today(p_family uuid) returns date
 language sql stable security definer set search_path to ''
as $$ select (now() at time zone coalesce((select timezone from public.families where id = p_family), 'Europe/Paris'))::date $$;

create or replace function private.child_today(p_child uuid) returns date
 language sql stable security definer set search_path to ''
as $$ select private.family_today((select family_id from public.children where id = p_child)) $$;

create or replace function private.family_tz(p_family uuid) returns text
 language sql stable security definer set search_path to ''
as $$ select coalesce((select timezone from public.families where id = p_family), 'Europe/Paris') $$;

-- Dernier jour de la semaine de la famille (veille du premier jour)
create or replace function private.family_last_dow(p_family uuid) returns int
 language sql stable security definer set search_path to ''
as $$ select ((coalesce((select week_start from public.families where id = p_family), 1) + 5) % 7) + 1 $$;

-- Fin d'une quinzaine commençant le jour ps :
-- première période (ps = début du jardin) : 8 à 14 jours ; ensuite : 14 jours si alignée, jusqu'à 20 sinon.
create or replace function private.period_end_of(ps date, gs date, last_dow int) returns date
 language sql immutable set search_path to ''
as $$
  select b + ((last_dow - extract(isodow from b)::int + 7) % 7)
  from (select ps + case when ps <= gs then 7 else 13 end as b) x
$$;

-- Début du jardin d'un nouvel enfant : « aujourd'hui » dans le fuseau de la famille
alter table public.children alter column garden_start drop default;
create or replace function private.set_garden_start() returns trigger
 language plpgsql security definer set search_path to ''
as $$ begin
  if new.garden_start is null then new.garden_start := private.family_today(new.family_id); end if;
  return new;
end $$;
drop trigger if exists children_garden_start on public.children;
create trigger children_garden_start before insert on public.children for each row execute function private.set_garden_start();

-- Changer la semaine ou le fuseau recalcule les compteurs de badges
create or replace function private.family_settings_changed() returns trigger
 language plpgsql security definer set search_path to ''
as $$ begin
  if new.week_start is distinct from old.week_start or new.weekend_days is distinct from old.weekend_days
     or new.timezone is distinct from old.timezone then
    update public.children set stats_day = null where family_id = new.id;
  end if;
  return null;
end $$;
drop trigger if exists families_settings_changed on public.families;
create trigger families_settings_changed after update on public.families for each row execute function private.family_settings_changed();

-- 3. Fonctions passées au fuseau de la famille -------------------------------------
create or replace function private.auto_validate() returns integer
 language plpgsql security definer set search_path to ''
as $function$
declare n int;
begin
  update public.completions c set validated_at = now()
  from public.families f
  where f.id = c.family_id and f.auto_validate and c.validated_at is null
    and c.day < (now() at time zone f.timezone)::date;
  get diagnostics n = row_count;
  return n;
end $function$;

create or replace function private.invalidate_stats() returns trigger
 language plpgsql security definer set search_path to ''
as $function$
declare r record;
begin
  if tg_op = 'DELETE' then r := old; else r := new; end if;
  if tg_table_name = 'pauses' then
    update public.children set stats_day = null where id = r.child_id;
  elsif r.day < private.child_today(r.child_id) then
    update public.children set stats_day = null where id = r.child_id;
  end if;
  return null;
end $function$;

create or replace function private.garden_days(p_child uuid, p_from date, p_to date)
 returns table(day date, due integer, earned integer, paused boolean, good boolean)
 language sql stable security definer set search_path to ''
as $function$
  with tz as (select private.family_tz(c.family_id) as z from public.children c where c.id = p_child),
  d as (
    select g::date as day,
      (coalesce((select sum(r.stars) from public.routines r
        where r.child_id = p_child and r.kind = 'regular' and not r.is_bonus
          and (r.created_at at time zone (select z from tz))::date <= g::date
          and (r.ended_at is null or (r.ended_at at time zone (select z from tz))::date > g::date)
          and r.days @> array[extract(isodow from g)::smallint]), 0)
      + coalesce((select sum(r.stars) from public.routines r
        where r.child_id = p_child and r.kind = 'oneoff' and not r.is_bonus and r.active
          and g::date between r.start_day and r.end_day
          and (exists (select 1 from public.completions c where c.routine_id = r.id and c.day = g::date)
               or (g::date = r.end_day and not exists (select 1 from public.completions c where c.routine_id = r.id)))), 0))::int as due,
      coalesce((select sum(c.stars) from public.completions c
        where c.child_id = p_child and c.day = g::date and c.validated_at is not null), 0)::int as earned,
      exists (select 1 from public.pauses p where p.child_id = p_child and g::date between p.start_day and p.end_day) as paused
    from generate_series(p_from, p_to, interval '1 day') g
  )
  select day, due, earned, paused, (not paused and due > 0 and earned >= ceil(due * 0.75)) as good from d;
$function$;

-- 4. Badges « Semaine parfaite » et « Week-end parfait » selon la famille ------------------
create or replace function private.history_counters(p_child uuid) returns jsonb
 language plpgsql security definer set search_path to ''
as $function$
declare
  c record; fam record; today date; r record; tz text;
  run int := 0; best int := 0; wk_ok boolean := true; wk_act int := 0; weeks int := 0;
  last_dow int; dw int; we_ok boolean := false; we_len int := 0; exp_len int; weekends int := 0; m int; s int; f int;
begin
  select * into c from public.children where id = p_child;
  select week_start, weekend_days into fam from public.families where id = c.family_id;
  today := private.family_today(c.family_id); tz := private.family_tz(c.family_id);
  last_dow := ((fam.week_start + 5) % 7) + 1;
  for r in select * from private.garden_days(p_child, c.garden_start, today - 1) order by day loop
    dw := extract(isodow from r.day)::int;
    -- séries de bonnes journées (jours neutres ignorés)
    if not (r.paused or r.due = 0) then
      if r.good then run := run + 1; best := greatest(best, run); else run := 0; end if;
    end if;
    -- semaines parfaites (premier → dernier jour de la semaine de la famille, au moins 5 jours actifs, tous bons)
    if dw = fam.week_start then wk_ok := true; wk_act := 0; end if;
    if not (r.paused or r.due = 0) then wk_act := wk_act + 1; if not r.good then wk_ok := false; end if; end if;
    if dw = last_dow and wk_ok and wk_act >= 5 and r.day - 6 >= c.garden_start then weeks := weeks + 1; end if;
    -- week-ends parfaits (tous les jours d'un bloc de week-end consécutif sont de bonnes journées)
    if dw = any(fam.weekend_days) then
      if we_len = 0 then we_ok := r.good; we_len := 1; else we_ok := we_ok and r.good; we_len := we_len + 1; end if;
      if not ((dw % 7) + 1 = any(fam.weekend_days)) then            -- dernier jour du bloc
        exp_len := 1;
        while exp_len < 7 and (((dw - 1 - exp_len + 7) % 7) + 1) = any(fam.weekend_days) loop exp_len := exp_len + 1; end loop;
        if we_ok and we_len = exp_len then weekends := weekends + 1; end if;
        we_len := 0;
      end if;
    else
      we_len := 0;
    end if;
  end loop;

  with days as (select g::date as d from generate_series(c.garden_start, today - 1, interval '1 day') g),
  x as (
    select dd.d,
      count(rt.id) filter (where rt.moment = 'matin' and not rt.is_bonus) as dm,
      count(rt.id) filter (where rt.moment = 'matin' and not rt.is_bonus and cp.id is not null) as vm,
      count(rt.id) filter (where rt.moment = 'soir' and not rt.is_bonus) as ds,
      count(rt.id) filter (where rt.moment = 'soir' and not rt.is_bonus and cp.id is not null) as vs,
      count(rt.id) as da, count(rt.id) filter (where cp.id is not null) as va
    from days dd
    join public.routines rt on rt.child_id = p_child and rt.kind = 'regular'
      and rt.days @> array[extract(isodow from dd.d)::smallint]
      and (rt.created_at at time zone tz)::date <= dd.d
      and (rt.ended_at is null or (rt.ended_at at time zone tz)::date > dd.d)
    left join public.completions cp on cp.routine_id = rt.id and cp.day = dd.d and cp.validated_at is not null
    group by dd.d)
  select count(*) filter (where dm > 0 and dm = vm), count(*) filter (where ds > 0 and ds = vs), count(*) filter (where da > 0 and da = va)
    into m, s, f from x;

  return jsonb_build_object('best', best, 'trail', run, 'weeks', weeks, 'weekends', weekends, 'matin', m, 'soir', s, 'full', f);
end $function$;

-- 5. Quinzaines alignées sur la semaine de la famille ----------------------------------
create or replace function private.close_periods(p_child uuid) returns integer
 language plpgsql security definer set search_path to ''
as $function$
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
    select count(*) filter (where not paused and due > 0), count(*) filter (where good)
      into act, gd from private.garden_days(p_child, ps, pe);
    g := case when act = 0 then null
              when gd::numeric / act >= 0.9 then 3
              when gd::numeric / act >= 0.65 then 2
              when gd::numeric / act >= 0.35 then 1 else 0 end;
    sea := private.season_of(pe); yr := private.garden_year_of(pe);
    lst := case sea when 'printemps' then array['tulipe-rose','marguerite','tulipe-jaune','tulipe-violette']
                    when 'ete' then array['tournesol','cosmos-rose','marguerite','tournesol']
                    when 'automne' then array['cosmos-orange','tournesol','cosmos-rouge','marguerite']
                    else array['hellebore','tulipe-rouge','hellebore','marguerite'] end;
    select count(*) into idx from public.flowers where child_id = p_child and season = sea and garden_year = yr and grade is not null;
    sp := case when g is null then null else lst[(idx % array_length(lst, 1)) + 1] end;
    insert into public.flowers(family_id, child_id, period_start, period_end, species, grade, good_days, active_days, season, garden_year)
    values (c.family_id, p_child, ps, pe, sp, g, gd, act, sea, yr) on conflict (child_id, period_start) do nothing;
    ps := pe + 1; n := n + 1;
  end loop;
  return n;
end $function$;

create or replace function private.garden_payload(p_child uuid) returns json
 language plpgsql security definer set search_path to ''
as $function$
declare
  c record; today date; h jsonb; tg record; cur int; res json; ps date; pe date;
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
    'today', today,
    'period_start', ps, 'period_end', pe, 'period_len', pe - ps + 1,
    'season', private.season_of(today), 'garden_year', private.garden_year_of(today),
    'days', coalesce((select json_agg(x order by x.day) from private.garden_days(p_child, ps, least(today, pe)) x), '[]'::json),
    'flowers', coalesce((select json_agg(f order by f.period_start) from
        (select id, period_start, period_end, species, grade, good_days, active_days, season, garden_year
         from public.flowers where child_id = p_child and grade is not null) f), '[]'::json),
    'pauses', coalesce((select json_agg(p order by p.start_day) from
        (select id, start_day, end_day, reason from public.pauses where child_id = p_child and end_day >= today) p), '[]'::json),
    'streak', cur, 'best_streak', greatest((h ->> 'best')::int, cur),
    'counters', json_build_object(
      'timers', (select count(*) from public.completions where child_id = p_child and source = 'timer' and validated_at is not null),
      'bonus', (select count(*) from public.completions x join public.routines r on r.id = x.routine_id where x.child_id = p_child and r.is_bonus and x.validated_at is not null),
      'oneoff', (select count(*) from public.completions x join public.routines r on r.id = x.routine_id where x.child_id = p_child and r.kind = 'oneoff' and x.validated_at is not null),
      'sortie', (select count(*) from public.redemptions z join public.rewards w on w.id = z.reward_id where z.child_id = p_child and w.tier = 'sortie'),
      'grand', (select count(*) from public.redemptions z join public.rewards w on w.id = z.reward_id where z.child_id = p_child and w.tier = 'grand'),
      'last_redeem', (select max(created_at) from public.redemptions where child_id = p_child),
      'matin', (h ->> 'matin')::int, 'soir', (h ->> 'soir')::int, 'full', (h ->> 'full')::int,
      'weeks', (h ->> 'weeks')::int, 'weekends', (h ->> 'weekends')::int)
  ) into res;
  return res;
end $function$;

-- 6. Appareil enfant : « aujourd'hui » de la famille --------------------------------------
create or replace function public.child_state(p_token text) returns json
 language plpgsql security definer set search_path to ''
as $function$
declare d record; today date; res json;
begin
  select * into d from private.device_child(p_token);
  today := private.family_today(d.family_id);
  select json_build_object(
    'today', today,
    'child', (select row_to_json(c) from (select id, name, emoji, color, garden_start from public.children where id = d.child_id) c),
    'routines', coalesce((select json_agg(r order by r.position, r.created_at) from
        (select id, title, emoji, place, moment, stars, days, is_bonus, timer_minutes, position, created_at, kind, start_day, end_day
         from public.routines where child_id = d.child_id and active and (kind = 'regular' or end_day >= today - 2)) r), '[]'::json),
    'completions', coalesce((select json_agg(x) from
        (select routine_id, day, stars, source, validated_at is not null as validated,
           case when validated_at is null then null when validated_by is null then 'auto' else private.member_label(d.family_id, validated_by) end as validated_label
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

create or replace function public.child_toggle(p_token text, p_routine uuid, p_day date, p_done boolean, p_source text default 'child')
 returns json language plpgsql security definer set search_path to ''
as $function$
declare d record; today date; r record;
begin
  select * into d from private.device_child(p_token);
  today := private.family_today(d.family_id);
  select * into r from public.routines where id = p_routine and child_id = d.child_id and active;
  if not found then raise exception 'Routine introuvable'; end if;
  if p_day < today - 2 or p_day > today then raise exception 'Jour non modifiable'; end if;
  if r.kind = 'oneoff' and (p_day < r.start_day or p_day > r.end_day) then raise exception 'Routine exceptionnelle hors de ses dates'; end if;
  if p_done then
    insert into public.completions(family_id, child_id, routine_id, day, source)
    values (d.family_id, d.child_id, p_routine, p_day, case when p_source in ('child','timer') then p_source else 'child' end)
    on conflict (routine_id, day) do nothing;
  else
    if exists (select 1 from public.completions where routine_id = p_routine and day = p_day and validated_at is not null) then
      raise exception 'Déjà validée par un parent';
    end if;
    delete from public.completions where routine_id = p_routine and day = p_day and child_id = d.child_id and validated_at is null;
  end if;
  return json_build_object('ok', true);
end $function$;

-- 7. Rappels à l'heure locale de chaque famille (textes inchangés, traduits à l'étape 2) -------
create or replace function public.reminders_due(p_secret text) returns json
 language plpgsql security definer set search_path to ''
as $function$
declare items json;
begin
  if p_secret is null or p_secret is distinct from (select value from private.config where key = 'cron_secret') then
    raise exception 'Accès refusé';
  end if;
  with fam as (
    select f.id, (now() at time zone f.timezone) as now_l from public.families f
  ),
  due as (
    select s.* from public.push_subscriptions s join fam on fam.id = s.family_id
    where exists (select 1 from unnest(s.reminder_times) t
                  where t ~ '^\d{2}:\d{2}$' and fam.now_l::time >= t::time and fam.now_l::time < t::time + interval '15 minutes')
  ),
  todo as (
    select c.id as child_id, c.family_id, c.name,
      count(r.id) filter (where r.days @> array[extract(isodow from fam.now_l)::smallint] and not r.is_bonus) as total,
      count(r.id) filter (where r.days @> array[extract(isodow from fam.now_l)::smallint] and not r.is_bonus
        and exists (select 1 from public.completions x where x.routine_id = r.id and x.day = fam.now_l::date)) as done,
      (select count(*) from public.completions x where x.child_id = c.id and x.validated_at is null) as pending
    from public.children c
    join fam on fam.id = c.family_id
    left join public.routines r on r.child_id = c.id and r.active
    group by c.id, fam.now_l
  )
  select coalesce(json_agg(json_build_object(
    'endpoint', d.endpoint, 'p256dh', d.p256dh, 'auth', d.auth,
    'title', case when d.child_device_id is not null then 'C''est l''heure de tes routines 🌱' else 'Routines du jour 🌱' end,
    'body', case when d.child_device_id is not null then
        (select case when t.total - t.done > 0 then 'Encore ' || (t.total - t.done) || ' à faire. Ta plante t''attend !' end
         from todo t join public.child_devices cd on cd.child_id = t.child_id where cd.id = d.child_device_id)
      else
        (select string_agg(t.name || ' : ' || t.done || '/' || t.total
                 || case when t.pending > 0 then ' (' || t.pending || ' à valider)' else '' end, ', ' order by t.name)
         from todo t where t.family_id = d.family_id and (t.total > 0 or t.pending > 0))
      end
  )), '[]'::json) into items from due d;
  return json_build_object(
    'vapid_public', (select value from private.config where key = 'vapid_public'),
    'vapid_private', (select value from private.config where key = 'vapid_private'),
    'subject', (select value from private.config where key = 'vapid_subject'),
    'items', items);
end $function$;

-- 8. Création de famille avec réglages détectés sur le téléphone ------------------------------
drop function if exists public.create_family(text, text);
create function public.create_family(p_name text, p_display_name text,
  p_week_start smallint default 1, p_weekend smallint[] default '{6,7}', p_timezone text default 'Europe/Paris')
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare fid uuid; uid uuid := auth.uid(); ws smallint; we smallint[]; tz text;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select family_id into fid from public.family_members where user_id = uid order by created_at limit 1;
  if fid is not null then return fid; end if;
  ws := case when p_week_start between 1 and 7 then p_week_start else 1 end;
  we := case when p_weekend is not null and p_weekend <@ array[1,2,3,4,5,6,7]::smallint[] and cardinality(p_weekend) <= 3
             then coalesce((select array_agg(distinct x order by x) from unnest(p_weekend) x), '{}') else '{6,7}' end;
  tz := case when private.valid_tz(p_timezone) then p_timezone else 'Europe/Paris' end;
  insert into public.families(name, week_start, weekend_days, timezone)
  values (coalesce(nullif(trim(p_name), ''), 'Ma famille'), ws, we, tz) returning id into fid;
  insert into public.family_members(family_id, user_id, role, display_name) values (fid, uid, 'parent', nullif(trim(p_display_name), ''));
  return fid;
end $function$;
revoke execute on function public.create_family(text, text, smallint, smallint[], text) from public, anon;
grant execute on function public.create_family(text, text, smallint, smallint[], text) to authenticated;

-- 9. Anciennes fonctions remplacées ---------------------------------------------------------------
-- private.paris_today, private.first_end et private.period_bounds ne sont plus appelées ; conservées pour l'historique.
