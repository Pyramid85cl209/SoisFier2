-- Test de la migration ep09g (thème G d'EP-09 : présentation « déjà vue » des comptes existants) : à lancer AVANT de l'appliquer, dans l'éditeur SQL de Supabase.
-- Transaction annulée : comptes, familles et routines fictifs (adresses en .invalid), rien n'est conservé.
-- Déroulé : 1. jeu d'essai ; 2. migration 20261112150000 (copie) ; 3. contrôles.
-- Résultat attendu : une seule ligne d'erreur « RESULT: … » contenant, dans l'ordre :
--  G1.routine_active=vu G2.routine_arretee=vu G3.famille_sans_routine=non_vu G4.sans_famille=non_vu G5.deux_familles=vu G6.metadonnees_gardees=ok G7.rejouee=ok G8.sans_routine_jamais_marque=ok
-- Lancé jusqu'ici sur une réplique locale du schéma (PostgreSQL 16), pas sur la base de production.
begin;
do $s$
declare fa uuid; fb uuid; fc uuid; ca uuid; cb uuid; cc uuid;
begin
  insert into auth.users(id, email, raw_user_meta_data) values
    ('a0000000-0000-0000-0000-000000000001', 'g1@example.invalid', '{"display_name":"Test 1"}'), ('a0000000-0000-0000-0000-000000000002', 'g2@example.invalid', null),
    ('a0000000-0000-0000-0000-000000000003', 'g3@example.invalid', '{"display_name":"Test 3"}'), ('a0000000-0000-0000-0000-000000000004', 'g4@example.invalid', '{}'),
    ('a0000000-0000-0000-0000-000000000005', 'g5@example.invalid', '{"display_name":"Test 5"}');
  insert into public.families(name, plan) values ('Famille G-A', 'free') returning id into fa;
  insert into public.families(name, plan) values ('Famille G-B', 'free') returning id into fb;
  insert into public.families(name, plan) values ('Famille G-C', 'free') returning id into fc;
  insert into public.children(family_id, name) values (fa, 'Enfant A') returning id into ca;
  insert into public.children(family_id, name) values (fb, 'Enfant B') returning id into cb;
  insert into public.children(family_id, name) values (fc, 'Enfant C') returning id into cc;
  insert into public.routines(family_id, child_id, title, active) values (fa, ca, 'Routine active', true);
  insert into public.routines(family_id, child_id, title, active) values (fb, cb, 'Routine arrêtée', false);   -- fc : enfant sans aucune routine
  insert into public.family_members(family_id, user_id) values (fa, 'a0000000-0000-0000-0000-000000000001'), (fb, 'a0000000-0000-0000-0000-000000000002'),
    (fc, 'a0000000-0000-0000-0000-000000000003'), (fa, 'a0000000-0000-0000-0000-000000000005'), (fc, 'a0000000-0000-0000-0000-000000000005');   -- le compte 4 n'a aucune famille
end $s$;
-- Copie de supabase/migrations/20261112150000_ep09g_intro_vue_comptes_existants.sql (en cas d'écart, la migration fait foi)
update auth.users u
   set raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb) || '{"intro_seen": true}'::jsonb
 where exists (select 1 from public.family_members m join public.routines r on r.family_id = m.family_id where m.user_id = u.id);
do $t$
declare res text := ''; before_n int; after_n int;
  v text;
begin
  for v in select unnest(array['1:G1.routine_active','2:G2.routine_arretee','3:G3.famille_sans_routine','4:G4.sans_famille','5:G5.deux_familles']) loop
    res := res || ' ' || split_part(v, ':', 2) || '=' || case when (select raw_user_meta_data->>'intro_seen' from auth.users where id = ('a0000000-0000-0000-0000-00000000000' || split_part(v, ':', 1))::uuid) = 'true' then 'vu' else 'non_vu' end;
  end loop;
  res := res || ' G6.metadonnees_gardees=' || case when (select raw_user_meta_data->>'display_name' from auth.users where id = 'a0000000-0000-0000-0000-000000000001') = 'Test 1'
    and (select raw_user_meta_data->>'display_name' from auth.users where id = 'a0000000-0000-0000-0000-000000000005') = 'Test 5' then 'ok' else 'perdues' end;
  select count(*) into before_n from auth.users where raw_user_meta_data->>'intro_seen' = 'true';
  update auth.users u set raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb) || '{"intro_seen": true}'::jsonb
   where exists (select 1 from public.family_members m join public.routines r on r.family_id = m.family_id where m.user_id = u.id);
  select count(*) into after_n from auth.users where raw_user_meta_data->>'intro_seen' = 'true';
  res := res || ' G7.rejouee=' || case when before_n = after_n then 'ok' else 'ecart' end;
  res := res || ' G8.sans_routine_jamais_marque=' || case when not exists (select 1 from auth.users x where x.raw_user_meta_data->>'intro_seen' = 'true'
    and not exists (select 1 from public.family_members m join public.routines r on r.family_id = m.family_id where m.user_id = x.id)) then 'ok' else 'ecart' end;
  raise exception 'RESULT:%', res;
end $t$;
