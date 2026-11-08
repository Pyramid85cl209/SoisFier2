-- v22 : Mode vacances (Premium).
-- Une période par enfant ; pendant la période, chaque routine habituelle suit son réglage
-- (en pause, obligatoire, bonus, jours, étoiles ; vide = comme d'habitude) et des routines de vacances s'ajoutent.
-- Les réglages sont lus par une seule fonction, private.routine_rules, utilisée par le jardin,
-- les compteurs, les rappels et les étoiles des routines cochées.

-- 1. Tables
create table public.holiday_periods (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  child_id uuid not null,
  name text not null check (char_length(name) between 1 and 40),
  start_day date not null,
  end_day date not null,
  active boolean not null default true,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (end_day >= start_day),
  unique (id, child_id),
  foreign key (child_id, family_id) references public.children(id, family_id) on delete cascade
);
create index holiday_periods_child_idx on public.holiday_periods (child_id, start_day);
create index holiday_periods_family_idx on public.holiday_periods (family_id);

create table public.holiday_overrides (
  period_id uuid not null,
  routine_id uuid not null,
  child_id uuid not null,
  family_id uuid not null,
  status text check (status in ('off', 'required', 'bonus')),
  days smallint[] check (days is null or (cardinality(days) between 1 and 7 and days <@ array[1,2,3,4,5,6,7]::smallint[])),
  stars int check (stars is null or stars between 1 and 10),
  primary key (period_id, routine_id),
  foreign key (period_id, child_id) references public.holiday_periods(id, child_id) on delete cascade,
  foreign key (routine_id, child_id) references public.routines(id, child_id) on delete cascade
);
create index holiday_overrides_routine_idx on public.holiday_overrides (routine_id, child_id);
create index holiday_overrides_family_idx on public.holiday_overrides (family_id);

-- Routine de vacances : rattachée à sa période (et au même enfant)
alter table public.routines add column holiday_period_id uuid;
alter table public.routines add constraint routines_holiday_period_fkey
  foreign key (holiday_period_id, child_id) references public.holiday_periods(id, child_id) on delete cascade;
create index routines_holiday_period_idx on public.routines (holiday_period_id, child_id) where holiday_period_id is not null;

-- 2. Droits : tout membre lit, un parent modifie
alter table public.holiday_periods enable row level security;
alter table public.holiday_overrides enable row level security;
create policy holiday_periods_select on public.holiday_periods for select using ((select private.is_member(family_id)));
create policy holiday_periods_insert on public.holiday_periods for insert with check ((select private.is_parent(family_id)));
create policy holiday_periods_update on public.holiday_periods for update using ((select private.is_parent(family_id))) with check ((select private.is_parent(family_id)));
create policy holiday_periods_delete on public.holiday_periods for delete using ((select private.is_parent(family_id)));
create policy holiday_overrides_select on public.holiday_overrides for select using ((select private.is_member(family_id)));
create policy holiday_overrides_insert on public.holiday_overrides for insert with check ((select private.is_parent(family_id)));
create policy holiday_overrides_update on public.holiday_overrides for update using ((select private.is_parent(family_id))) with check ((select private.is_parent(family_id)));
create policy holiday_overrides_delete on public.holiday_overrides for delete using ((select private.is_parent(family_id)));

-- 3. Règles de gestion des périodes
create or replace function private.holiday_period_check() returns trigger
language plpgsql security definer set search_path = '' as $$
declare today date;
begin
  if tg_op = 'DELETE' then
    -- Une période commencée ne se supprime pas : elle s'arrête (les étoiles gagnées restent).
    -- Sauf suppression de l'enfant ou de la famille (cascade).
    if exists (select 1 from public.children where id = old.child_id)
       and old.start_day < private.family_today(old.family_id) then raise exception 'SF:holiday_started'; end if;
    return old;
  end if;
  if tg_op = 'INSERT' and not private.is_premium(new.family_id) then raise exception 'SF:premium_holidays'; end if;
  if new.active and exists (select 1 from public.holiday_periods p
      where p.child_id = new.child_id and p.active and p.id <> new.id
        and p.start_day <= new.end_day and new.start_day <= p.end_day) then
    raise exception 'SF:holiday_overlap';
  end if;
  return new;
end $$;
create trigger holiday_periods_check before insert or update or delete on public.holiday_periods
  for each row execute function private.holiday_period_check();

-- Toute modification des vacances peut changer les journées passées de la période : recalcul des compteurs
create or replace function private.holiday_invalidate() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.children set stats_day = null where id = coalesce(new.child_id, old.child_id);
  return null;
end $$;
create trigger holiday_periods_invalidate after insert or update or delete on public.holiday_periods
  for each row execute function private.holiday_invalidate();
create trigger holiday_overrides_invalidate after insert or update or delete on public.holiday_overrides
  for each row execute function private.holiday_invalidate();

-- Fin du Premium : la période en cours va jusqu'au bout, les périodes à venir sont désactivées (gardées en base)
create or replace function private.plan_lapsed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.plan = 'free' and old.plan is distinct from 'free' then
    update public.holiday_periods set active = false
    where family_id = new.id and active and start_day > private.family_today(new.id);
  end if;
  return null;
end $$;
create trigger families_plan_lapsed after update of plan on public.families
  for each row execute function private.plan_lapsed();

-- 4. Routines dues d'un jour (habituelles réglées par la période + routines de vacances ; hors exceptionnelles)
create or replace function private.routine_rules(p_child uuid, p_day date)
returns table (routine_id uuid, stars int, is_bonus boolean, moment text)
language sql stable security definer set search_path = '' as $$
  with z as (select private.family_tz(c.family_id) as tz from public.children c where c.id = p_child),
  hp as (select p.id from public.holiday_periods p
         where p.child_id = p_child and p.active and p_day between p.start_day and p.end_day limit 1)
  select r.id, coalesce(o.stars, r.stars)::int,
    case o.status when 'bonus' then true when 'required' then false else r.is_bonus end, r.moment
  from public.routines r
  left join public.holiday_overrides o on o.routine_id = r.id and o.period_id = (select id from hp)
  where r.child_id = p_child and r.kind = 'regular'
    and (r.created_at at time zone (select tz from z))::date <= p_day
    and (r.ended_at is null or (r.ended_at at time zone (select tz from z))::date > p_day)
    and coalesce(o.days, r.days) @> array[extract(isodow from p_day)::smallint]
    and case when r.holiday_period_id is null then o.status is distinct from 'off'
             else r.holiday_period_id = (select id from hp) end
$$;

-- 5. Fonctions existantes réécrites sur routine_rules (mêmes signatures)
create or replace function private.garden_days(p_child uuid, p_from date, p_to date)
returns table(day date, due integer, earned integer, paused boolean, good boolean)
language sql stable security definer set search_path = '' as $$
  with d as (
    select g::date as day,
      (coalesce((select sum(rr.stars) from private.routine_rules(p_child, g::date) rr where not rr.is_bonus), 0)
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
$$;

create or replace function private.history_counters(p_child uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  c record; fam record; today date; r record;
  run int := 0; best int := 0; wk_ok boolean := true; wk_act int := 0; weeks int := 0;
  last_dow int; dw int; we_ok boolean := false; we_len int := 0; exp_len int; weekends int := 0; m int; s int; f int;
begin
  select * into c from public.children where id = p_child;
  select week_start, weekend_days into fam from public.families where id = c.family_id;
  today := private.family_today(c.family_id);
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
      count(rr.routine_id) filter (where rr.moment = 'matin' and not rr.is_bonus) as dm,
      count(rr.routine_id) filter (where rr.moment = 'matin' and not rr.is_bonus and cp.id is not null) as vm,
      count(rr.routine_id) filter (where rr.moment = 'soir' and not rr.is_bonus) as ds,
      count(rr.routine_id) filter (where rr.moment = 'soir' and not rr.is_bonus and cp.id is not null) as vs,
      count(rr.routine_id) as da, count(rr.routine_id) filter (where cp.id is not null) as va
    from days dd
    cross join lateral private.routine_rules(p_child, dd.d) rr
    left join public.completions cp on cp.routine_id = rr.routine_id and cp.day = dd.d and cp.validated_at is not null
    group by dd.d)
  select count(*) filter (where dm > 0 and dm = vm), count(*) filter (where ds > 0 and ds = vs), count(*) filter (where da > 0 and da = va)
    into m, s, f from x;

  return jsonb_build_object('best', best, 'trail', run, 'weeks', weeks, 'weekends', weekends, 'matin', m, 'soir', s, 'full', f);
end $$;

-- Étoiles d'une routine cochée : celles du jour (réglage vacances compris)
create or replace function private.set_completion_stars()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  select coalesce((select rr.stars from private.routine_rules(new.child_id, new.day) rr where rr.routine_id = new.routine_id), r.stars)
    into new.stars from public.routines r where r.id = new.routine_id;
  new.created_by := auth.uid();
  if new.source = 'parent' then new.validated_at := coalesce(new.validated_at, now()); new.validated_by := auth.uid();
  else new.validated_at := null; new.validated_by := null; end if;
  return new;
end $$;

create or replace function public.reminders_due(p_secret text)
returns json language plpgsql security definer set search_path = '' as $$
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
    where exists (select 1 from unnest(s.reminder_times) t
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
end $$;

-- Téléphone de l'enfant : une routine de vacances ne se coche que pendant sa période
create or replace function public.child_toggle(p_token text, p_routine uuid, p_day date, p_done boolean, p_source text default 'child')
returns json language plpgsql security definer set search_path = '' as $$
declare d record; today date; r record;
begin
  select * into d from private.device_child(p_token);
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
    insert into public.completions(family_id, child_id, routine_id, day, source)
    values (d.family_id, d.child_id, p_routine, p_day, case when p_source in ('child','timer') then p_source else 'child' end)
    on conflict (routine_id, day) do nothing;
  else
    if exists (select 1 from public.completions where routine_id = p_routine and day = p_day and validated_at is not null) then
      raise exception 'SF:validated_by_parent';
    end if;
    delete from public.completions where routine_id = p_routine and day = p_day and child_id = d.child_id and validated_at is null;
  end if;
  return json_build_object('ok', true);
end $$;

-- État de l'enfant : routines avec leur période de vacances, et les périodes (60 derniers jours et à venir)
create or replace function public.child_state(p_token text)
returns json language plpgsql security definer set search_path = '' as $$
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
end $$;
