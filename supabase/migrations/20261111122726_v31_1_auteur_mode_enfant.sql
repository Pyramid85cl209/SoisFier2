-- v31.1 (correctif, DT05-06) : en Mode enfant ici (téléphone d'un adulte connecté, ouvert en mode enfant),
-- une coche ou un échange envoyé par l'enfant ne porte plus l'adulte connecté comme auteur.
-- Comme sur l'appareil de l'enfant sans session, created_by reste vide (affiché au prénom de l'enfant).
-- Seuls child_toggle et child_redeem (jeton d'appareil vérifié par private.device_child) posent le repère
-- sf.via_device, local à la transaction ; il n'est pas modifiable depuis l'API (PostgREST n'expose pas set_config).
-- Toute autre écriture garde auth.uid() (T05-16 : auteur fixé par le serveur, pas d'auteur forgé).
-- Pas de reprise des données déjà enregistrées (décision du 11/11/2026). Sans drop ni delete.

-- 1. Déclencheurs d'auteur
create or replace function private.set_completion_stars()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  select coalesce((select rr.stars from private.routine_rules(new.child_id, new.day) rr where rr.routine_id = new.routine_id), r.stars)
    into new.stars from public.routines r where r.id = new.routine_id;
  if coalesce(current_setting('sf.via_device', true), '') = 'on' and new.source in ('child', 'timer') then
    new.created_by := null;   -- action de l'enfant par son jeton d'appareil (Mode enfant ici compris)
  else
    new.created_by := auth.uid();
  end if;
  if new.source = 'parent' then new.validated_at := coalesce(new.validated_at, now()); new.validated_by := auth.uid();
  else new.validated_at := null; new.validated_by := null; end if;
  return new;
end $function$;

create or replace function private.set_redemption_author()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if coalesce(current_setting('sf.via_device', true), '') = 'on' then new.created_by := null;
  else new.created_by := auth.uid(); end if;
  return new;
end $function$;

-- 2. Appels de l'enfant par jeton : repère posé autour de la seule insertion
create or replace function public.child_toggle(p_token text, p_routine uuid, p_day date, p_done boolean, p_source text default 'child'::text)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare d record; today date; r record;
begin
  select * into d from private.device_child(p_token);
  today := private.family_today(d.family_id);
  select * into r from public.routines where id = p_routine and child_id = d.child_id and active;
  if not found then raise exception 'SF:routine_not_found'; end if;
  if p_day < today - 2 or p_day > today then raise exception 'SF:day_locked'; end if;
  if r.kind = 'oneoff' and (p_day < r.start_day or p_day > r.end_day) then raise exception 'SF:oneoff_out_of_range'; end if;
  if r.holiday_period_id is not null and not exists (select 1 from public.holiday_periods p
      where p.id = r.holiday_period_id and p.active and p_day between p.start_day and p.end_day) then
    raise exception 'SF:holiday_out_of_range';
  end if;
  if p_done then
    perform set_config('sf.via_device', 'on', true);
    insert into public.completions(family_id, child_id, routine_id, day, source)
    values (d.family_id, d.child_id, p_routine, p_day, case when p_source in ('child','timer') then p_source else 'child' end)
    on conflict (routine_id, day) do nothing;
    perform set_config('sf.via_device', '', true);
  else
    if exists (select 1 from public.completions where routine_id = p_routine and day = p_day and validated_at is not null) then
      raise exception 'SF:validated_by_parent';
    end if;
    delete from public.completions where routine_id = p_routine and day = p_day and child_id = d.child_id and validated_at is null;
  end if;
  return json_build_object('ok', true);
end $function$;

create or replace function public.child_redeem(p_token text, p_reward uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare d record; w public.rewards; price int;
begin
  select * into d from private.device_child(p_token);
  select * into w from public.rewards where id = p_reward and family_id = d.family_id and active
    and (child_id is null or child_id = d.child_id);
  if not found then raise exception 'SF:reward_not_found'; end if;
  price := private.reward_cost(w, d.child_id);
  if coalesce(private.balance(d.child_id), 0) < price then raise exception 'SF:not_enough_stars'; end if;
  perform set_config('sf.via_device', 'on', true);
  insert into public.redemptions(family_id, child_id, reward_id, title, emoji, cost)
  values (d.family_id, d.child_id, w.id, w.title, w.emoji, price);
  perform set_config('sf.via_device', '', true);
  return json_build_object('ok', true);
end $function$;
