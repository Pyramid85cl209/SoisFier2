-- SoisFier – optimisations du 11 octobre 2026
-- 1) Table des langues : remplace les listes figées ('fr', 'ar', 'en') des contraintes et des fonctions.
--    Ajouter une langue = une ligne dans public.languages (plus besoin de drop).
-- 2) Purge mensuelle de l'historique pg_cron (cron.job_run_details).
-- À lancer une fois dans l'éditeur SQL de Supabase (le script contient des « drop »).

begin;

-- 1. Table des langues ---------------------------------------------------------------------------
create table if not exists public.languages (
  code text primary key check (code ~ '^[a-z]{2,3}$'),
  name text not null,                       -- nom dans la langue elle-même
  rtl boolean not null default false,       -- écriture de droite à gauche
  status text not null default 'review' check (status in ('review', 'ok')),
  created_at timestamptz not null default now()
);
alter table public.languages enable row level security;
drop policy if exists languages_read on public.languages;
create policy languages_read on public.languages for select to anon, authenticated using (true);
grant select on public.languages to anon, authenticated;

insert into public.languages(code, name, rtl, status) values
  ('fr', 'Français', false, 'ok'),
  ('ar', 'العربية', true, 'review')
on conflict (code) do nothing;

-- Contraintes figées remplacées par des clés étrangères
alter table public.family_members drop constraint if exists family_members_locale_chk;
alter table public.push_subscriptions drop constraint if exists push_subscriptions_locale_chk;
alter table public.family_members drop constraint if exists family_members_locale_fk;
alter table public.push_subscriptions drop constraint if exists push_subscriptions_locale_fk;
alter table public.tips drop constraint if exists tips_locale_fk;
alter table public.family_members add constraint family_members_locale_fk foreign key (locale) references public.languages(code) on update cascade;
alter table public.push_subscriptions add constraint push_subscriptions_locale_fk foreign key (locale) references public.languages(code) on update cascade;
alter table public.tips add constraint tips_locale_fk foreign key (locale) references public.languages(code) on update cascade;

-- Langue valide, sinon français
create or replace function private.valid_locale(p text) returns text
 language sql stable security definer set search_path to ''
as $$ select coalesce((select code from public.languages where code = p), 'fr') $$;

create or replace function public.parent_push_subscribe(p_family uuid, p_endpoint text, p_p256dh text, p_auth text, p_times text[], p_locale text default 'fr')
 returns void language plpgsql security definer set search_path to ''
as $function$
declare loc text := private.valid_locale(p_locale);
begin
  if not private.is_member(p_family) then raise exception 'SF:access_denied'; end if;
  insert into public.push_subscriptions(family_id, user_id, child_device_id, endpoint, p256dh, auth, reminder_times, locale)
  values (p_family, auth.uid(), null, p_endpoint, p_p256dh, p_auth, p_times, loc)
  on conflict (endpoint) do update set family_id = excluded.family_id, user_id = excluded.user_id,
    child_device_id = null, p256dh = excluded.p256dh, auth = excluded.auth, reminder_times = excluded.reminder_times, locale = excluded.locale;
end $function$;

create or replace function public.child_push_subscribe(p_token text, p_endpoint text, p_p256dh text, p_auth text, p_times text[], p_locale text default 'fr')
 returns void language plpgsql security definer set search_path to ''
as $function$
declare d record; loc text := private.valid_locale(p_locale);
begin
  select * into d from private.device_child(p_token);
  insert into public.push_subscriptions(family_id, user_id, child_device_id, endpoint, p256dh, auth, reminder_times, locale)
  values (d.family_id, null, d.device_id, p_endpoint, p_p256dh, p_auth, p_times, loc)
  on conflict (endpoint) do update set family_id = excluded.family_id, user_id = null,
    child_device_id = excluded.child_device_id, p256dh = excluded.p256dh, auth = excluded.auth, reminder_times = excluded.reminder_times, locale = excluded.locale;
end $function$;

create or replace function public.push_set_locale(p_endpoint text, p_locale text)
 returns void language sql security definer set search_path to ''
as $$ update public.push_subscriptions set locale = p_locale
      where endpoint = p_endpoint and exists (select 1 from public.languages where code = p_locale) $$;

-- 2. Purge mensuelle de l'historique pg_cron (le 1er du mois, 3h40 UTC, garde 30 jours) -----------
select cron.unschedule(jobid) from cron.job where jobname = 'soisfier-purge-cron-logs';
select cron.schedule('soisfier-purge-cron-logs', '40 3 1 * *',
  $$delete from cron.job_run_details where end_time < now() - interval '30 days'$$);

-- Contrôle : toute anomalie annule l'ensemble
do $$
declare n int;
begin
  select count(*) into n from public.languages where code in ('fr', 'ar'); if n <> 2 then raise exception 'langues manquantes'; end if;
  select count(*) into n from pg_constraint where conname in ('family_members_locale_chk', 'push_subscriptions_locale_chk'); if n <> 0 then raise exception 'anciennes contraintes encore là'; end if;
  select count(*) into n from pg_constraint where conname like '%_locale_fk'; if n <> 3 then raise exception 'clés étrangères manquantes'; end if;
  select count(*) into n from cron.job where jobname = 'soisfier-purge-cron-logs'; if n <> 1 then raise exception 'purge non planifiée'; end if;
end $$;

commit;
