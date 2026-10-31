-- Test de la migration v30_report_sheet : à coller dans l'éditeur SQL AVANT d'appliquer la migration (ou à lancer par le connecteur).
-- Tout se passe dans une transaction annulée : la fonction est créée dedans, famille, enfants et utilisateurs sont fictifs, rien n'est conservé.
-- Le fichier contient la migration puis les cas ; à régénérer si la migration change.
-- Résultat attendu (une seule ligne, message d'erreur « RESULT: … »), avec une semaine précédente commençant un lundi :
--  1.statuts=reported,reported,stopped,stopped,stopped,stopped,not_due,not_due  1b.coches=2/étoiles=4/validées_par_parent=2
--  2.rejeu=already_done,already_done  3.attente=validated  3b=true/true/2  4.pause=reported  5.vide=[]/coches=4
--  6.courante=reported  6b.trop_ancienne=SF:scan_week  6c.future=SF:scan_week  6d.pas_un_premier_jour=SF:scan_week  6e.nulle=SF:scan_week
--  7.a_venir=SF:scan_day  7b.hors_semaine=SF:scan_day  7c.mal_ecrit=SF:scan_day  7d.absent=SF:scan_day
--  8.trop=SF:scan_too_many  8b.limite=499_virgules  9.gratuit=SF:premium_report  9b.premium=already_done
--  10.proche=SF:access_denied  10b.inconnu=SF:access_denied  10c.autre_famille=SF:access_denied  10d.enfant_inexistant=SF:access_denied  10e.sans_session=SF:access_denied
--  11.dimanche_precedent=reported  11b.lundi_refuse=SF:scan_week  12.droits=anon:false/connecte:true
begin;
-- v30 (EP-13 V1, ADR-30) : report d'une semaine de coches par une fonction serveur unique (R04-11, F04-09).
-- À tester dans une transaction annulée (supabase/tests/v30_report_sheet_test.sql) avant d'appliquer. Sans drop ni delete.
--
-- public.report_sheet(p_child, p_week_start, p_items) : p_items = tableau JSON d'éléments {"routine": uuid, "day": "AAAA-MM-JJ"}.
-- Contrôles bloquants (rien n'est écrit si l'un échoue) :
--   SF:access_denied    pas Parent de la famille de l'enfant (Proche, téléphone de l'enfant, autre famille)
--   SF:premium_report   famille gratuite
--   SF:scan_week        p_week_start n'est pas le premier jour de la semaine en cours ou de la précédente (fuseau et premier jour de la famille)
--   SF:scan_day         jour absent, mal écrit, hors de la semaine choisie, ou à venir
--   SF:scan_too_many    plus de 500 éléments
-- La limite « 7 jours après la fin de la semaine choisie » (R04-11 CA6) découle du contrôle de semaine.
-- Statut renvoyé pour chaque élément (même ordre que p_items) :
--   reported      coche créée, validée au nom du Parent, étoiles fixées par le serveur (R05-01, R05-02)
--   validated     coche de l'enfant en attente, validée
--   already_done  déjà validée (ou créée entre-temps) : inchangée
--   not_due       routine pas due ce jour-là d'après private.routine_rules (vacances et routines en pause comprises) : non reportée
--   stopped       routine absente, d'un autre enfant, exceptionnelle ou arrêtée (active = false) : non reportée (DEC-08)
-- Les pauses de l'enfant ne sont pas lues (DEC-09, DT10-12). Ne supprime jamais rien : un rond vide ne retire aucune coche.
-- Jardin et série : recalculés par invalidate_stats pour un jour passé, comme pour une coche à la main.

