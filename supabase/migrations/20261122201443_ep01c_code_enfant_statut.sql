-- EP-01 lot C : quels enfants d'une famille ont déjà un code d'enfant (R03-11 CA1, F03-09, ADR-53).
-- Le Parent ne peut pas lire private.child_codes (hors API) : cette fonction dit seulement « a un code » ou non, jamais l'empreinte.
-- Parent seul (SF:device_parent_only sinon), comptes connectés seulement. Additions seulement, rien n'est supprimé.
-- À tester dans une transaction annulée : supabase/tests/ep01c_code_enfant_statut_test.sql (rejoue la migration A d'abord).

create or replace function public.child_code_status(p_family uuid)
returns table (child_id uuid, has_code boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_family is null or auth.uid() is null or not private.is_parent(p_family) then raise exception 'SF:device_parent_only'; end if;
  return query
    select c.id, exists (select 1 from private.child_codes k where k.child_id = c.id)
    from public.children c where c.family_id = p_family order by c.position, c.created_at;
end $$;
revoke all on function public.child_code_status(uuid) from public, anon;
grant execute on function public.child_code_status(uuid) to authenticated;
