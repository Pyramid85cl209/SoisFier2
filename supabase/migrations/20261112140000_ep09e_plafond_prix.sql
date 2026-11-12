-- EP-09 thème E : plafond des prix (DT06-06, R06-03, F06-03 CA11). Addition seule, compatible avec l'ancienne version de l'application :
-- un prix (celui de la récompense ou l'un des prix calculés par enfant) au-delà de 5 000 est refusé avec le code SF:price_cap (message clair traduit),
-- au lieu de l'erreur brute de la contrainte. À tester dans une transaction annulée (supabase/tests/ep09e_prix_test.sql).
create or replace function private.reward_price_cap() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.cost > 5000 or exists (select 1 from jsonb_each_text(coalesce(new.costs, '{}'::jsonb)) c where c.value ~ '^\d+$' and c.value::numeric > 5000) then
    raise exception 'SF:price_cap';
  end if;
  return new;
end $$;

drop trigger if exists rewards_price_cap on public.rewards;
create trigger rewards_price_cap before insert or update on public.rewards
  for each row execute function private.reward_price_cap();
