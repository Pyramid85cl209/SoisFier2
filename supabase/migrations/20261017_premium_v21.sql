-- v21 : réservation des fonctions Premium côté serveur.
-- Aucun effet tant que toutes les familles sont founder.
--
-- Gratuit : 1 enfant, 2 parents, pas de proche, pas de malus,
-- pas de routine exceptionnelle ni de modèle d'exceptionnelle.

create or replace function private.is_premium(p_family uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select plan in ('premium', 'founder') from public.families where id = p_family), false)
$$;

-- Garde unique, déclenchée avant insertion sur les tables concernées
create or replace function private.premium_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if private.is_premium(new.family_id) then return new; end if;
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

create trigger children_premium before insert on public.children
  for each row execute function private.premium_guard();
create trigger family_members_premium before insert on public.family_members
  for each row execute function private.premium_guard();
create trigger routines_premium before insert on public.routines
  for each row execute function private.premium_guard();
create trigger oneoff_templates_premium before insert on public.oneoff_templates
  for each row execute function private.premium_guard();
create trigger penalties_premium before insert on public.penalties
  for each row execute function private.premium_guard();
create trigger penalty_events_premium before insert on public.penalty_events
  for each row execute function private.premium_guard();

-- Invitation : refus dès la création du code (et pas seulement à l'utilisation)
create or replace function public.create_invite(p_family uuid, p_relation text default null, p_role text default 'parent')
returns text language plpgsql security definer set search_path = '' as $$
declare c text;
begin
  if not private.is_parent(p_family) then raise exception 'SF:invite_parent_only'; end if;
  if p_role not in ('parent','helper') then raise exception 'SF:unknown_role'; end if;
  if not private.is_premium(p_family) then
    if p_role = 'helper' then raise exception 'SF:premium_helpers'; end if;
    if (select count(*) from public.family_members where family_id = p_family and role = 'parent') >= 2 then
      raise exception 'SF:premium_adults';
    end if;
  end if;
  delete from public.invites where family_id = p_family and (expires_at < now() or used_at is not null);
  c := private.random_code(6);
  insert into public.invites(code, family_id, created_by, expires_at, relation, role)
  values (c, p_family, auth.uid(), now() + interval '48 hours', nullif(trim(p_relation), ''), p_role);
  return c;
end $$;

-- État de l'enfant : ajoute premium (le téléphone de l'enfant masque les badges et jardins Premium)
create or replace function public.child_state(p_token text)
returns json language plpgsql security definer set search_path = '' as $$
declare d record; today date; res json;
begin
  select * into d from private.device_child(p_token);
  today := private.family_today(d.family_id);
  select json_build_object(
    'today', today,
    'premium', private.is_premium(d.family_id),
    'child', (select row_to_json(c) from (select id, name, emoji, color, garden_start from public.children where id = d.child_id) c),
    'routines', coalesce((select json_agg(r order by r.position, r.created_at) from
        (select id, title, emoji, place, moment, stars, days, is_bonus, timer_minutes, position, created_at, kind, start_day, end_day
         from public.routines where child_id = d.child_id and active and (kind = 'regular' or end_day >= today - 2)) r), '[]'::json),
    'completions', coalesce((select json_agg(x) from
        (select routine_id, day, stars, source, validated_at is not null as validated,
           case when validated_at is null then null when validated_by is null then 'auto' else private.member_label(d.family_id, validated_by) end as validated_label
         from public.completions where child_id = d.child_id and day >= today - 60) x), '[]'::json),
    'oneoff_done', (select count(*) from public.completions c join public.routines r on r.id = c.routine_id
                    where c.child_id = d.child_id and r.kind = 'oneoff' and c.validated_at is not null),
    'rewards', coalesce((select json_agg(w order by w.cost) from
        (select id, title, emoji, tier, event_date, place, private.reward_cost(rw, d.child_id) as cost
         from public.rewards rw where family_id = d.family_id and active and (child_id is null or child_id = d.child_id)
           and (event_date is null or event_date >= today)) w), '[]'::json),
    'redemptions', coalesce((select json_agg(z order by z.created_at desc) from
        (select id, title, emoji, cost, created_at from public.redemptions where child_id = d.child_id
         order by created_at desc limit 30) z), '[]'::json),
    'penalties', coalesce((select json_agg(p order by p.created_at desc) from
        (select id, title, emoji, stars, created_at from public.penalty_events where child_id = d.child_id
         order by created_at desc limit 30) p), '[]'::json),
    'badges', coalesce((select json_agg(b.badge_key) from public.child_badges b where b.child_id = d.child_id), '[]'::json),
    'badge_dates', coalesce((select json_object_agg(b.badge_key, b.earned_at) from public.child_badges b where b.child_id = d.child_id), '{}'::json),
    'stats', (select row_to_json(s) from (select earned, done_count, pending_stars, pending_count, spent, redeemed_count, broken, broken_count
              from public.child_stats where child_id = d.child_id) s),
    'garden', private.garden_payload(d.child_id),
    'family', (select json_build_object('week_start', week_start, 'weekend_days', weekend_days, 'timezone', timezone) from public.families where id = d.family_id)
  ) into res;
  return res;
end $$;
