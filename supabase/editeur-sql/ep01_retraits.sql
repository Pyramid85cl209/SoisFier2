-- EP-01 : retraits (suppressions), à lancer dans l'éditeur SQL de Supabase (ADR-07), PAS par le connecteur.
-- À lancer SEULEMENT quand la v33 est en ligne ET diffusée aux téléphones (mise à jour automatique, ADR-26) :
-- l'application v32 appelle encore les anciennes signatures ci-dessous. Avant : « select count(*) from public.child_devices where child_id is not null » sert de repère.
-- Étape 1 de 3 : fonctions remplacées par les nouvelles signatures (à plusieurs enfants, à plusieurs familles).
begin;
drop function if exists public.child_state(text);
drop function if exists public.child_toggle(text, uuid, date, boolean, text);
drop function if exists public.child_redeem(text, uuid);
drop function if exists public.child_badges_seen(text, text[]);
drop function if exists public.create_child_code(uuid);
drop function if exists public.child_pair_here(uuid, text);
drop function if exists public.create_family(text, text, smallint, smallint[], text);
drop function if exists public.parent_push_subscribe(uuid, text, text, text, text[], text);
drop function if exists private.device_child(text);
-- Étape 2 de 3 : colonne child_devices.child_id (la table child_device_children est la seule source)
alter table public.child_devices drop column if exists child_id;
-- Étape 3 de 3 : clés des rappels sorties de la base (ADR-45) ; vapid_public reste (clé publique)
-- Ne lancer cette étape qu'après avoir vu un vrai rappel arriver avec les secrets de la fonction Edge.
delete from private.config where key in ('vapid_private', 'vapid_subject', 'cron_secret');
-- Contrôle : doit renvoyer vapid_public seule
select key from private.config;
commit;
