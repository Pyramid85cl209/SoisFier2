-- EP-01 lot B : rappels regroupés (ADR-55), rappel à l'heure d'une routine (ADR-57), secrets hors base (ADR-45, DT11-09).
-- Additions seulement : aucune ligne de private.config n'est supprimée ici (supabase/editeur-sql/ep01_retraits.sql, après la mise en ligne).
-- ORDRE DE MISE EN LIGNE : 1) secrets VAPID_PRIVATE_KEY et VAPID_SUBJECT posés dans les secrets de la fonction Edge ;
-- 2) fonction send-reminders redéployée (elle lit ses clés dans ses secrets, sinon dans la réponse, et comprend les deux formats) ;
-- 3) cette migration ; 4) plus tard, retraits (éditeur SQL). Après l'étape 3, reminders_due ne renvoie plus de clé privée.
-- À tester dans une transaction annulée : supabase/tests/ep01b_rappels_secrets_test.sql.

------------------------------------------------------------------------------------------------------------------------
-- 1. Rappel à l'heure d'une routine : donnée, contrainte, Premium (ADR-57)
------------------------------------------------------------------------------------------------------------------------
alter table public.routines add column if not exists remind_at time;
alter table public.routines drop constraint if exists routines_remind_at_check;
alter table public.routines add constraint routines_remind_at_check check (
  remind_at is null or (kind = 'regular'
    and extract(minute from remind_at)::int in (0, 15, 30, 45) and extract(second from remind_at) = 0
    and remind_at >= time '05:00' and remind_at <= time '23:45'));

create or replace function private.remind_guard() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.remind_at is null then return new; end if;
  if tg_op = 'UPDATE' and new.remind_at is not distinct from old.remind_at then return new; end if;
  if not private.is_premium(new.family_id) then raise exception 'SF:premium_reminder'; end if;
  return new;
end $$;
drop trigger if exists routines_remind_premium on public.routines;
create trigger routines_remind_premium before insert or update of remind_at on public.routines
  for each row execute function private.remind_guard();

------------------------------------------------------------------------------------------------------------------------
-- 2. Abonnements : plusieurs familles, lignes « Mode enfant ici » (ADR-55, ADR-57)
------------------------------------------------------------------------------------------------------------------------
-- Un membre qui quitte une famille : l'abonnement passe à une autre famille du compte s'il en reste une, sinon il est supprimé (C-20)
create or replace function private.member_left() returns trigger language plpgsql security definer set search_path = '' as $$
declare other uuid;
begin
  select m.family_id into other from public.family_members m where m.user_id = old.user_id and m.family_id <> old.family_id order by m.created_at limit 1;
  if other is not null then
    update public.push_subscriptions set family_id = other where family_id = old.family_id and user_id = old.user_id;
  else
    delete from public.push_subscriptions where family_id = old.family_id and user_id = old.user_id;
  end if;
  return old;
end $$;

-- Abonnement de l'adulte, avec les jetons « Mode enfant ici » gardés sur ce téléphone : leur adresse d'envoi est notée (ADR-57)
create or replace function public.parent_push_subscribe(p_family uuid, p_endpoint text, p_p256dh text, p_auth text, p_times text[], p_locale text, p_tokens text[])
returns void language plpgsql security definer set search_path = '' as $$
declare loc text := private.valid_locale(p_locale);
begin
  if not private.is_member(p_family) then raise exception 'SF:access_denied'; end if;
  insert into public.push_subscriptions(family_id, user_id, child_device_id, endpoint, p256dh, auth, reminder_times, locale)
  values (p_family, auth.uid(), null, p_endpoint, p_p256dh, p_auth, p_times, loc)
  on conflict (endpoint) do update set family_id = excluded.family_id, user_id = excluded.user_id,
    child_device_id = null, p256dh = excluded.p256dh, auth = excluded.auth, reminder_times = excluded.reminder_times, locale = excluded.locale;
  update public.child_devices d set here_endpoint = p_endpoint
  where d.mode_here and d.token_hash in (select encode(extensions.digest(t, 'sha256'), 'hex') from unnest(coalesce(p_tokens, array[]::text[])) t)
    and exists (select 1 from public.family_members m where m.family_id = d.family_id and m.user_id = auth.uid());
end $$;
revoke all on function public.parent_push_subscribe(uuid, text, text, text, text[], text, text[]) from public, anon;
grant execute on function public.parent_push_subscribe(uuid, text, text, text, text[], text, text[]) to authenticated;