create or replace function public.report_sheet(p_child uuid, p_week_start date, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  fid uuid; ws int; today date; cur date;
  items jsonb := coalesce(p_items, '[]'::jsonb);
  e jsonb; rtxt text; rid uuid; d date; st text; rc int;
  r record; cm record;
  res jsonb := '[]'::jsonb;
begin
  select c.family_id into fid from public.children c where c.id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:access_denied'; end if;
  if not private.is_premium(fid) then raise exception 'SF:premium_report'; end if;

  select f.week_start into ws from public.families f where f.id = fid;
  today := private.family_today(fid);
  cur := today - (((extract(isodow from today)::int - ws) + 7) % 7);
  if p_week_start is null or p_week_start not in (cur, cur - 7) then raise exception 'SF:scan_week'; end if;

  if jsonb_typeof(items) <> 'array' then items := '[]'::jsonb; end if;
  if jsonb_array_length(items) > 500 then raise exception 'SF:scan_too_many'; end if;

  for e in select x.value from jsonb_array_elements(items) as x loop
    begin d := (e->>'day')::date; exception when others then d := null; end;
    if d is null or d < p_week_start or d > p_week_start + 6 or d > today then raise exception 'SF:scan_day'; end if;

    rtxt := e->>'routine'; rid := null;
    if rtxt ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then rid := rtxt::uuid; end if;

    select ro.child_id, ro.kind, ro.active into r from public.routines ro where ro.id = rid;
    if not found or r.child_id <> p_child or r.kind <> 'regular' or not r.active then
      st := 'stopped';
    elsif not exists (select 1 from private.routine_rules(p_child, d) rr where rr.routine_id = rid) then
      st := 'not_due';
    else
      select co.id, co.validated_at into cm from public.completions co where co.routine_id = rid and co.day = d for update;
      if not found then
        insert into public.completions(family_id, child_id, routine_id, day, source)
        values (fid, p_child, rid, d, 'parent')
        on conflict (routine_id, day) do nothing;
        get diagnostics rc = row_count;
        st := case when rc = 1 then 'reported' else 'already_done' end;
      elsif cm.validated_at is null then
        update public.completions set validated_at = now() where id = cm.id;
        st := 'validated';
      else
        st := 'already_done';
      end if;
    end if;
    res := res || jsonb_build_object('routine', rtxt, 'day', d, 'status', st);
  end loop;
  return res;
end $$;

revoke execute on function public.report_sheet(uuid, date, jsonb) from public, anon;
grant execute on function public.report_sheet(uuid, date, jsonb) to authenticated;

do $t$
declare
  u_par uuid := gen_random_uuid(); u_help uuid := gen_random_uuid(); u_str uuid := gen_random_uuid(); u_par2 uuid := gen_random_uuid();
  fid uuid; fid2 uuid; c1 uuid; c2 uuid;
  rA uuid; rStop uuid; rOne uuid; rLun uuid; rV uuid; rOther uuid; per uuid;
  td date; w0 date; cur date; cur7 date; res text := '';
  big jsonb;
begin
  -- Aides : exécution en tant que l'utilisateur donné (auth.uid() lit les revendications de la requête)
  create or replace function pg_temp.it(r uuid, d date) returns jsonb language sql as $f$ select jsonb_build_object('routine', r, 'day', d) $f$;
  create or replace function pg_temp.run(u uuid, c uuid, wk date, items jsonb) returns text language plpgsql as $f$
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    return coalesce((select string_agg(x->>'status', ',') from jsonb_array_elements(public.report_sheet(c, wk, items)) as x), '');
  exception when others then return sqlerrm;
  end $f$;

  -- Données fictives (rien n'est conservé)
  insert into auth.users(id, email) values (u_par, 'parent.test@example.invalid'), (u_help, 'proche.test@example.invalid'), (u_str, 'autre.test@example.invalid'), (u_par2, 'parent2.test@example.invalid');
  insert into public.families(name) values ('Famille test v30') returning id into fid;
  insert into public.families(name) values ('Famille test v30 bis') returning id into fid2;
  insert into public.family_members(family_id, user_id, role) values (fid, u_par, 'parent'), (fid, u_help, 'helper'), (fid2, u_par2, 'parent');
  insert into public.children(family_id, name) values (fid, 'Enfant 1') returning id into c1;
  insert into public.children(family_id, name) values (fid2, 'Enfant 2') returning id into c2;
  td := private.family_today(fid);
  w0 := date_trunc('week', td)::date - 7;          -- lundi de la semaine précédente (premier jour de la semaine : lundi par défaut)
  cur := w0 + 7;

  insert into public.routines(family_id, child_id, title, stars, created_at) values (fid, c1, 'Routine A', 2, now() - interval '60 days') returning id into rA;
  insert into public.routines(family_id, child_id, title, stars, created_at) values (fid, c1, 'Routine V', 1, now() - interval '60 days') returning id into rV;
  insert into public.routines(family_id, child_id, title, days, created_at) values (fid, c1, 'Routine lundi', array[1]::smallint[], now() - interval '60 days') returning id into rLun;
  insert into public.routines(family_id, child_id, title, created_at) values (fid, c1, 'Routine arrêtée', now() - interval '60 days') returning id into rStop;
  update public.routines set active = false where id = rStop;
  insert into public.routines(family_id, child_id, title, kind, start_day, end_day, created_at) values (fid, c1, 'Exceptionnelle', 'oneoff', w0, w0 + 20, now() - interval '60 days') returning id into rOne;
  insert into public.routines(family_id, child_id, title, created_at) values (fid2, c2, 'Routine autre famille', now() - interval '60 days') returning id into rOther;
  -- Vacances le 5e jour de la semaine précédente : « Routine V » en pause ce jour-là (CA4)
  insert into public.holiday_periods(family_id, child_id, name, start_day, end_day) values (fid, c1, 'Vacances test', w0 + 4, w0 + 4) returning id into per;
  insert into public.holiday_overrides(period_id, routine_id, child_id, family_id, status) values (per, rV, c1, fid, 'off');

  -- 1. Parent, Premium : un statut par élément, dans l'ordre
  res := res || ' 1.statuts=' || pg_temp.run(u_par, c1, w0, jsonb_build_array(
    pg_temp.it(rA, w0), pg_temp.it(rA, w0 + 1), pg_temp.it(rStop, w0), pg_temp.it(rOne, w0), pg_temp.it(rOther, w0),
    jsonb_build_object('routine', 'pas-un-uuid', 'day', w0), pg_temp.it(rV, w0 + 4), pg_temp.it(rLun, w0 + 1)));
  res := res || ' 1b.coches=' || (select count(*) from public.completions where child_id = c1)
    || '/étoiles=' || (select coalesce(sum(stars), 0) from public.completions where child_id = c1)
    || '/validées_par_parent=' || (select count(*) from public.completions where child_id = c1 and validated_at is not null and validated_by = u_par and source = 'parent');
  -- 2. Rejouer : déjà faites, rien ne change
  res := res || ' 2.rejeu=' || pg_temp.run(u_par, c1, w0, jsonb_build_array(pg_temp.it(rA, w0), pg_temp.it(rA, w0 + 1)));
  -- 3. Coche de l'enfant en attente : validée au nom du Parent, étoiles inchangées
  insert into public.completions(family_id, child_id, routine_id, day, source) values (fid, c1, rA, w0 + 2, 'child');
  res := res || ' 3.attente=' || pg_temp.run(u_par, c1, w0, jsonb_build_array(pg_temp.it(rA, w0 + 2)));
  res := res || ' 3b=' || (select (validated_at is not null)::text || '/' || (validated_by = u_par)::text || '/' || stars from public.completions where routine_id = rA and day = w0 + 2);
  -- 4. Jour de pause de l'enfant : reporté quand même (DEC-09, CA7)
  insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (fid, c1, w0 + 3, w0 + 3, 'sick');
  res := res || ' 4.pause=' || pg_temp.run(u_par, c1, w0, jsonb_build_array(pg_temp.it(rA, w0 + 3)));
  -- 5. Aucun élément : rien n'est retiré
  res := res || ' 5.vide=[' || pg_temp.run(u_par, c1, w0, '[]'::jsonb) || ']/coches=' || (select count(*) from public.completions where child_id = c1);
  -- 6. Semaine en cours acceptée ; semaines refusées
  res := res || ' 6.courante=' || pg_temp.run(u_par, c1, cur, jsonb_build_array(pg_temp.it(rA, cur)));
  res := res || ' 6b.trop_ancienne=' || pg_temp.run(u_par, c1, w0 - 7, jsonb_build_array(pg_temp.it(rA, w0 - 7)));
  res := res || ' 6c.future=' || pg_temp.run(u_par, c1, cur + 7, '[]'::jsonb);
  res := res || ' 6d.pas_un_premier_jour=' || pg_temp.run(u_par, c1, w0 + 1, '[]'::jsonb);
  res := res || ' 6e.nulle=' || pg_temp.run(u_par, c1, null, '[]'::jsonb);
  -- 7. Jours refusés
  res := res || ' 7.a_venir=' || pg_temp.run(u_par, c1, cur, jsonb_build_array(pg_temp.it(rA, td + 1)));
  res := res || ' 7b.hors_semaine=' || pg_temp.run(u_par, c1, w0, jsonb_build_array(pg_temp.it(rA, w0 + 7)));
  res := res || ' 7c.mal_ecrit=' || pg_temp.run(u_par, c1, w0, jsonb_build_array(jsonb_build_object('routine', rA, 'day', 'abc')));
  res := res || ' 7d.absent=' || pg_temp.run(u_par, c1, w0, jsonb_build_array(jsonb_build_object('routine', rA)));
  -- 8. Plus de 500 éléments
  select jsonb_agg(pg_temp.it(rA, w0)) into big from generate_series(1, 501);
  res := res || ' 8.trop=' || pg_temp.run(u_par, c1, w0, big);
  select jsonb_agg(pg_temp.it(rA, w0)) into big from generate_series(1, 500);
  res := res || ' 8b.limite=' || (length(pg_temp.run(u_par, c1, w0, big)) - length(replace(pg_temp.run(u_par, c1, w0, big), ',', ''))) || '_virgules';
  -- 9. Famille gratuite
  update public.families set plan = 'free' where id = fid;
  res := res || ' 9.gratuit=' || pg_temp.run(u_par, c1, w0, jsonb_build_array(pg_temp.it(rA, w0 + 3)));
  update public.families set plan = 'premium' where id = fid;
  res := res || ' 9b.premium=' || pg_temp.run(u_par, c1, w0, jsonb_build_array(pg_temp.it(rA, w0 + 3)));
  update public.families set plan = 'founder' where id = fid;
  -- 10. Droits
  res := res || ' 10.proche=' || pg_temp.run(u_help, c1, w0, '[]'::jsonb);
  res := res || ' 10b.inconnu=' || pg_temp.run(u_str, c1, w0, '[]'::jsonb);
  res := res || ' 10c.autre_famille=' || pg_temp.run(u_par, c2, w0, '[]'::jsonb);
  res := res || ' 10d.enfant_inexistant=' || pg_temp.run(u_par, gen_random_uuid(), w0, '[]'::jsonb);
  res := res || ' 10e.sans_session=' || pg_temp.run(null, c1, w0, '[]'::jsonb);
  -- 11. Premier jour de la semaine = dimanche (réglage de la famille)
  update public.families set week_start = 7 where id = fid;
  cur7 := td - extract(dow from td)::int;
  res := res || ' 11.dimanche_precedent=' || pg_temp.run(u_par, c1, cur7 - 7, jsonb_build_array(pg_temp.it(rA, cur7 - 7)));
  res := res || ' 11b.lundi_refuse=' || pg_temp.run(u_par, c1, w0, '[]'::jsonb);
  update public.families set week_start = 1 where id = fid;
  -- 12. Droits d'exécution : ni anon ni public ; connecté oui
  res := res || ' 12.droits=anon:' || has_function_privilege('anon', 'public.report_sheet(uuid,date,jsonb)', 'execute')
    || '/connecte:' || has_function_privilege('authenticated', 'public.report_sheet(uuid,date,jsonb)', 'execute');
  raise exception 'RESULT:%', res;
end $t$;
rollback;
