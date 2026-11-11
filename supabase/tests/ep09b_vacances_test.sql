-- Test de la migration ep09b (thème B d'EP-09) : à lancer AVANT d'appliquer la migration, dans l'éditeur SQL de Supabase (elle contient des drop trigger : confirmation demandée).
-- Tout se passe dans une transaction annulée : familles, enfants, utilisateurs fictifs, rien n'est conservé. Elle suppose la migration A1 appliquée (ou lancée avant dans la même transaction).
-- Fichier composé : cat migrations/20261112090000_ep09b_vacances_pauses_premium.sql tests/ep09b_cases.sql
-- Résultat attendu : une seule ligne d'erreur « RESULT: … » contenant, dans l'ordre :
--  H1.deja_finie=SF:holiday_past H2.commence_aujourdhui=ok H3.grace_suppression=ok H4.grace_debut=ok H4b.grace_suppression=ok H5.verrou_suppression=SF:holiday_started
--  H5b.verrou_debut=SF:holiday_started H5c.verrou_fin_avant_hier=SF:holiday_started H5d.verrou_creation=ok H5e.creation_figee=true H5f.verrou_suppression_apres=SF:holiday_started
--  H5g.verrou_prolonger=ok H5h.verrou_nom=ok H6.arreter=ok H6b.finie_prolonger=SF:holiday_started H6c.finie_nom=ok H7.creation_future=true H8.reactivation_gratuit=SF:premium_holidays
--  H8b.nom_gratuit=ok H8c.reactivation_premium=ok P1.repos_recu_sick=ok P1b.converti=rest P2.chevauche=SF:pause_overlap P2b.contigue=ok P2c.modif_chevauche=SF:pause_overlap
--  P2d.motif_seul=ok P2e.motif_sick_modif=ok/rest P3.quinzaine_close=SF:pause_closed P3b.a_cheval=SF:pause_closed P3c.apres_quinzaine=ok P4.creation_modifiee=ok
--  P4b.suppression_apres=SF:pause_started P4c.creation_figee=true M1.proche_vers_parent=SF:premium_adults M2.parent_vers_proche=SF:premium_helpers M3.meme_droit=ok
--  M4.vers_exceptionnelle=SF:premium_oneoff M4b.titre_seul=ok M4c.kind_inchange=ok M5.premium_proche_vers_parent=ok M5b.premium_vers_exceptionnelle=ok
-- Lancé jusqu'ici sur une réplique locale du schéma (PostgreSQL 16), seul puis après les migrations A1 et A2 (mêmes résultats), pas sur la base de production.
begin;
-- EP-09 thème B : vacances, pauses, garde-fous Premium à la modification (ADR-50, ADR-51).
-- Contient « DELETE » dans le corps de fonctions et des drop trigger (uniquement de ses propres déclencheurs) : à lancer dans l'ÉDITEUR SQL de Supabase, puis à enregistrer
-- dans supabase_migrations.schema_migrations (version 20261112090000, nom ep09b_vacances_pauses_premium).
-- Compatible avec l'ancienne version de l'application (elle n'écrit que des pauses, périodes et droits permis par ces règles,
-- sauf le motif « sick », converti en « rest » par le déclencheur).
-- À tester dans une transaction annulée (supabase/tests/ep09b_vacances_test.sql).
--
-- DT10-02  24 h de grâce après la création d'une période (modifiable et supprimable, comme une pause)
-- DT10-03  « commencée » = premier jour passé (heure de la famille)
-- DT10-04  période commencée : premier jour et fin passée figés, fin jamais avant hier ; période déjà finie non créable
-- DT10-05  created_at figé (périodes et pauses) ; une date de création future est ramenée à maintenant
-- DT10-06  réactivation d'une période refusée sans Premium
-- DT10-07  pause sur une quinzaine close (fleur éclose) refusée
-- DT10-08  pauses d'un même enfant qui se chevauchent refusées
-- DT10-13  motif « Repos » (clé rest) à la place de « Maladie » (sick)
-- DT02-03, DT12-02  premium_guard aussi à la mise à jour (droit d'un membre, routine passée en exceptionnelle)
-- DT10-09 (coche d'adulte hors période) : déjà traité par private.check_completion (thème A).
-- Constat (DT proposée) : pauses.reason n'a ni contrainte ni valeur par défaut en base (texte libre, ancien texte affiché tel quel,
-- M10b) : rien à contraindre ; le défaut « rest » est écrit par l'application.

-- 1. Périodes de vacances
create or replace function private.holiday_period_check() returns trigger
language plpgsql security definer set search_path = '' as $$
declare today date; locked boolean;
begin
  if tg_op = 'DELETE' then
    -- Une période commencée (premier jour passé) et créée il y a plus de 24 h ne se supprime pas : elle s'arrête.
    -- Sauf suppression de l'enfant ou de la famille (cascade).
    if old.start_day < private.family_today(old.family_id) and old.created_at < now() - interval '24 hours'
       and exists (select 1 from public.children where id = old.child_id) then
      raise exception 'SF:holiday_started';
    end if;
    return old;
  end if;
  today := private.family_today(new.family_id);
  if tg_op = 'INSERT' then
    if not private.is_premium(new.family_id) then raise exception 'SF:premium_holidays'; end if;
    if new.end_day < today then raise exception 'SF:holiday_past'; end if;
    if new.created_at is null or new.created_at > now() then new.created_at := now(); end if;
  else
    new.created_at := old.created_at;
    -- Réactivation d'une période désactivée : Premium seulement
    if new.active and not old.active and not private.is_premium(new.family_id) then raise exception 'SF:premium_holidays'; end if;
    locked := old.start_day < today and old.created_at < now() - interval '24 hours';
    if locked and (new.start_day <> old.start_day or new.child_id <> old.child_id or new.family_id <> old.family_id
                   or (new.end_day <> old.end_day and (old.end_day < today or new.end_day < today - 1))) then
      raise exception 'SF:holiday_started';
    end if;
  end if;
  if new.active and exists (select 1 from public.holiday_periods p
      where p.child_id = new.child_id and p.active and p.id <> new.id
        and p.start_day <= new.end_day and new.start_day <= p.end_day) then
    raise exception 'SF:holiday_overlap';
  end if;
  return new;
end $$;

-- 2. Pauses : insertion contrôlée, date de création figée, motif « Repos »
create or replace function private.pause_check() returns trigger
language plpgsql security definer set search_path = '' as $$
declare today date; locked boolean;
begin
  if tg_op = 'INSERT' then
    -- ancien motif converti (copie locale d'avant la mise à jour)
    if new.reason = 'sick' then new.reason := 'rest'; end if;
    if new.created_at is null or new.created_at > now() then new.created_at := now(); end if;
  else
    today := private.family_today(old.family_id);
    locked := old.start_day < today and old.created_at < now() - interval '24 hours';
    if tg_op = 'DELETE' then
      if locked and exists (select 1 from public.children where id = old.child_id) then
        raise exception 'SF:pause_started';
      end if;
      return old;
    end if;
    new.created_at := old.created_at;
    if new.reason = 'sick' then new.reason := 'rest'; end if;
    if locked and (new.start_day <> old.start_day or new.child_id <> old.child_id or new.family_id <> old.family_id
                   or new.end_day < least(old.end_day, today - 1)) then
      raise exception 'SF:pause_started';
    end if;
    -- dates inchangées : rien d'autre à contrôler (pauses existantes gardées telles quelles)
    if new.start_day = old.start_day and new.end_day = old.end_day and new.child_id = old.child_id then return new; end if;
  end if;
  if exists (select 1 from public.pauses p where p.child_id = new.child_id and p.id <> new.id
             and p.start_day <= new.end_day and new.start_day <= p.end_day) then
    raise exception 'SF:pause_overlap';
  end if;
  if exists (select 1 from public.flowers f where f.child_id = new.child_id
             and f.period_start <= new.end_day and f.period_end >= new.start_day) then
    raise exception 'SF:pause_closed';
  end if;
  return new;
end $$;

drop trigger if exists pauses_check on public.pauses;
create trigger pauses_check before insert or update or delete on public.pauses
  for each row execute function private.pause_check();

update public.pauses set reason = 'rest' where reason = 'sick';

-- 3. Premium à la modification : droit d'un membre, type d'une routine
create or replace function private.premium_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if private.is_premium(new.family_id) then return new; end if;
  if tg_op = 'UPDATE' then   -- seuls les changements du droit ou du type sont contrôlés
    if tg_table_name = 'family_members' then
      if new.role is not distinct from old.role then return new; end if;
    elsif tg_table_name = 'routines' then
      if new.kind is not distinct from old.kind then return new; end if;
    end if;
  end if;
  case tg_table_name
    when 'children' then
      if exists (select 1 from public.children where family_id = new.family_id) then
        raise exception 'SF:premium_children';
      end if;
    when 'family_members' then
      if new.role = 'helper' then raise exception 'SF:premium_helpers'; end if;
      if (select count(*) from public.family_members where family_id = new.family_id and role = 'parent') >= 2 then
        raise exception 'SF:premium_adults';
      end if;
    when 'routines' then
      if new.kind = 'oneoff' then raise exception 'SF:premium_oneoff'; end if;
    when 'oneoff_templates' then
      raise exception 'SF:premium_oneoff';
    when 'penalties', 'penalty_events' then
      raise exception 'SF:premium_malus';
    else null;
  end case;
  return new;
end $$;

drop trigger if exists family_members_premium_upd on public.family_members;
create trigger family_members_premium_upd before update of role on public.family_members
  for each row execute function private.premium_guard();
drop trigger if exists routines_premium_upd on public.routines;
create trigger routines_premium_upd before update of kind on public.routines
  for each row execute function private.premium_guard();

do $t$
declare
  u_par uuid := gen_random_uuid(); u_par2 uuid := gen_random_uuid(); u_help uuid := gen_random_uuid();
  u_f1 uuid := gen_random_uuid(); u_f2 uuid := gen_random_uuid(); u_fh uuid := gen_random_uuid();
  fid uuid; fidF uuid; c1 uuid; cF uuid; hp uuid; hp2 uuid; hp3 uuid; pz uuid; pz2 uuid; rF uuid;
  td date; res text := ''; v text;
begin
  create or replace function pg_temp.as_user(u uuid) returns void language plpgsql as $f$
  begin
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', case when u is null then '' else json_build_object('sub', u, 'role', 'authenticated')::text end, true);
    perform set_config('role', case when u is null then 'anon' else 'authenticated' end, true);
  end $f$;
  create or replace function pg_temp.try(q text) returns text language plpgsql as $f$
  begin execute q; return 'ok'; exception when others then return sqlerrm; end $f$;
  create or replace function pg_temp.sup(q text) returns text language plpgsql as $f$
  declare old text := current_setting('role'); x text;
  begin perform set_config('role', 'postgres', true); execute q into x; perform set_config('role', old, true); return x; end $f$;
  create or replace function pg_temp.supdo(q text) returns void language plpgsql as $f$
  declare old text := current_setting('role');
  begin perform set_config('role', 'postgres', true); execute q; perform set_config('role', old, true); end $f$;
  create or replace function pg_temp.tq(q text) returns text language plpgsql as $f$ declare x text; begin execute q into x; return x; exception when others then return sqlerrm; end $f$;
  create or replace function pg_temp.hdr(x text) returns void language sql as $f$ select set_config('request.headers', x, true) $f$;
  grant execute on function pg_temp.try(text), pg_temp.as_user(uuid), pg_temp.sup(text), pg_temp.supdo(text) to public;   -- droits par défaut retirés par la migration A2

  -- Données fictives (aucun vrai e-mail ni prénom)
  insert into auth.users(id, email) values (u_par, 'parent.test@example.invalid'), (u_par2, 'parent2.test@example.invalid'), (u_help, 'proche.test@example.invalid'),
    (u_f1, 'gratuit1.test@example.invalid'), (u_f2, 'gratuit2.test@example.invalid'), (u_fh, 'gratuit3.test@example.invalid');
  insert into public.families(name, plan) values ('Famille test EP-09B', 'premium') returning id into fid;
  insert into public.families(name, plan) values ('Famille gratuite test EP-09B', 'premium') returning id into fidF;
  insert into public.family_members(family_id, user_id, role, display_name) values (fid, u_par, 'parent', 'Prenom Test Parent'), (fid, u_par2, 'parent', null), (fid, u_help, 'helper', null),
    (fidF, u_f1, 'parent', null), (fidF, u_f2, 'parent', null), (fidF, u_fh, 'helper', null);
  insert into public.children(family_id, name) values (fid, 'Enfant 1') returning id into c1;
  insert into public.children(family_id, name) values (fidF, 'Enfant gratuit') returning id into cF;
  update public.families set plan = 'free' where id = fidF;   -- membres et enfant posés en Premium, offre repassée en gratuit
  td := private.family_today(fid);

  -- ===================== B1. Périodes de vacances =====================
  perform pg_temp.as_user(u_par);
  res := res || ' H1.deja_finie=' || pg_temp.try(format('insert into public.holiday_periods(family_id, child_id, name, start_day, end_day) values (%L, %L, ''Finie'', %L, %L)', fid, c1, td - 5, td - 1));
  res := res || ' H2.commence_aujourdhui=' || pg_temp.try(format('insert into public.holiday_periods(family_id, child_id, name, start_day, end_day) values (%L, %L, ''Auj'', %L, %L)', fid, c1, td, td + 3));
  res := res || ' H3.grace_suppression=' || pg_temp.try(format('delete from public.holiday_periods where family_id = %L and name = ''Auj''', fid));
  -- période commencée il y a 2 jours (créée à l'instant) : 24 h de grâce, premier jour modifiable et suppression permise
  insert into public.holiday_periods(family_id, child_id, name, start_day, end_day) values (fid, c1, 'Grace', td - 3, td + 3) returning id into hp;
  res := res || ' H4.grace_debut=' || pg_temp.try(format('update public.holiday_periods set start_day = %L where id = %L', td - 4, hp));
  res := res || ' H4b.grace_suppression=' || pg_temp.try(format('delete from public.holiday_periods where id = %L', hp));
  -- période commencée et créée il y a 2 jours : verrouillée
  perform pg_temp.supdo(format('insert into public.holiday_periods(id, family_id, child_id, name, start_day, end_day, created_at) values (gen_random_uuid(), %L, %L, ''Verrou'', %L, %L, now() - interval ''2 days'')', fid, c1, td - 3, td + 3));
  hp2 := (select id from public.holiday_periods where family_id = fid and name = 'Verrou');
  res := res || ' H5.verrou_suppression=' || pg_temp.try(format('delete from public.holiday_periods where id = %L', hp2));
  res := res || ' H5b.verrou_debut=' || pg_temp.try(format('update public.holiday_periods set start_day = %L where id = %L', td - 4, hp2));
  res := res || ' H5c.verrou_fin_avant_hier=' || pg_temp.try(format('update public.holiday_periods set end_day = %L where id = %L', td - 2, hp2));
  res := res || ' H5d.verrou_creation=' || pg_temp.try(format('update public.holiday_periods set created_at = now() where id = %L', hp2));
  res := res || ' H5e.creation_figee=' || (select (created_at < now() - interval '1 day')::text from public.holiday_periods where id = hp2);
  res := res || ' H5f.verrou_suppression_apres=' || pg_temp.try(format('delete from public.holiday_periods where id = %L', hp2));
  res := res || ' H5g.verrou_prolonger=' || pg_temp.try(format('update public.holiday_periods set end_day = %L where id = %L', td + 9, hp2));
  res := res || ' H5h.verrou_nom=' || pg_temp.try(format('update public.holiday_periods set name = ''Verrou 2'' where id = %L', hp2));
  res := res || ' H6.arreter=' || pg_temp.try(format('update public.holiday_periods set end_day = %L where id = %L', td - 1, hp2));
  res := res || ' H6b.finie_prolonger=' || pg_temp.try(format('update public.holiday_periods set end_day = %L where id = %L', td + 2, hp2));
  res := res || ' H6c.finie_nom=' || pg_temp.try(format('update public.holiday_periods set name = ''Verrou 3'' where id = %L', hp2));
  insert into public.holiday_periods(family_id, child_id, name, start_day, end_day, created_at) values (fid, c1, 'Futur', td + 20, td + 25, now() + interval '10 days') returning id into hp3;
  res := res || ' H7.creation_future=' || (select (created_at <= now())::text from public.holiday_periods where id = hp3);
  -- Gratuit : réactivation refusée
  perform pg_temp.supdo(format('update public.families set plan = ''premium'' where id = %L', fidF));
  perform pg_temp.supdo(format('insert into public.holiday_periods(family_id, child_id, name, start_day, end_day, active) values (%L, %L, ''Desactivee'', %L, %L, false)', fidF, cF, td + 30, td + 35));
  perform pg_temp.supdo(format('update public.families set plan = ''free'' where id = %L', fidF));
  perform pg_temp.as_user(u_f1);
  res := res || ' H8.reactivation_gratuit=' || pg_temp.try(format('update public.holiday_periods set active = true where family_id = %L', fidF));
  res := res || ' H8b.nom_gratuit=' || pg_temp.try(format('update public.holiday_periods set name = ''Renommee'' where family_id = %L', fidF));
  perform pg_temp.supdo(format('update public.families set plan = ''premium'' where id = %L', fidF));
  res := res || ' H8c.reactivation_premium=' || pg_temp.try(format('update public.holiday_periods set active = true where family_id = %L', fidF));
  perform pg_temp.supdo(format('update public.families set plan = ''free'' where id = %L', fidF));

  -- ===================== B2. Pauses =====================
  perform pg_temp.as_user(u_par);
  res := res || ' P1.repos_recu_sick=' || pg_temp.try(format('insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (%L, %L, %L, %L, ''sick'')', fid, c1, td, td + 3));
  res := res || ' P1b.converti=' || (select reason from public.pauses where family_id = fid and start_day = td);
  res := res || ' P2.chevauche=' || pg_temp.try(format('insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (%L, %L, %L, %L, ''trip'')', fid, c1, td + 2, td + 5));
  res := res || ' P2b.contigue=' || pg_temp.try(format('insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (%L, %L, %L, %L, ''trip'')', fid, c1, td + 4, td + 6));
  res := res || ' P2c.modif_chevauche=' || pg_temp.try(format('update public.pauses set end_day = %L where family_id = %L and start_day = %L', td + 5, fid, td));
  res := res || ' P2d.motif_seul=' || pg_temp.try(format('update public.pauses set reason = ''other'' where family_id = %L and start_day = %L', fid, td));
  v := pg_temp.try(format('update public.pauses set reason = ''sick'' where family_id = %L and start_day = %L', fid, td));
  res := res || ' P2e.motif_sick_modif=' || v || '/' || (select reason from public.pauses where family_id = fid and start_day = td);
  perform pg_temp.supdo(format('insert into public.flowers(family_id, child_id, period_start, period_end) values (%L, %L, %L, %L)', fid, c1, td - 20, td - 7));
  res := res || ' P3.quinzaine_close=' || pg_temp.try(format('insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (%L, %L, %L, %L, ''rest'')', fid, c1, td - 10, td - 9));
  res := res || ' P3b.a_cheval=' || pg_temp.try(format('insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (%L, %L, %L, %L, ''rest'')', fid, c1, td - 8, td - 6));
  res := res || ' P3c.apres_quinzaine=' || pg_temp.try(format('insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (%L, %L, %L, %L, ''rest'')', fid, c1, td - 6, td - 5));
  -- création figée, pause verrouillée
  perform pg_temp.supdo(format('insert into public.pauses(id, family_id, child_id, start_day, end_day, reason, created_at) values (gen_random_uuid(), %L, %L, %L, %L, ''rest'', now() - interval ''2 days'')', fid, c1, td - 3, td - 2));
  pz := (select id from public.pauses where family_id = fid and start_day = td - 3);
  res := res || ' P4.creation_modifiee=' || pg_temp.try(format('update public.pauses set created_at = now() where id = %L', pz));
  res := res || ' P4b.suppression_apres=' || pg_temp.try(format('delete from public.pauses where id = %L', pz));
  res := res || ' P4c.creation_figee=' || (select (created_at < now() - interval '1 day')::text from public.pauses where id = pz);

  -- ===================== B3. Premium à la modification =====================
  perform pg_temp.as_user(u_f1);
  res := res || ' M1.proche_vers_parent=' || pg_temp.try(format('update public.family_members set role = ''parent'' where family_id = %L and user_id = %L', fidF, u_fh));
  res := res || ' M2.parent_vers_proche=' || pg_temp.try(format('update public.family_members set role = ''helper'' where family_id = %L and user_id = %L', fidF, u_f2));
  res := res || ' M3.meme_droit=' || pg_temp.try(format('update public.family_members set role = ''parent'' where family_id = %L and user_id = %L', fidF, u_f2));
  insert into public.routines(family_id, child_id, title, stars) values (fidF, cF, 'Routine gratuite', 1) returning id into rF;
  res := res || ' M4.vers_exceptionnelle=' || pg_temp.try(format('update public.routines set kind = ''oneoff'', start_day = %L, end_day = %L where id = %L', td, td + 2, rF));
  res := res || ' M4b.titre_seul=' || pg_temp.try(format('update public.routines set title = ''Titre modifie'' where id = %L', rF));
  res := res || ' M4c.kind_inchange=' || pg_temp.try(format('update public.routines set kind = ''regular'', stars = 2 where id = %L', rF));
  perform pg_temp.as_user(u_par);
  insert into public.routines(family_id, child_id, title, stars) values (fid, c1, 'Routine premium', 1);
  res := res || ' M5.premium_proche_vers_parent=' || pg_temp.try(format('update public.family_members set role = ''parent'' where family_id = %L and user_id = %L', fid, u_help));
  res := res || ' M5b.premium_vers_exceptionnelle=' || pg_temp.try(format('update public.routines set kind = ''oneoff'', start_day = %L, end_day = %L where id = (select id from public.routines where family_id = %L limit 1)', td, td + 2, fid));

  perform pg_temp.as_user(null);
  perform set_config('role', 'postgres', true);
  perform set_config('t.res', res, true);
  raise exception 'RESULT:%', res;
end $t$;
rollback;
