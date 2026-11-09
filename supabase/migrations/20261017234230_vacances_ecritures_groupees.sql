-- v24 : Mode vacances, écritures groupées (un seul appel au lieu de plusieurs).
-- holiday_create : crée la période et reprend éventuellement une période précédente du même enfant.
-- holiday_copy : copie les routines de vacances d'une autre période (frère ou sœur).

-- Copie d'une période vers une autre : réglages des routines habituelles (même enfant seulement) et routines de vacances
create or replace function private.holiday_copy_into(p_from uuid, p_to uuid, p_settings boolean)
returns int language plpgsql security definer set search_path = '' as $$
declare src record; dst record; n int := 0; k int; base int;
begin
  select * into src from public.holiday_periods where id = p_from;
  select * into dst from public.holiday_periods where id = p_to;
  if src.id is null or dst.id is null or src.family_id <> dst.family_id then raise exception 'SF:access_denied'; end if;
  if p_settings and src.child_id = dst.child_id then
    insert into public.holiday_overrides(period_id, routine_id, child_id, family_id, status, days, stars)
    select dst.id, o.routine_id, dst.child_id, dst.family_id, o.status, o.days, o.stars
    from public.holiday_overrides o join public.routines r on r.id = o.routine_id
    where o.period_id = src.id and r.active and r.kind = 'regular' and r.holiday_period_id is null
    on conflict (period_id, routine_id) do update set status = excluded.status, days = excluded.days, stars = excluded.stars;
    get diagnostics k = row_count; n := n + k;
  end if;
  select count(*) into base from public.routines where child_id = dst.child_id;
  insert into public.routines(family_id, child_id, holiday_period_id, title, emoji, moment, place, stars, days, is_bonus, timer_minutes, position)
  select dst.family_id, dst.child_id, dst.id, r.title, r.emoji, r.moment, r.place, r.stars, r.days, r.is_bonus, r.timer_minutes,
         base + row_number() over (order by r.position, r.created_at)
  from public.routines r
  where r.holiday_period_id = src.id and r.active
    and lower(r.title) not in (select lower(x.title) from public.routines x where x.holiday_period_id = dst.id and x.active);
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;

create or replace function public.holiday_create(p_child uuid, p_name text, p_from date, p_to date, p_copy uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare fid uuid; pid uuid;
begin
  select family_id into fid from public.children where id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:access_denied'; end if;
  insert into public.holiday_periods(family_id, child_id, name, start_day, end_day, created_by)
  values (fid, p_child, trim(p_name), p_from, p_to, auth.uid()) returning id into pid;
  if p_copy is not null then perform private.holiday_copy_into(p_copy, pid, true); end if;
  return pid;
end $$;

create or replace function public.holiday_copy(p_from uuid, p_to uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare fid uuid;
begin
  select family_id into fid from public.holiday_periods where id = p_to;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:access_denied'; end if;
  return private.holiday_copy_into(p_from, p_to, false);
end $$;
