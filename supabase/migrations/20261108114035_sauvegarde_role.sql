-- EP-12 (R00-09, ADR-33) : rôle de sauvegarde en lecture seule.
-- Aucun mot de passe ici (dépôt public) : la personne qui pilote le saisit
-- dans l'éditeur SQL (alter role soisfier_sauvegarde password '...').

create role soisfier_sauvegarde
  login
  bypassrls
  noinherit
  nocreatedb
  nocreaterole
  connection limit 3;

alter role soisfier_sauvegarde set default_transaction_read_only = on;
alter role soisfier_sauvegarde set statement_timeout = '5min';

-- Données de l'application : tables et séquences de public et private
grant usage on schema public, private to soisfier_sauvegarde;
grant select on all tables in schema public, private to soisfier_sauvegarde;
grant select on all sequences in schema public, private to soisfier_sauvegarde;
alter default privileges for role postgres in schema public, private
  grant select on tables to soisfier_sauvegarde;
alter default privileges for role postgres in schema public, private
  grant select on sequences to soisfier_sauvegarde;

-- Comptes : colonnes autorisées seulement (sans encrypted_password, sans jetons,
-- sans colonnes calculées). Vues créées par postgres, fermées par défaut.
create view private.sauvegarde_users as
select instance_id, id, aud, role, email, email_confirmed_at, invited_at,
       confirmation_sent_at, recovery_sent_at, email_change, email_change_sent_at,
       last_sign_in_at, raw_app_meta_data, raw_user_meta_data, is_super_admin,
       created_at, updated_at, phone, phone_confirmed_at, phone_change,
       phone_change_sent_at, email_change_confirm_status, banned_until,
       reauthentication_sent_at, is_sso_user, deleted_at, is_anonymous
from auth.users;

create view private.sauvegarde_identities as
select provider_id, user_id, identity_data, provider, last_sign_in_at,
       created_at, updated_at, id
from auth.identities;

revoke all on private.sauvegarde_users, private.sauvegarde_identities
  from public, anon, authenticated, service_role;
grant select on private.sauvegarde_users, private.sauvegarde_identities
  to soisfier_sauvegarde;

-- Liste des tâches planifiées (plan de la base, ADR-34)
grant usage on schema cron to soisfier_sauvegarde;
grant select on cron.job to soisfier_sauvegarde;