------------------------------------------------------------------------------------------------------------------------
-- 3. Secret de la tâche dans Vault (ADR-45) : copie du secret actuel, la valeur ne transite par aucun client
------------------------------------------------------------------------------------------------------------------------
do $v$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_secret') then
    perform vault.create_secret((select value from private.config where key = 'cron_secret'), 'cron_secret', 'Secret de la tâche des rappels (ADR-45)');
  end if;
end $v$;

select cron.alter_job(
  (select jobid from cron.job where jobname = 'soisfier-reminders'),
  command := $cmd$
  select net.http_post(
    url := 'https://mlgrtpuvnjgkjnmhnlfg.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
  $cmd$);

------------------------------------------------------------------------------------------------------------------------
-- 4. reminders_due : familles du compte, appareil commun, rappels de routine, plus aucune clé renvoyée
--    Lecture seule : aucune écriture, aucun appel réseau (l'envoi est fait par send-reminders).
--    Formats : résumé adulte {kind:'parent', children:[{name, done, total, pending, family?}]} ; résumé appareil
--    {kind:'child', left} (un enfant) ou {kind:'child', kids:[{name, left}]} (appareil commun) ;
--    rappel de routine {kind:'routine', mode:'device'|'here', child, common, at, routines:[{title, emoji}]}.
------------------------------------------------------------------------------------------------------------------------
create or replace function public.reminders_due(p_secret text)
returns json language plpgsql security definer set search_path = '' as $$
declare sec text; sums jsonb; routs jsonb;
begin
  select decrypted_secret into sec from vault.decrypted_secrets where name = 'cron_secret';
  if p_secret is null or sec is null or p_secret is distinct from sec then raise exception 'SF:access_denied'; end if;

  with fam as (
    select f.id, f.name, f.timezone as tz, (now() at time zone f.timezone) as now_l from public.families f
  ),
  due as (
    select s.* from public.push_subscriptions s join fam on fam.id = s.family_id
    where (s.child_device_id is not null
           or exists (select 1 from public.family_members m where m.family_id = s.family_id and m.user_id = s.user_id))
      and exists (select 1 from unnest(s.reminder_times) t
                  where t ~ '^\d{2}:\d{2}$' and fam.now_l::time >= t::time and fam.now_l::time < t::time + interval '15 minutes')
  ),
  cov as (
    select d.id as sub_id, c.id as child_id from due d
      join public.family_members m on m.user_id = d.user_id join public.children c on c.family_id = m.family_id
    where d.child_device_id is null
    union all
    select d.id, l.child_id from due d join public.child_device_children l on l.device_id = d.child_device_id
    where d.child_device_id is not null
  ),
  todo as (
    select c.id as child_id, c.family_id, c.name, fc.name as fam_name,
      exists (select 1 from public.pauses p where p.child_id = c.id and fc.now_l::date between p.start_day and p.end_day) as paused,
      (select count(*) from private.routine_rules(c.id, fc.now_l::date) rr where not rr.is_bonus) + o.total as total,
      (select count(*) from private.routine_rules(c.id, fc.now_l::date) rr where not rr.is_bonus
        and exists (select 1 from public.completions x where x.routine_id = rr.routine_id and x.day = fc.now_l::date)) + o.done as done,
      (select count(*) from public.completions x where x.child_id = c.id and x.validated_at is null) as pending
    from public.children c
    join fam fc on fc.id = c.family_id
    cross join lateral (
      select count(*) as total,
             count(*) filter (where exists (select 1 from public.completions x where x.routine_id = r.id and x.day = fc.now_l::date)) as done
      from public.routines r
      where r.child_id = c.id and r.kind = 'oneoff' and not r.is_bonus
        and case when r.ended_at is not null then (r.ended_at at time zone fc.tz)::date > fc.now_l::date else r.active end
        and fc.now_l::date between r.start_day and r.end_day
        and (exists (select 1 from public.completions x where x.routine_id = r.id and x.day = fc.now_l::date)
             or (fc.now_l::date = r.end_day and not exists (select 1 from public.completions x where x.routine_id = r.id)))
    ) o
    where exists (select 1 from cov where cov.child_id = c.id)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'endpoint', d.endpoint, 'p256dh', d.p256dh, 'auth', d.auth, 'locale', d.locale,
    'kind', case when d.child_device_id is not null then 'child' else 'parent' end,
    'left', case when d.child_device_id is not null
                  and (select count(*) from public.child_device_children l where l.device_id = d.child_device_id) = 1 then
        (select case when t.paused then null else t.total - t.done end
         from todo t join public.child_device_children l on l.child_id = t.child_id where l.device_id = d.child_device_id) end,
    'kids', case when d.child_device_id is not null
                  and (select count(*) from public.child_device_children l where l.device_id = d.child_device_id) > 1 then
        (select jsonb_agg(jsonb_build_object('name', t.name, 'left', t.total - t.done) order by t.name)
         from todo t join cov on cov.child_id = t.child_id and cov.sub_id = d.id where not t.paused) end,
    'children', case when d.child_device_id is null then
        (select jsonb_agg(jsonb_build_object('name', t.name, 'done', t.done, 'total', t.total, 'pending', t.pending,
            'family', case when (select count(*) from public.family_members m where m.user_id = d.user_id) >= 2 then t.fam_name end)
            order by t.fam_name, t.name)
         from todo t join cov on cov.child_id = t.child_id and cov.sub_id = d.id
         where not t.paused and (t.total > 0 or t.pending > 0)) end
  )), '[]'::jsonb) into sums from due d;

  -- Rappels à l'heure d'une routine (F11-05, R11-10) : routines habituelles Premium dues ce jour, non cochées, enfant hors pause
  with fam as (
    select f.id, (now() at time zone f.timezone) as now_l from public.families f
  ),
  rem as (
    select r.id as rid, r.title, r.emoji, r.remind_at, c.id as child_id, c.name as child_name, c.family_id
    from public.routines r
    join public.children c on c.id = r.child_id
    join fam on fam.id = r.family_id
    where r.kind = 'regular' and r.active and r.remind_at is not null and private.is_premium(r.family_id)
      and (extract(hour from fam.now_l) * 60 + extract(minute from fam.now_l))::int
          between (extract(hour from r.remind_at) * 60 + extract(minute from r.remind_at))::int
              and (extract(hour from r.remind_at) * 60 + extract(minute from r.remind_at))::int + 14
      and not exists (select 1 from public.pauses p where p.child_id = c.id and fam.now_l::date between p.start_day and p.end_day)
      and exists (select 1 from private.routine_rules(c.id, fam.now_l::date) rr where rr.routine_id = r.id)
      and not exists (select 1 from public.completions x where x.routine_id = r.id and x.day = fam.now_l::date)
  ),
  dev as (
    select distinct s.id as sub_id, s.endpoint, s.p256dh, s.auth, s.locale, rem.child_id, 'device'::text as mode,
      (select count(*) from public.child_device_children l2 where l2.device_id = cd.id) > 1 as common
    from rem
    join public.child_device_children l on l.child_id = rem.child_id
    join public.child_devices cd on cd.id = l.device_id and not cd.mode_here
    join public.push_subscriptions s on s.child_device_id = cd.id
  ),
  here as (
    select distinct s.id as sub_id, s.endpoint, s.p256dh, s.auth, s.locale, rem.child_id, 'here'::text as mode, false as common
    from rem
    join public.child_device_children l on l.child_id = rem.child_id
    join public.child_devices cd on cd.id = l.device_id and cd.mode_here and cd.here_endpoint is not null
    join public.push_subscriptions s on s.endpoint = cd.here_endpoint and s.user_id is not null
    where not exists (select 1 from dev where dev.child_id = rem.child_id)
      and exists (select 1 from public.family_members m where m.family_id = rem.family_id and m.user_id = s.user_id)
  ),
  dest as (select * from dev union all select * from here)
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', 'routine', 'mode', g.mode, 'endpoint', g.endpoint, 'p256dh', g.p256dh, 'auth', g.auth, 'locale', g.locale,
    'child', g.child_name, 'common', g.common, 'at', to_char(g.remind_at, 'HH24:MI'), 'routines', g.rts)), '[]'::jsonb) into routs
  from (
    select dest.mode, dest.endpoint, dest.p256dh, dest.auth, dest.locale, dest.common, rem.child_name, rem.remind_at,
      jsonb_agg(jsonb_build_object('title', rem.title, 'emoji', rem.emoji) order by rem.title) as rts
    from dest join rem on rem.child_id = dest.child_id
    group by dest.sub_id, dest.mode, dest.endpoint, dest.p256dh, dest.auth, dest.locale, dest.common, rem.child_id, rem.child_name, rem.remind_at
  ) g;

  return json_build_object('vapid_public', (select value from private.config where key = 'vapid_public'), 'items', sums || routs);
end $$;
