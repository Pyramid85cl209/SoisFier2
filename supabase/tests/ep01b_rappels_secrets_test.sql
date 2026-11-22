-- Test de la migration ep01b_rappels_secrets (EP-01 lot B), à coller dans l'éditeur SQL de Supabase (le fichier contient la migration puis les cas).
-- Tout se passe dans une transaction annulée : famille, enfants, utilisateurs, appareils et abonnements fictifs, rien n'est conservé.
-- Résultat : une ligne d'erreur « RESULT: … ». Le dernier cas lit cron.job : la commande doit avoir été remplacée par la migration.
begin;
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

do $t$
declare
  u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid();
  tz text; f1 uuid; f2 uuid; f3 uuid; c1 uuid; c1b uuid; c2 uuid; c3 uuid; r1 uuid; r2 uuid; r3 uuid; r4 uuid;
  d_com uuid; d_one uuid; d_here uuid; hm text; qt time; sec text; j jsonb; it jsonb; res text := '';
begin
  tz := (select z from unnest(array['Pacific/Auckland','Europe/Paris','America/New_York','Asia/Tokyo','Pacific/Honolulu']) z
         where extract(hour from now() at time zone z) between 6 and 21 limit 1);
  insert into auth.users(id, email) values (u1, 'p1.test@example.invalid'), (u2, 'p2.test@example.invalid');
  insert into public.families(name, plan, timezone) values ('Fam1', 'premium', tz) returning id into f1;
  insert into public.families(name, plan, timezone) values ('Fam2', 'premium', tz) returning id into f2;
  insert into public.families(name, plan, timezone) values ('Fam3', 'free', tz) returning id into f3;
  insert into public.family_members(family_id, user_id, role) values (f1, u1, 'parent'), (f2, u1, 'parent'), (f3, u2, 'parent'), (f1, u2, 'parent'), (f2, u2, 'parent');
  qt := ((date_trunc('hour', now() at time zone tz) + floor(extract(minute from now() at time zone tz) / 15) * interval '15 minutes'))::time;
  hm := to_char((now() at time zone tz) - interval '1 minute', 'HH24:MI');
  insert into public.children(family_id, name) values (f1, 'Enf1') returning id into c1;
  insert into public.children(family_id, name) values (f1, 'Enf1b') returning id into c1b;
  insert into public.children(family_id, name) values (f2, 'Enf2') returning id into c2;
  insert into public.children(family_id, name) values (f3, 'Enf3') returning id into c3;
  insert into public.routines(family_id, child_id, title, emoji, moment, remind_at) values (f1, c1, 'R1', 'a', 'matin', qt) returning id into r1;
  insert into public.routines(family_id, child_id, title, emoji, moment, remind_at) values (f1, c1, 'R1b', 'b', 'matin', qt);
  insert into public.routines(family_id, child_id, title, emoji, moment, remind_at) values (f2, c2, 'R2', 'c', 'matin', qt) returning id into r2;
  insert into public.routines(family_id, child_id, title, emoji, moment) values (f1, c1b, 'R1c', 'd', 'matin') returning id into r3;
  begin insert into public.routines(family_id, child_id, title, emoji, moment, remind_at) values (f3, c3, 'R3', 'e', 'matin', qt);
        res := res || ' 1.gratuit_remind=ok'; exception when others then res := res || ' 1.gratuit_remind=' || sqlerrm; end;
  begin insert into public.routines(family_id, child_id, title, moment, remind_at) values (f1, c1, 'X', 'matin', time '10:10'); res := res || ' 2.minute10=ok';
        exception when others then res := res || ' 2.minute10=refuse'; end;
  begin insert into public.routines(family_id, child_id, title, moment, remind_at) values (f1, c1, 'X', 'matin', time '04:45'); res := res || ' 2b.avant5h=ok';
        exception when others then res := res || ' 2b.avant5h=refuse'; end;
  begin insert into public.routines(family_id, child_id, title, moment, kind, start_day, end_day, remind_at) values (f1, c1, 'X', 'matin', 'oneoff', current_date, current_date, time '10:00'); res := res || ' 2c.oneoff=ok';
        exception when others then res := res || ' 2c.oneoff=refuse'; end;
  begin update public.routines set remind_at = null where id = r1; update public.routines set remind_at = qt where id = r1; res := res || ' 2d.maj_premium=ok';
        exception when others then res := res || ' 2d.maj=' || sqlerrm; end;
  -- appareils : commun (c1, c1b), un enfant (c2 : Mode ici), Mode ici de c3 (famille gratuite)
  insert into public.child_devices(child_id, family_id, token_hash, label) values (c1, f1, 'h-com', 'Commun') returning id into d_com;
  insert into public.child_device_children(device_id, child_id, family_id) values (d_com, c1, f1), (d_com, c1b, f1);
  insert into public.child_devices(child_id, family_id, token_hash, label, mode_here, here_endpoint) values (c2, f2, 'h-here', 'Ici', true, 'e-par') returning id into d_here;
  insert into public.child_device_children(device_id, child_id, family_id) values (d_here, c2, f2);
  insert into public.push_subscriptions(family_id, user_id, endpoint, p256dh, auth, reminder_times) values (f1, u1, 'e-par', 'k', 'a', array[hm]);
  insert into public.push_subscriptions(family_id, child_device_id, endpoint, p256dh, auth, reminder_times) values (f1, d_com, 'e-com', 'k', 'a', array[hm]);
  sec := (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret');
  res := res || ' 3.vault=' || (sec is not null) || '/egal_config=' || (sec = (select value from private.config where key = 'cron_secret'));
  begin perform public.reminders_due('mauvais'); res := res || ' 4.secret_faux=ok'; exception when others then res := res || ' 4.secret_faux=' || sqlerrm; end;
  j := public.reminders_due(sec)::jsonb;
  res := res || ' 5.cles=' || (select string_agg(k, ',' order by k) from jsonb_object_keys(j) k);
  select i into it from jsonb_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-par' and i ->> 'kind' = 'parent';
  res := res || ' 6.adulte_2_familles=' || coalesce((select string_agg(coalesce(c ->> 'family', '-') || '/' || (c ->> 'name'), ',' order by c ->> 'family', c ->> 'name') from jsonb_array_elements(it -> 'children') c), 'aucun');
  select i into it from jsonb_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-com' and i ->> 'kind' = 'child';
  res := res || ' 7.appareil_commun_kids=' || coalesce((select string_agg((k ->> 'name') || ':' || (k ->> 'left'), ',' order by k ->> 'name') from jsonb_array_elements(it -> 'kids') k), 'aucun') || '/left=' || coalesce(it ->> 'left', 'null');
  select i into it from jsonb_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-com' and i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf1';
  res := res || ' 8.routine_commun=' || coalesce((select string_agg(r ->> 'title', ',' order by r ->> 'title') from jsonb_array_elements(it -> 'routines') r), 'aucune') || '/mode=' || coalesce(it ->> 'mode', '-') || '/common=' || coalesce(it ->> 'common', '-') || '/at_ok=' || coalesce((it ->> 'at') = to_char(qt, 'HH24:MI'), false);
  select i into it from jsonb_array_elements(j -> 'items') i where i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf1b';
  res := res || ' 9.sans_rappel_enf1b=' || (it is null);
  select i into it from jsonb_array_elements(j -> 'items') i where i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf2';
  res := res || ' 10.mode_ici=' || coalesce(it ->> 'endpoint', 'aucun') || '/' || coalesce(it ->> 'mode', '-');
  -- 11 : l'enfant a un appareil à lui avec abonnement : le téléphone du parent ne reçoit plus le rappel
  insert into public.push_subscriptions(family_id, child_device_id, endpoint, p256dh, auth, reminder_times) values (f2, (select id from public.child_devices where token_hash = 'h-here'), 'e-ici-sub', 'k', 'a', array['00:00']);
  j := public.reminders_due(sec)::jsonb;
  res := res || ' 11.mode_ici_avec_abonnement_propre=' || (select count(*) from jsonb_array_elements(j -> 'items') i where i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf2');
  delete from public.push_subscriptions where endpoint = 'e-ici-sub';
  -- 12 : routine cochée, famille gratuite, pause
  insert into public.completions(routine_id, child_id, family_id, day, stars) values (r2, c2, f2, (now() at time zone tz)::date, 1);
  j := public.reminders_due(sec)::jsonb;
  res := res || ' 12.cochee=' || (select count(*) from jsonb_array_elements(j -> 'items') i where i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf2');
  insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (f1, c1, (now() at time zone tz)::date, (now() at time zone tz)::date, 'rest');
  j := public.reminders_due(sec)::jsonb;
  res := res || ' 13.pause=' || (select count(*) from jsonb_array_elements(j -> 'items') i where i ->> 'kind' = 'routine' and i ->> 'child' = 'Enf1');
  begin update public.families set plan = 'free' where id = f2; exception when others then res := res || ' 13b.x=' || sqlerrm; end;
  -- 14 : parent_push_subscribe avec jetons
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.parent_push_subscribe(f1, 'e-nouveau', 'k', 'a', array['07:30'], 'fr', array['jeton-inconnu']); res := res || ' 14.abonne_jetons=ok'; exception when others then res := res || ' 14.x=' || sqlerrm; end;
  begin perform public.parent_push_subscribe(f3, 'e-x', 'k', 'a', array['07:30'], 'fr', null); res := res || ' 14b.autre_famille=ok'; exception when others then res := res || ' 14b.autre_famille=' || sqlerrm; end;
  reset role;
  -- 15 : départ d'une famille : l'abonnement suit, puis disparaît au dernier départ
  begin
  delete from public.family_members where family_id = f1 and user_id = u1;
  res := res || ' 15.apres_depart_f1=' || coalesce((select (family_id = f2)::text from public.push_subscriptions where endpoint = 'e-par'), 'supprime');
  delete from public.family_members where family_id = f2 and user_id = u1;
  res := res || ' 15b.apres_depart_f2=' || coalesce((select 'reste' from public.push_subscriptions where endpoint = 'e-par'), 'supprime');
  exception when others then res := res || ' 15.x=' || sqlerrm; end;
  res := res || ' 16.cron_sans_config=' || (select (command not like '%private.config%' and command like '%vault.decrypted_secrets%') from cron.job where jobname = 'soisfier-reminders');
  raise exception 'RESULT:%', res;
end $t$;
