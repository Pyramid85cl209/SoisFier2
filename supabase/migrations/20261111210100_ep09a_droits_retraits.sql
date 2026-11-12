-- EP-09 thème A (2/2) : retraits et droits par défaut. CONTIENT drop ET revoke : à lancer dans l'ÉDITEUR SQL de Supabase (ADR-07), après ep09a_controles_serveur,
-- et SEULEMENT quand la nouvelle version de l'application est en ligne (elle appelle public.redeem au lieu d'insérer dans redemptions).
-- À tester dans une transaction annulée (supabase/tests/ep09a_controles_test.sql, cas 20 à 27) avant d'appliquer.
--
-- DT04-05  politique routines_delete retirée : l'arrêt (ended_at) reste la seule voie
-- DT06-02  politique redemptions_insert retirée : l'échange passe par public.redeem (ADR-43)
-- DT00-07  fonctions inutilisées private.paris_today, period_bounds, first_end retirées
-- DT00-08  politiques holiday_periods et holiday_overrides recréées pour authenticated (rôle public avant)
-- DT00-22  droits par défaut : EXECUTE retiré sur les fonctions de private, sauf ce qu'appellent les RLS et les contraintes ;
--          droits d'anon retirés sur les tables de public hors languages et tips (lecture seule) ; droits par défaut alignés.
-- Non fait ici : DT11-05 (secrets des rappels, ADR-45), à part.

-- 1. Politiques retirées
drop policy redemptions_insert on public.redemptions;
drop policy routines_delete on public.routines;

-- 2. Politiques de vacances pour authenticated (mêmes conditions qu'avant)
drop policy holiday_periods_select on public.holiday_periods;
drop policy holiday_periods_insert on public.holiday_periods;
drop policy holiday_periods_update on public.holiday_periods;
drop policy holiday_periods_delete on public.holiday_periods;
create policy holiday_periods_select on public.holiday_periods for select to authenticated using ((select private.is_member(holiday_periods.family_id)));
create policy holiday_periods_insert on public.holiday_periods for insert to authenticated with check ((select private.is_parent(holiday_periods.family_id)));
create policy holiday_periods_update on public.holiday_periods for update to authenticated using ((select private.is_parent(holiday_periods.family_id))) with check ((select private.is_parent(holiday_periods.family_id)));
create policy holiday_periods_delete on public.holiday_periods for delete to authenticated using ((select private.is_parent(holiday_periods.family_id)));

drop policy holiday_overrides_select on public.holiday_overrides;
drop policy holiday_overrides_insert on public.holiday_overrides;
drop policy holiday_overrides_update on public.holiday_overrides;
drop policy holiday_overrides_delete on public.holiday_overrides;
create policy holiday_overrides_select on public.holiday_overrides for select to authenticated using ((select private.is_member(holiday_overrides.family_id)));
create policy holiday_overrides_insert on public.holiday_overrides for insert to authenticated with check ((select private.is_parent(holiday_overrides.family_id)));
create policy holiday_overrides_update on public.holiday_overrides for update to authenticated using ((select private.is_parent(holiday_overrides.family_id))) with check ((select private.is_parent(holiday_overrides.family_id)));
create policy holiday_overrides_delete on public.holiday_overrides for delete to authenticated using ((select private.is_parent(holiday_overrides.family_id)));

-- 3. Fonctions inutilisées (period_bounds appelle first_end : dans cet ordre)
drop function private.period_bounds(date, date);
drop function private.first_end(date);
drop function private.paris_today();

-- 4. Fonctions de private : plus aucun droit d'exécution, sauf ce qu'exécutent les RLS (is_member, is_parent), la contrainte de
--    families.timezone (valid_tz) et le déclencheur set_relation_key, qui s'exécute avec les droits de l'appelant (relation_key).
--    Les fonctions SECURITY DEFINER s'appellent entre elles avec les droits de leur propriétaire ; les tâches pg_cron tournent en postgres ;
--    un déclencheur n'a besoin d'aucun droit d'exécution au moment où il se déclenche.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p
           where p.pronamespace = 'private'::regnamespace and p.prokind = 'f' loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('is_member', 'is_parent', 'valid_tz', 'relation_key') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;

-- 5. Fonctions nouvelles de public réservées aux comptes connectés (le droit par défaut les ouvrait aussi à anon)
revoke execute on function public.redeem(uuid, uuid, uuid) from public, anon;
revoke execute on function public.child_pair_here(uuid, text) from public, anon;

-- 6. Tables de public : plus aucun droit pour anon, sauf la lecture de languages et tips (seules tables lues sans compte)
revoke all on all tables in schema public from anon;
grant select on public.languages, public.tips to anon;
revoke all on all sequences in schema public from anon;

-- 7. Droits par défaut des objets créés à l'avenir par postgres (migrations) : rien pour anon, rien pour PUBLIC sur les fonctions
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from anon;
alter default privileges for role postgres revoke execute on functions from public;
