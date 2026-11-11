-- EP-09 thème B : vacances, pauses, garde-fous Premium à la modification (ADR-50, ADR-51).
-- Contient « DELETE » dans le corps de fonctions et des drop trigger (uniquement de ses propres déclencheurs) : à lancer dans l'ÉDITEUR SQL de Supabase, puis à enregistrer
-- dans supabase_migrations.schema_migrations (version 20261112090000, nom ep09b_vacances_pauses_premium).
-- Compatible avec l'ancienne version de l'application (elle n'écrit que des pauses, périodes et droits permis par ces règles,
-- sauf le motif « sick », converti en « rest » par le déclencheur).
-- À tester dans une transaction annulée (supabase/tests/ep09b_vacances_test.sql).
--
-- DT10-02  24 h de grâce après la création d'une période (modifiable et supprimable, comme une pause)
-- DT10-03  « commencée » = premier jour passé (heure de la famille)
-- DT10-04  période commencée : premier jour et fin passée figés, fin jamais avant hier ; période déjà finie non créable
-- DT10-05  created_at figé (périodes et pauses) ; une date de création future est ramenée à maintenant
-- DT10-06  réactivation d'une période refusée sans Premium
-- DT10-07  pause sur une quinzaine close (fleur éclose) refusée
-- DT10-08  pauses d'un même enfant qui se chevauchent refusées
-- DT10-13  motif « Repos » (clé rest) à la place de « Maladie » (sick)
-- DT02-03, DT12-02  premium_guard aussi à la mise à jour (droit d'un membre, routine passée en exceptionnelle)
-- DT10-09 (coche d'adulte hors période) : déjà traité par private.check_completion (thème A).
-- Constat (DT proposée) : pauses.reason n'a ni contrainte ni valeur par défaut en base (texte libre, ancien texte affiché tel quel,
-- M10b) : rien à contraindre ; le défaut « rest » est écrit par l'application.

-- 1. Périodes de vacances
create or replace function private.holiday_period_check() returns trigger
language plpgsql security definer set search_path = '' as $$
declare today date; locked boolean;
begin
  if tg_op = 'DELETE' then
    -- Une période commencée (premier jour passé) et créée il y a plus de 24 h ne se supprime pas : elle s'arrête.
    -- Sauf suppression de l'enfant ou de la famille (cascade).
    if old.start_day < private.family_today(old.family_id) and old.created_at < now() - interval '24 hours'
       and exists (select 1 from public.children where id = old.child_id) then
      raise exception 'SF:holiday_started';
    end if;
    return old;
  end if;
  today := private.family_today(new.family_id);
  if tg_op = 'INSERT' then
    if not private.is_premium(new.family_id) then raise exception 'SF:premium_holidays'; end if;
    if new.end_day < today then raise exception 'SF:holiday_past'; end if;
    if new.created_at is null or new.created_at > now() then new.created_at := now(); end if;
  else
    new.created_at := old.created_at;
    -- Réactivation d'une période désactivée : Premium seulement
    if new.active and not old.active and not private.is_premium(new.family_id) then raise exception 'SF:premium_holidays'; end if;
    locked := old.start_day < today and old.created_at < now() - interval '24 hours';
    if locked and (new.start_day <> old.start_day or new.child_id <> old.child_id or new.family_id <> old.family_id
                   or (new.end_day <> old.end_day and (old.end_day < today or new.end_day < today - 1))) then
      raise exception 'SF:holiday_started';
    end if;
  end if;
  if new.active and exists (select 1 from public.holiday_periods p
      where p.child_id = new.child_id and p.active and p.id <> new.id
        and p.start_day <= new.end_day and new.start_day <= p.end_day) then
    raise exception 'SF:holiday_overlap';
  end if;
  return new;
end $$;

-- 2. Pauses : insertion contrôlée, date de création figée, motif « Repos »
create or replace function private.pause_check() returns trigger
language plpgsql security definer set search_path = '' as $$
declare today date; locked boolean;
begin
  if tg_op = 'INSERT' then
    -- ancien motif converti (copie locale d'avant la mise à jour)
    if new.reason = 'sick' then new.reason := 'rest'; end if;
    if new.created_at is null or new.created_at > now() then new.created_at := now(); end if;
  else
    today := private.family_today(old.family_id);
    locked := old.start_day < today and old.created_at < now() - interval '24 hours';
    if tg_op = 'DELETE' then
      if locked and exists (select 1 from public.children where id = old.child_id) then
        raise exception 'SF:pause_started';
      end if;
      return old;
    end if;
    new.created_at := old.created_at;
    if new.reason = 'sick' then new.reason := 'rest'; end if;
    if locked and (new.start_day <> old.start_day or new.child_id <> old.child_id or new.family_id <> old.family_id
                   or new.end_day < least(old.end_day, today - 1)) then
      raise exception 'SF:pause_started';
    end if;
    -- dates inchangées : rien d'autre à contrôler (pauses existantes gardées telles quelles)
    if new.start_day = old.start_day and new.end_day = old.end_day and new.child_id = old.child_id then return new; end if;
  end if;
  if exists (select 1 from public.pauses p where p.child_id = new.child_id and p.id <> new.id
             and p.start_day <= new.end_day and new.start_day <= p.end_day) then
    raise exception 'SF:pause_overlap';
  end if;
  if exists (select 1 from public.flowers f where f.child_id = new.child_id
             and f.period_start <= new.end_day and f.period_end >= new.start_day) then
    raise exception 'SF:pause_closed';
  end if;
  return new;
end $$;

drop trigger if exists pauses_check on public.pauses;
create trigger pauses_check before insert or update or delete on public.pauses
  for each row execute function private.pause_check();

update public.pauses set reason = 'rest' where reason = 'sick';

-- 3. Premium à la modification : droit d'un membre, type d'une routine
create or replace function private.premium_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if private.is_premium(new.family_id) then return new; end if;
  if tg_op = 'UPDATE' then   -- seuls les changements du droit ou du type sont contrôlés
    if tg_table_name = 'family_members' then
      if new.role is not distinct from old.role then return new; end if;
    elsif tg_table_name = 'routines' then
      if new.kind is not distinct from old.kind then return new; end if;
    end if;
  end if;
  case tg_table_name
    when 'children' then
      if exists (select 1 from public.children where family_id = new.family_id) then
        raise exception 'SF:premium_children';
      end if;
    when 'family_members' then
      if new.role = 'helper' then raise exception 'SF:premium_helpers'; end if;
      if (select count(*) from public.family_members where family_id = new.family_id and role = 'parent') >= 2 then
        raise exception 'SF:premium_adults';
      end if;
    when 'routines' then
      if new.kind = 'oneoff' then raise exception 'SF:premium_oneoff'; end if;
    when 'oneoff_templates' then
      raise exception 'SF:premium_oneoff';
    when 'penalties', 'penalty_events' then
      raise exception 'SF:premium_malus';
    else null;
  end case;
  return new;
end $$;

drop trigger if exists family_members_premium_upd on public.family_members;
create trigger family_members_premium_upd before update of role on public.family_members
  for each row execute function private.premium_guard();
drop trigger if exists routines_premium_upd on public.routines;
create trigger routines_premium_upd before update of kind on public.routines
  for each row execute function private.premium_guard();
