-- v29 (point 16 de l'analyse, décision D9-1) : liens de parenté enregistrés en clé, traduits à l'affichage. Testée dans une transaction annulée, puis appliquée par le connecteur le 29 octobre 2026 (version 20261029000949).
-- Compatible avec la v28c : la colonne relation (texte) reste lue et écrite comme avant ;
-- la clé est calculée par un déclencheur à chaque écriture du texte. Sans drop ni delete.

-- 1. Libellé (fr, ar, en) -> clé ; texte libre non reconnu -> null (affiché tel quel)
create or replace function private.relation_key(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case regexp_replace(lower(btrim(coalesce(p, ''))), '[ًٌٍَُِّْ]', '', 'g')
    when 'papa' then 'dad' when 'dad' then 'dad' when 'daddy' then 'dad' when 'بابا' then 'dad'
    when 'maman' then 'mom' when 'mum' then 'mom' when 'mom' then 'mom' when 'mummy' then 'mom' when 'ماما' then 'mom'
    when 'papy' then 'grandpa' when 'papi' then 'grandpa' when 'grandad' then 'grandpa' when 'granddad' then 'grandpa' when 'grandpa' then 'grandpa' when 'جدو' then 'grandpa'
    when 'mamie' then 'grandma' when 'mamy' then 'grandma' when 'grandma' then 'grandma' when 'granny' then 'grandma' when 'تيتة' then 'grandma'
    when 'tonton' then 'uncle' when 'uncle' then 'uncle'
    when 'tata' then 'aunt' when 'tatie' then 'aunt' when 'auntie' then 'aunt' when 'aunt' then 'aunt'
    when 'عمو' then 'uncle_p' when 'خالو' then 'uncle_m'
    when 'عمتو' then 'aunt_p' when 'خالتو' then 'aunt_m'
    when 'parrain' then 'godfather' when 'godfather' then 'godfather' when 'العراب' then 'godfather'
    when 'marraine' then 'godmother' when 'godmother' then 'godmother' when 'العرابة' then 'godmother'
    when 'nounou' then 'nanny' when 'nanny' then 'nanny' when 'المربية' then 'nanny'
  end
$$;

-- 2. Colonnes
alter table public.family_members add column if not exists relation_key text;
alter table public.invites add column if not exists relation_key text;
alter table public.family_members add constraint family_members_relation_key_chk check (relation_key is null or relation_key in
  ('dad','mom','grandpa','grandma','uncle','aunt','uncle_p','uncle_m','aunt_p','aunt_m','godfather','godmother','nanny'));
alter table public.invites add constraint invites_relation_key_chk check (relation_key is null or relation_key in
  ('dad','mom','grandpa','grandma','uncle','aunt','uncle_p','uncle_m','aunt_p','aunt_m','godfather','godmother','nanny'));

-- 3. Clé calculée à chaque écriture du texte (v28c et v29 écrivent seulement relation)
create or replace function private.set_relation_key()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.relation_key := private.relation_key(new.relation);
  return new;
end;
$$;

create trigger family_members_relation_key before insert or update of relation on public.family_members
  for each row execute function private.set_relation_key();
create trigger invites_relation_key before insert or update of relation on public.invites
  for each row execute function private.set_relation_key();

-- 4. Lignes existantes
update public.family_members set relation_key = private.relation_key(relation) where relation is not null;
update public.invites set relation_key = private.relation_key(relation) where relation is not null;
