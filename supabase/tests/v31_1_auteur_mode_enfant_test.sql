-- Test de la migration v31_1_auteur_mode_enfant (DT05-06) : à lancer AVANT d'appliquer la migration, dans l'éditeur SQL de Supabase
-- (la migration redéfinit child_toggle, dont la branche « décocher » contient un delete inchangé : le connecteur demande alors une confirmation).
-- Tout se passe dans une transaction annulée : famille, enfant, utilisateurs, appareil et récompense sont fictifs, rien n'est conservé.
-- Le fichier contient la migration puis les cas ; à régénérer si la migration change.
-- Résultat attendu (une seule ligne, message d'erreur « RESULT: … ») :
--  1.ici_coche=vide/non_validee  1b.ici_chrono=vide  2.ici_echange=vide  3.proche_ici=vide/vide
--  4.sans_session=vide/vide  5.parent_coche=parent/validee_parent  6.forge_coche=parent  6b.forge_source_enfant=parent
--  7.forge_echange=parent  8.apres_rpc=parent/parent  9.modif_auteur=vide  10.autre_famille=SF:routine_not_found
--  11.droits=anon:true/connecte:true  12.repere_fin=vide
begin;
-- v31.1 (correctif, DT05-06) : en Mode enfant ici (téléphone d'un adulte connecté, ouvert en mode enfant),
-- une coche ou un échange envoyé par l'enfant ne porte plus l'adulte connecté comme auteur.
-- Comme sur l'appareil de l'enfant sans session, created_by reste vide (affiché au prénom de l'enfant).
-- Seuls child_toggle et child_redeem (jeton d'appareil vérifié par private.device_child) posent le repère
-- sf.via_device, local à la transaction ; il n'est pas modifiable depuis l'API (PostgREST n'expose pas set_config).
-- Toute autre écriture garde auth.uid() (T05-16 : auteur fixé par le serveur, pas d'auteur forgé).
-- Pas de reprise des données déjà enregistrées (décision du 11/11/2026). Sans drop ni delete.

-- 1. Déclencheurs d'auteur
create or replace function private.set_completion_stars()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  select coalesce((select rr.stars from private.routine_rules(new.child_id, new.day) rr where rr.routine_id = new.routine_id), r.stars)
    into new.stars from public.routines r where r.id = new.routine_id;
  if coalesce(current_setting('sf.via_device', true), '') = 'on' and new.source in ('child', 'timer') then
    new.created_by := null;   -- action de l'enfant par son jeton d'appareil (Mode enfant ici compris)
  else
    new.created_by := auth.uid();
  end if;
  if new.source = 'parent' then new.validated_at := coalesce(new.validated_at, now()); new.validated_by := auth.uid();
  else new.validated_at := null; new.validated_by := null; end if;
  return new;
end $function$;

create or replace function private.set_redemption_author()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if coalesce(current_setting('sf.via_device', true), '') = 'on' then new.created_by := null;
  else new.created_by := auth.uid(); end if;
  return new;
end $function$;

-- 2. Appels de l'enfant par jeton : repère posé autour de la seule insertion
create or replace function public.child_toggle(p_token text, p_routine uuid, p_day date, p_done boolean, p_source text default 'child'::text)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
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
    perform set_config('sf.via_device', 'on', true);
    insert into public.completions(family_id, child_id, routine_id, day, source)
    values (d.family_id, d.child_id, p_routine, p_day, case when p_source in ('child','timer') then p_source else 'child' end)
    on conflict (routine_id, day) do nothing;
    perform set_config('sf.via_device', '', true);
  else
    if exists (select 1 from public.completions where routine_id = p_routine and day = p_day and validated_at is not null) then
      raise exception 'SF:validated_by_parent';
    end if;
    delete from public.completions where routine_id = p_routine and day = p_day and child_id = d.child_id and validated_at is null;
  end if;
  return json_build_object('ok', true);
end $function$;

create or replace function public.child_redeem(p_token text, p_reward uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare d record; w public.rewards; price int;
begin
  select * into d from private.device_child(p_token);
  select * into w from public.rewards where id = p_reward and family_id = d.family_id and active
    and (child_id is null or child_id = d.child_id);
  if not found then raise exception 'SF:reward_not_found'; end if;
  price := private.reward_cost(w, d.child_id);
  if coalesce(private.balance(d.child_id), 0) < price then raise exception 'SF:not_enough_stars'; end if;
  perform set_config('sf.via_device', 'on', true);
  insert into public.redemptions(family_id, child_id, reward_id, title, emoji, cost)
  values (d.family_id, d.child_id, w.id, w.title, w.emoji, price);
  perform set_config('sf.via_device', '', true);
  return json_build_object('ok', true);
end $function$;

do $t$
declare
  u_par uuid := gen_random_uuid(); u_help uuid := gen_random_uuid(); u_par2 uuid := gen_random_uuid();
  fid uuid; fid2 uuid; c1 uuid; c2 uuid; rA uuid; rB uuid; rC uuid; rD uuid; rE uuid; rF uuid; rO uuid; w uuid;
  tok text; tok2 text; code text; td date; res text := ''; v uuid; v2 uuid; vb boolean;
begin
  -- Aides : agir en tant qu'un utilisateur (revendications de la requête, rôle authenticated : RLS appliquée)
  create or replace function pg_temp.as_user(u uuid) returns void language plpgsql as $f$
  begin
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', case when u is null then '' else json_build_object('sub', u, 'role', 'authenticated')::text end, true);
    perform set_config('role', case when u is null then 'anon' else 'authenticated' end, true);
  end $f$;
  create or replace function pg_temp.cb(r uuid, d date) returns uuid language plpgsql as $f$
  declare old text := current_setting('role'); x uuid;
  begin perform set_config('role', 'postgres', true); select c.created_by into x from public.completions c where c.routine_id = r and c.day = d;
    perform set_config('role', old, true); return x; end $f$;
  create or replace function pg_temp.vb(r uuid, d date) returns uuid language plpgsql as $f$
  declare old text := current_setting('role'); x uuid;
  begin perform set_config('role', 'postgres', true); select c.validated_by into x from public.completions c where c.routine_id = r and c.day = d;
    perform set_config('role', old, true); return x; end $f$;
  create or replace function pg_temp.pending(r uuid, d date) returns boolean language plpgsql as $f$
  declare old text := current_setting('role'); x boolean;
  begin perform set_config('role', 'postgres', true); select c.validated_at is null into x from public.completions c where c.routine_id = r and c.day = d;
    perform set_config('role', old, true); return x; end $f$;
  create or replace function pg_temp.rb(ch uuid) returns uuid language plpgsql as $f$
  declare old text := current_setting('role'); x uuid;
  begin perform set_config('role', 'postgres', true); select z.created_by into x from public.redemptions z where z.child_id = ch order by z.created_at desc, z.ctid desc limit 1;
    perform set_config('role', old, true); return x; end $f$;
  create or replace function pg_temp.who(x uuid, par uuid) returns text language sql as $f$
    select case when x is null then 'vide' when x = par then 'parent' else 'autre' end $f$;

  -- Données fictives
  insert into auth.users(id, email) values (u_par, 'parent.test@example.invalid'), (u_help, 'proche.test@example.invalid'), (u_par2, 'parent2.test@example.invalid');
  insert into public.families(name) values ('Famille test v31.1') returning id into fid;
  insert into public.families(name) values ('Famille test v31.1 bis') returning id into fid2;
  insert into public.family_members(family_id, user_id, role) values (fid, u_par, 'parent'), (fid, u_help, 'helper'), (fid2, u_par2, 'parent');
  insert into public.children(family_id, name) values (fid, 'Enfant 1') returning id into c1;
  insert into public.children(family_id, name) values (fid2, 'Enfant 2') returning id into c2;
  insert into public.routines(family_id, child_id, title, stars) values (fid, c1, 'Routine A', 5) returning id into rA;
  insert into public.routines(family_id, child_id, title, stars) values (fid, c1, 'Routine B', 1) returning id into rB;
  insert into public.routines(family_id, child_id, title, stars) values (fid, c1, 'Routine C', 1) returning id into rC;
  insert into public.routines(family_id, child_id, title, stars) values (fid, c1, 'Routine D', 1) returning id into rD;
  insert into public.routines(family_id, child_id, title, stars) values (fid, c1, 'Routine E', 1) returning id into rE;
  insert into public.routines(family_id, child_id, title, stars) values (fid, c1, 'Routine F', 1) returning id into rF;
  insert into public.routines(family_id, child_id, title, stars) values (fid2, c2, 'Routine autre famille', 1) returning id into rO;
  insert into public.rewards(family_id, title, cost) values (fid, 'Récompense test', 1) returning id into w;
  td := private.family_today(fid);

  -- Mode enfant ici : le Parent connecté crée le code et appaire son propre téléphone (comme A.childHere)
  perform pg_temp.as_user(u_par);
  code := public.create_child_code(c1);
  tok := (public.child_pair(code, 'Téléphone de Papa') ->> 'token');
  -- solde : une coche du Parent, validée (5 étoiles), auteur forcé à un autre membre (ignoré)
  insert into public.completions(family_id, child_id, routine_id, day, source, created_by) values (fid, c1, rA, td, 'parent', u_help);
  v := pg_temp.cb(rA, td); v2 := pg_temp.vb(rA, td);
  res := res || ' 5.parent_coche=' || pg_temp.who(v, u_par) || '/' || case when v2 = u_par then 'validee_parent' else coalesce(v2::text, 'non') end;

  -- 1. coche de l'enfant en Mode enfant ici (session du Parent ouverte)
  perform public.child_toggle(tok, rB, td, true, 'child');
  v := pg_temp.cb(rB, td); vb := pg_temp.pending(rB, td);
  res := res || ' 1.ici_coche=' || pg_temp.who(v, u_par) || '/' || case when vb then 'non_validee' else 'validee' end;
  perform public.child_toggle(tok, rC, td, true, 'timer');
  v := pg_temp.cb(rC, td);
  res := res || ' 1b.ici_chrono=' || pg_temp.who(v, u_par);
  -- 2. échange en Mode enfant ici
  perform public.child_redeem(tok, w);
  v := pg_temp.rb(c1);
  res := res || ' 2.ici_echange=' || pg_temp.who(v, u_par);
  -- 8. repère non conservé après l'appel : écritures directes du Parent dans la même transaction
  insert into public.completions(family_id, child_id, routine_id, day, source) values (fid, c1, rF, td, 'child');
  v := pg_temp.cb(rF, td);
  insert into public.redemptions(family_id, child_id, reward_id, title, cost) values (fid, c1, w, 'x', 0) returning created_by into v2;
  res := res || ' 8.apres_rpc=' || pg_temp.who(v, u_par) || '/' || pg_temp.who(v2, u_par);
  delete from public.completions where routine_id = rF and day = td;

  -- 3. Proche connecté, téléphone ouvert en Mode enfant ici (jeton de l'enfant)
  perform pg_temp.as_user(u_help);
  perform public.child_toggle(tok, rD, td, true, 'child');
  v := pg_temp.cb(rD, td);
  perform public.child_redeem(tok, w);
  v2 := pg_temp.rb(c1);
  res := res || ' 3.proche_ici=' || pg_temp.who(v, u_help) || '/' || pg_temp.who(v2, u_help);

  -- 4. appareil de l'enfant sans session (anon) : inchangé
  perform pg_temp.as_user(null);
  perform public.child_toggle(tok, rE, td, true, 'child');
  v := pg_temp.cb(rE, td);
  perform public.child_redeem(tok, w);
  v2 := pg_temp.rb(c1);
  perform pg_temp.as_user(u_par);
  res := res || ' 4.sans_session=' || pg_temp.who(v, u_par) || '/' || pg_temp.who(v2, u_par);

  -- 6. Parent qui force un auteur (T05-16) : refusé, auteur = lui
  perform public.child_toggle(tok, rE, td, false, 'child');
  insert into public.completions(family_id, child_id, routine_id, day, source, created_by) values (fid, c1, rE, td, 'parent', u_help);
  v := pg_temp.cb(rE, td);
  res := res || ' 6.forge_coche=' || pg_temp.who(v, u_par);
  delete from public.completions where routine_id = rE and day = td;
  insert into public.completions(family_id, child_id, routine_id, day, source, created_by) values (fid, c1, rE, td, 'child', null);
  v := pg_temp.cb(rE, td);
  res := res || ' 6b.forge_source_enfant=' || pg_temp.who(v, u_par);
  -- 7. échange direct avec auteur forcé (vide ou autre membre)
  insert into public.redemptions(family_id, child_id, reward_id, title, cost, created_by) values (fid, c1, w, 'x', 0, null) returning created_by into v;
  insert into public.redemptions(family_id, child_id, reward_id, title, cost, created_by) values (fid, c1, w, 'x', 0, u_help) returning created_by into v2;
  res := res || ' 7.forge_echange=' || case when pg_temp.who(v, u_par) = 'parent' and pg_temp.who(v2, u_par) = 'parent' then 'parent' else pg_temp.who(v, u_par) || ',' || pg_temp.who(v2, u_par) end;
  -- 9. modifier l'auteur d'une coche de l'enfant : refusé (protect_completion garde l'auteur)
  update public.completions set created_by = u_par where routine_id = rB and day = td;
  v := pg_temp.cb(rB, td);
  res := res || ' 9.modif_auteur=' || pg_temp.who(v, u_par);
  -- 10. jeton d'un enfant, routine d'une autre famille : refus inchangé
  begin perform public.child_toggle(tok, rO, td, true, 'child'); res := res || ' 10.autre_famille=accepte';
  exception when others then res := res || ' 10.autre_famille=' || sqlerrm; end;

  perform set_config('role', 'postgres', true);
  -- 11. droits d'exécution inchangés
  res := res || ' 11.droits=anon:' || has_function_privilege('anon', 'public.child_toggle(text,uuid,date,boolean,text)', 'execute')
    || '/connecte:' || has_function_privilege('authenticated', 'public.child_redeem(text,uuid)', 'execute')
    || ' 12.repere_fin=' || coalesce(nullif(current_setting('sf.via_device', true), ''), 'vide');
  raise exception 'RESULT:%', res;
end $t$;
rollback;
