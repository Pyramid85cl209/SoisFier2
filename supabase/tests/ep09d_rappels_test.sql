-- Test de la migration ep09d (thème D d'EP-09 : rappels) : à lancer AVANT de l'appliquer, dans l'éditeur SQL de Supabase. Transaction annulée : famille, enfants, abonnements fictifs, rien n'est conservé.
-- Suppose la migration ep09a_controles_serveur appliquée (ou lancée avant dans la même transaction). Un test ne dépend que de l'heure du jour : il est à relancer, pas à comparer à une heure précise (le cas se place dans le quart d'heure courant de la famille).
-- Contenu : migration 20261112130000 puis les cas D1 à D11.
-- Résultat attendu : une seule ligne d'erreur « RESULT: … » contenant, dans l'ordre :
--  D1.defaut_base={07:30,18:00} D2.secret_faux=SF:access_denied D3.adulte_enfants=Enfant A:1/2,Enfant C:1/2 (Enfant B en pause : absent) D4.enfant_A_reste=1 D5.enfant_B_pause_reste=null
--  D6.enfant_C_reste=1 D7.adulte_apres_O1=Enfant A:1/2,Enfant C:2/2 D8.enfant_C_tout_fait=0 D9.arretee_ignoree_B_revient=Enfant A:1/2,Enfant B:0/1,Enfant C:1/1 D10.enfant_B_hors_pause=1 D11.non_membre=0
-- Lancé jusqu'ici sur une réplique locale du schéma (PostgreSQL 16), après A1 seule puis après A1, B, C1 et C2 (mêmes résultats), pas sur la base de production.
begin;
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
do $t$
declare
  u_par uuid := gen_random_uuid(); u_old uuid := gen_random_uuid();
  fid uuid; c1 uuid; c2 uuid; c3 uuid; dev1 uuid; dev2 uuid; dev3 uuid; r1 uuid; r2 uuid; o1 uuid; o2 uuid; o3 uuid;
  td date; hm text; res text := ''; sec text; j json; it json;
