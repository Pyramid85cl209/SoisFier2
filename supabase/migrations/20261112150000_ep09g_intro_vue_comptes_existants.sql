-- EP-09 thème G (F14-04 CA6 à CA8, DEC-56, DEC-57, ADR-48) : présentation de l'application « déjà vue » pour les comptes existants.
-- À appliquer à la livraison, AVANT la publication de l'application. Seuls sont marqués les adultes membres d'au moins une famille
-- qui a une routine (de tout type, arrêtées comprises) ; les autres verront la présentation une fois (CA7).
-- Aucun e-mail ni identifiant de compte dans cette migration. Le compte de la personne qui pilote est remis à « non vu » par une
-- commande ponctuelle dans l'éditeur SQL, lancée à la livraison et non enregistrée dans le dépôt.
-- Les métadonnées existantes du compte sont conservées (fusion jsonb) ; la migration peut être rejouée sans autre effet.
update auth.users u
   set raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb) || '{"intro_seen": true}'::jsonb
 where exists (select 1 from public.family_members m join public.routines r on r.family_id = m.family_id where m.user_id = u.id);
