-- v21 : offre de la famille (appliquée le 17 octobre 2026 par le connecteur)
-- free, premium (abonnement) ou founder (Premium à vie, offre fondateur).
-- Par défaut founder jusqu'à nouvel ordre : toutes les familles existantes et nouvelles.
alter table public.families
  add column if not exists plan text not null default 'founder'
    check (plan in ('free', 'premium', 'founder'));

-- Le plan ne se modifie que côté serveur (Stripe, Google Play, ou à la main par l'admin)
create or replace function private.protect_plan() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.plan is distinct from old.plan and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'SF:plan_readonly';
  end if;
  return new;
end $$;

create trigger families_protect_plan before update of plan on public.families
  for each row execute function private.protect_plan();