begin
  create or replace function pg_temp.sup(q text) returns text language plpgsql as $f$
  declare x text; begin execute q into x; return x; end $f$;
  sec := (select value from private.config where key = 'cron_secret');
  insert into auth.users(id, email) values (u_par, 'parent.test@example.invalid'), (u_old, 'ancien.test@example.invalid');
  insert into public.families(name, plan, timezone) values ('Famille test EP-09D', 'premium', 'Pacific/Auckland') returning id into fid;
  insert into public.family_members(family_id, user_id, role) values (fid, u_par, 'parent');
  td := (now() at time zone 'Pacific/Auckland')::date;
  hm := to_char((now() at time zone 'Pacific/Auckland') - interval '2 minutes', 'HH24:MI');   -- heure d'envoi : il y a 2 minutes (dans le quart d'heure)
  insert into public.children(family_id, name) values (fid, 'Enfant A') returning id into c1;   -- 2 routines dues, 1 faite
  insert into public.children(family_id, name) values (fid, 'Enfant B') returning id into c2;   -- en pause
  insert into public.children(family_id, name) values (fid, 'Enfant C') returning id into c3;   -- seulement des exceptionnelles
  insert into public.routines(family_id, child_id, title, moment, days) values (fid, c1, 'R1', 'matin', '{1,2,3,4,5,6,7}') returning id into r1;
  insert into public.routines(family_id, child_id, title, moment, days) values (fid, c1, 'R2', 'matin', '{1,2,3,4,5,6,7}') returning id into r2;
  insert into public.routines(family_id, child_id, title, moment, days) values (fid, c2, 'RB', 'matin', '{1,2,3,4,5,6,7}');
  insert into public.completions(routine_id, child_id, family_id, day, stars) values (r1, c1, fid, td, 1);
  insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (fid, c2, td, td, 'rest');
  -- exceptionnelles de l'enfant C : O1 dernier jour aujourd'hui (non faite) ; O2 pas finie (fin dans 3 jours, non faite) ; O3 faite aujourd'hui, fin dans 2 jours
  insert into public.routines(family_id, child_id, title, moment, days, kind, start_day, end_day, stars) values (fid, c3, 'O1', 'journee', '{1,2,3,4,5,6,7}', 'oneoff', td - 1, td, 1) returning id into o1;
  insert into public.routines(family_id, child_id, title, moment, days, kind, start_day, end_day, stars) values (fid, c3, 'O2', 'journee', '{1,2,3,4,5,6,7}', 'oneoff', td, td + 3, 1) returning id into o2;
  insert into public.routines(family_id, child_id, title, moment, days, kind, start_day, end_day, stars) values (fid, c3, 'O3', 'journee', '{1,2,3,4,5,6,7}', 'oneoff', td, td + 2, 1) returning id into o3;
  insert into public.completions(routine_id, child_id, family_id, day, stars) values (o3, c3, fid, td, 1);
  insert into public.child_devices(child_id, family_id, token_hash) values (c1, fid, 'h1') returning id into dev1;
  insert into public.child_devices(child_id, family_id, token_hash) values (c2, fid, 'h2') returning id into dev2;
  insert into public.child_devices(child_id, family_id, token_hash) values (c3, fid, 'h3') returning id into dev3;
  -- abonnements : un adulte (défaut de la base lu ensuite) et trois appareils d'enfant
  insert into public.push_subscriptions(family_id, user_id, endpoint, p256dh, auth) values (fid, u_par, 'e-parent', 'k', 'a');
  res := res || ' D1.defaut_base=' || (select reminder_times::text from public.push_subscriptions where endpoint = 'e-parent');
  update public.push_subscriptions set reminder_times = array[hm] where endpoint = 'e-parent';
  insert into public.push_subscriptions(family_id, child_device_id, endpoint, p256dh, auth, reminder_times) values
    (fid, dev1, 'e-c1', 'k', 'a', array[hm]), (fid, dev2, 'e-c2', 'k', 'a', array[hm]), (fid, dev3, 'e-c3', 'k', 'a', array[hm]);
  res := res || ' D2.secret_faux=';
  begin perform public.reminders_due('mauvais'); res := res || 'ok'; exception when others then res := res || sqlerrm; end;
  j := public.reminders_due(sec);
  -- adulte : résumé
  select i into it from json_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-parent';
  res := res || ' D3.adulte_enfants=' || (select string_agg((c ->> 'name') || ':' || (c ->> 'done') || '/' || (c ->> 'total'), ',' order by c ->> 'name') from json_array_elements(it -> 'children') c);
  select i into it from json_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-c1';
  res := res || ' D4.enfant_A_reste=' || coalesce(it ->> 'left', 'null');
  select i into it from json_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-c2';
  res := res || ' D5.enfant_B_pause_reste=' || coalesce(it ->> 'left', 'null');
  select i into it from json_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-c3';
  res := res || ' D6.enfant_C_reste=' || coalesce(it ->> 'left', 'null');
  -- D7 : O1 faite aujourd'hui => elle compte (faite), O2 toujours exclue ; l'adulte voit C : 2/2
  insert into public.completions(routine_id, child_id, family_id, day, stars) values (o1, c3, fid, td, 1);
  j := public.reminders_due(sec);
  select i into it from json_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-parent';
  res := res || ' D7.adulte_apres_O1=' || (select string_agg((c ->> 'name') || ':' || (c ->> 'done') || '/' || (c ->> 'total'), ',' order by c ->> 'name') from json_array_elements(it -> 'children') c);
  select i into it from json_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-c3';
  res := res || ' D8.enfant_C_tout_fait=' || coalesce(it ->> 'left', 'null');
  -- D9 : exceptionnelle arrêtée aujourd'hui ignorée ; pause terminée : l'enfant B revient
  update public.routines set ended_at = now(), active = false where id = o3;
  delete from public.pauses where child_id = c2;
  j := public.reminders_due(sec);
  select i into it from json_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-parent';
  res := res || ' D9.arretee_ignoree_B_revient=' || (select string_agg((c ->> 'name') || ':' || (c ->> 'done') || '/' || (c ->> 'total'), ',' order by c ->> 'name') from json_array_elements(it -> 'children') c);
  select i into it from json_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-c2';
  res := res || ' D10.enfant_B_hors_pause=' || coalesce(it ->> 'left', 'null');
  -- D11 : un ancien membre (retiré) n'est pas servi (DT11-07 conservé)
  insert into public.push_subscriptions(family_id, user_id, endpoint, p256dh, auth, reminder_times) values (fid, u_old, 'e-old', 'k', 'a', array[hm]);
  j := public.reminders_due(sec);
  res := res || ' D11.non_membre=' || (select count(*) from json_array_elements(j -> 'items') i where i ->> 'endpoint' = 'e-old');
  raise exception 'RESULT:%', res;
end $t$;
