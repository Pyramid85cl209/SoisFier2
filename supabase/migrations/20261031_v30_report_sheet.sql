-- v30 (EP-13 V1, ADR-30) : report d'une semaine de coches par une fonction serveur unique (R04-11, F04-09).
-- À tester dans une transaction annulée (supabase/tests/v30_report_sheet_test.sql) avant d'appliquer. Sans drop ni delete.
--
-- public.report_sheet(p_child, p_week_start, p_items) : p_items = tableau JSON d'éléments {"routine": uuid, "day": "AAAA-MM-JJ"}.
-- Contrôles bloquants (rien n'est écrit si l'un échoue) :
--   SF:access_denied    pas Parent de la famille de l'enfant (Proche, téléphone de l'enfant, autre famille)
--   SF:premium_report   famille gratuite
--   SF:scan_week        p_week_start n'est pas le premier jour de la semaine en cours ou de la précédente (fuseau et premier jour de la famille)
--   SF:scan_day         jour absent, mal écrit, hors de la semaine choisie, ou à venir
--   SF:scan_too_many    plus de 500 éléments
-- La limite « 7 jours après la fin de la semaine choisie » (R04-11 CA6) découle du contrôle de semaine.
-- Statut renvoyé pour chaque élément (même ordre que p_items) :
--   reported      coche créée, validée au nom du Parent, étoiles fixées par le serveur (R05-01, R05-02)
--   validated     coche de l'enfant en attente, validée
--   already_done  déjà validée (ou créée entre-temps) : inchangée
--   not_due       routine pas due ce jour-là d'après private.routine_rules (vacances et routines en pause comprises) : non reportée
--   stopped       routine absente, d'un autre enfant, exceptionnelle ou arrêtée (active = false) : non reportée (DEC-08)
-- Les pauses de l'enfant ne sont pas lues (DEC-09, DT10-12). Ne supprime jamais rien : un rond vide ne retire aucune coche.
-- Jardin et série : recalculés par invalidate_stats pour un jour passé, comme pour une coche à la main.

create or replace function public.report_sheet(p_child uuid, p_week_start date, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  fid uuid; ws int; today date; cur date;
  items jsonb := coalesce(p_items, '[]'::jsonb);
  e jsonb; rtxt text; rid uuid; d date; st text; rc int;
  r record; cm record;
  res jsonb := '[]'::jsonb;
begin
  select c.family_id into fid from public.children c where c.id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:access_denied'; end if;
  if not private.is_premium(fid) then raise exception 'SF:premium_report'; end if;

  select f.week_start into ws from public.families f where f.id = fid;
  today := private.family_today(fid);
  cur := today - (((extract(isodow from today)::int - ws) + 7) % 7);
  if p_week_start is null or p_week_start not in (cur, cur - 7) then raise exception 'SF:scan_week'; end if;

  if jsonb_typeof(items) <> 'array' then items := '[]'::jsonb; end if;
  if jsonb_array_length(items) > 500 then raise exception 'SF:scan_too_many'; end if;

  for e in select x.value from jsonb_array_elements(items) as x loop
    begin d := (e->>'day')::date; exception when others then d := null; end;
    if d is null or d < p_week_start or d > p_week_start + 6 or d > today then raise exception 'SF:scan_day'; end if;

    rtxt := e->>'routine'; rid := null;
    if rtxt ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then rid := rtxt::uuid; end if;

    select ro.child_id, ro.kind, ro.active into r from public.routines ro where ro.id = rid;
    if not found or r.child_id <> p_child or r.kind <> 'regular' or not r.active then
      st := 'stopped';
    elsif not exists (select 1 from private.routine_rules(p_child, d) rr where rr.routine_id = rid) then
      st := 'not_due';
    else
      select co.id, co.validated_at into cm from public.completions co where co.routine_id = rid and co.day = d for update;
      if not found then
        insert into public.completions(family_id, child_id, routine_id, day, source)
        values (fid, p_child, rid, d, 'parent')
        on conflict (routine_id, day) do nothing;
        get diagnostics rc = row_count;
        st := case when rc = 1 then 'reported' else 'already_done' end;
      elsif cm.validated_at is null then
        update public.completions set validated_at = now() where id = cm.id;
        st := 'validated';
      else
        st := 'already_done';
      end if;
    end if;
    res := res || jsonb_build_object('routine', rtxt, 'day', d, 'status', st);
  end loop;
  return res;
end $$;

revoke execute on function public.report_sheet(uuid, date, jsonb) from public, anon;
grant execute on function public.report_sheet(uuid, date, jsonb) to authenticated;
