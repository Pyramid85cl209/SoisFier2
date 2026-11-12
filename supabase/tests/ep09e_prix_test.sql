-- Test de la migration ep09e (thème E d'EP-09 : plafond des prix) : à lancer AVANT de l'appliquer, dans l'éditeur SQL de Supabase. Transaction annulée : famille et récompenses fictives, rien n'est conservé.
-- Contenu : migration 20261112140000 puis les cas E1 à E6.
-- Résultat attendu : une seule ligne d'erreur « RESULT: … » contenant, dans l'ordre :
--  E1.prix_5000=ok E2.prix_5001=SF:price_cap E3.prix_enfant_6000=SF:price_cap E4.prix_enfant_5000=ok E5.modif_au_dela=SF:price_cap E6.modif_titre=ok
-- Lancé jusqu'ici sur une réplique locale du schéma (PostgreSQL 16), pas sur la base de production.
begin;
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
do $t$
declare fid uuid; c1 uuid; res text := '';
begin
  insert into public.families(name, plan) values ('Famille test EP-09E', 'premium') returning id into fid;
  insert into public.children(family_id, name) values (fid, 'Enfant 1') returning id into c1;
  create or replace function pg_temp.try(q text) returns text language plpgsql as $f$ begin execute q; return 'ok'; exception when others then return sqlerrm; end $f$;
  res := res || ' E1.prix_5000=' || pg_temp.try(format('insert into public.rewards(family_id, title, cost, costs) values (%L, ''A'', 5000, ''{}'')', fid));
  res := res || ' E2.prix_5001=' || pg_temp.try(format('insert into public.rewards(family_id, title, cost, costs) values (%L, ''B'', 5001, ''{}'')', fid));
  res := res || ' E3.prix_enfant_6000=' || pg_temp.try(format('insert into public.rewards(family_id, title, cost, costs) values (%L, ''C'', 100, jsonb_build_object(%L, 6000))', fid, c1));
  res := res || ' E4.prix_enfant_5000=' || pg_temp.try(format('insert into public.rewards(family_id, title, cost, costs) values (%L, ''D'', 100, jsonb_build_object(%L, 5000))', fid, c1));
  res := res || ' E5.modif_au_dela=' || pg_temp.try(format('update public.rewards set costs = jsonb_build_object(%L, 5200) where title = ''D''', c1));
  res := res || ' E6.modif_titre=' || pg_temp.try('update public.rewards set title = ''D2'' where title = ''D''');
  raise exception 'RESULT:%', res;
end $t$;
