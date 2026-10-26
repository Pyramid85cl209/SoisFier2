-- v27 (points 1 à 3 de l'analyse) : pause modifiable, pause commencée non supprimable
-- Contient « DELETE » dans le corps de la fonction : à appliquer dans l'éditeur SQL, puis à enregistrer
-- dans supabase_migrations.schema_migrations (version 20261027000000, nom v27_pauses).
--
-- Règle (décidée le 26 octobre 2026) : une pause est commencée quand son premier jour est passé
-- (avant aujourd'hui, heure de la famille). Une pause commencée et créée il y a plus de 24 h :
--   - ne se supprime pas (SF:pause_started) ;
--   - garde son premier jour, son enfant et sa famille (SF:pause_started) ;
--   - peut s'arrêter (dernier jour = hier) ou se prolonger, mais sa fin ne recule pas avant hier
--     ni avant sa fin actuelle si celle-ci est déjà passée (les jours neutres passés restent neutres).
-- Dans les 24 h qui suivent sa création, tout reste modifiable (correction d'une erreur de saisie).
-- Suppression de l'enfant ou de la famille (cascade) : toujours permise.
-- Compatible avec la version en production : elle insère et supprime des pauses à venir ou récentes ;
-- le motif reste un texte libre (la v27 enregistre une clé : trip, sick, other).

create or replace function private.pause_check() returns trigger
language plpgsql security definer set search_path = '' as $$
declare today date; locked boolean;
begin
  if tg_op = 'INSERT' then return new; end if;
  today := private.family_today(old.family_id);
  locked := old.start_day < today and old.created_at < now() - interval '24 hours';
  if tg_op = 'DELETE' then
    if locked and exists (select 1 from public.children where id = old.child_id) then
      raise exception 'SF:pause_started';
    end if;
    return old;
  end if;
  if locked and (new.start_day <> old.start_day or new.child_id <> old.child_id or new.family_id <> old.family_id
                 or new.end_day < least(old.end_day, today - 1)) then
    raise exception 'SF:pause_started';
  end if;
  return new;
end $$;

drop trigger if exists pauses_check on public.pauses;
create trigger pauses_check before update or delete on public.pauses
  for each row execute function private.pause_check();
