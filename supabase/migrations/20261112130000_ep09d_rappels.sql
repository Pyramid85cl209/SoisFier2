-- EP-09 thème D : rappels (DT11-01, DT11-03, DT11-08). Additions seulement : compatible avec l'ancienne version de l'application
-- (même format de réponse pour la fonction send-reminders ; les abonnements existants gardent leurs heures).
-- À tester dans une transaction annulée (supabase/tests/ep09d_rappels_test.sql). Ne touche ni aux clés ni aux secrets des rappels (ADR-45, hors lot).
--
-- DT11-01  un enfant en pause ce jour-là ne reçoit rien et n'est plus cité dans le résumé des adultes (R11-03 CA5, R11-04 CA2)
-- DT11-03  les exceptionnelles obligatoires sont comptées comme à l'écran (DEC-32, R05-07 CA3) : l'une compte le jour où elle est faite,
--          sinon son dernier jour ; une exceptionnelle arrêtée est ignorée
-- DT11-08  heure du soir par défaut 18:00 en base (les abonnements existants ne changent pas)
-- DT11-07  inchangé : les adultes ne reçoivent que s'ils sont membres actuels de la famille

alter table public.push_subscriptions alter column reminder_times set default '{07:30,18:00}';

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
    select f.id, f.timezone as tz, (now() at time zone f.timezone) as now_l from public.families f
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
      exists (select 1 from public.pauses p where p.child_id = c.id and fam.now_l::date between p.start_day and p.end_day) as paused,
      (select count(*) from private.routine_rules(c.id, fam.now_l::date) rr where not rr.is_bonus) + o.total as total,
      (select count(*) from private.routine_rules(c.id, fam.now_l::date) rr where not rr.is_bonus
        and exists (select 1 from public.completions x where x.routine_id = rr.routine_id and x.day = fam.now_l::date)) + o.done as done,
      (select count(*) from public.completions x where x.child_id = c.id and x.validated_at is null) as pending
    from public.children c
    join fam on fam.id = c.family_id
    cross join lateral (
      -- exceptionnelles obligatoires, comme à l'écran
      select count(*) as total,
             count(*) filter (where exists (select 1 from public.completions x where x.routine_id = r.id and x.day = fam.now_l::date)) as done
      from public.routines r
      where r.child_id = c.id and r.kind = 'oneoff' and not r.is_bonus
        and case when r.ended_at is not null then (r.ended_at at time zone fam.tz)::date > fam.now_l::date else r.active end
        and fam.now_l::date between r.start_day and r.end_day
        and (exists (select 1 from public.completions x where x.routine_id = r.id and x.day = fam.now_l::date)
             or (fam.now_l::date = r.end_day and not exists (select 1 from public.completions x where x.routine_id = r.id)))
    ) o
    where exists (select 1 from due d where d.family_id = c.family_id)
  )
  select coalesce(json_agg(json_build_object(
    'endpoint', d.endpoint, 'p256dh', d.p256dh, 'auth', d.auth, 'locale', d.locale,
    'kind', case when d.child_device_id is not null then 'child' else 'parent' end,
    'left', case when d.child_device_id is not null then
        (select case when t.paused then null else t.total - t.done end
         from todo t join public.child_devices cd on cd.child_id = t.child_id where cd.id = d.child_device_id) end,
    'children', case when d.child_device_id is null then
        (select json_agg(json_build_object('name', t.name, 'done', t.done, 'total', t.total, 'pending', t.pending) order by t.name)
         from todo t where t.family_id = d.family_id and not t.paused and (t.total > 0 or t.pending > 0)) end
  )), '[]'::json) into items from due d;
  return json_build_object(
    'vapid_public', (select value from private.config where key = 'vapid_public'),
    'vapid_private', (select value from private.config where key = 'vapid_private'),
    'subject', (select value from private.config where key = 'vapid_subject'),
    'items', items);
end $function$;
