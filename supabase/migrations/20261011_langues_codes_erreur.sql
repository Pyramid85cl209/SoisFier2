-- SoisFier : multilingue étape 2 (côté base)
-- Langue par membre et par abonnement aux rappels, codes d'erreur traduits par l'app, rappels en données brutes, astuces par langue.
-- Aucune donnée supprimée. Les familles existantes restent en français.
-- Tout est dans une transaction : si un contrôle final échoue, rien n'est appliqué.
begin;

-- 1. Langues ---------------------------------------------------------------------------------
alter table public.family_members add column if not exists locale text not null default 'fr';
alter table public.family_members add constraint family_members_locale_chk check (locale in ('fr', 'ar', 'en'));
alter table public.push_subscriptions add column if not exists locale text not null default 'fr';
alter table public.push_subscriptions add constraint push_subscriptions_locale_chk check (locale in ('fr', 'ar', 'en'));
alter table public.tips add column if not exists locale text not null default 'fr';
create index if not exists tips_locale_idx on public.tips (locale, id);

-- 2. Codes d'erreur (« SF:code », traduits par l'app) -----------------------------------------
create or replace function private.device_child(p_token text, out device_id uuid, out child_id uuid, out family_id uuid)
 returns record language plpgsql security definer set search_path to ''
as $function$
begin
  select d.id, d.child_id, d.family_id into device_id, child_id, family_id
  from public.child_devices d
  where d.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if device_id is null then raise exception 'SF:device_unknown'; end if;
  update public.child_devices set last_seen = now() where id = device_id;
end $function$;

create or replace function private.protect_completion() returns trigger
 language plpgsql security definer set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() = 1 and old.validated_at is not null and old.validated_at < now() - interval '5 minutes' then
      raise exception 'SF:already_validated_break';
    end if;
    return old;
  end if;
  new.stars := old.stars; new.routine_id := old.routine_id; new.child_id := old.child_id;
  new.family_id := old.family_id; new.day := old.day; new.created_by := old.created_by;
  if old.validated_at is not null and new.validated_at is distinct from old.validated_at then
    raise exception 'SF:already_validated';
  end if;
  if old.validated_at is null and new.validated_at is not null then new.validated_by := auth.uid(); else new.validated_by := old.validated_by; end if;
  return new;
end $function$;

create or replace function private.protect_member() returns trigger
 language plpgsql security definer set search_path to ''
as $function$
declare nparents int;
begin
  select count(*) into nparents from public.family_members where family_id = old.family_id and role = 'parent';
  if tg_op = 'DELETE' then
    if old.role = 'parent' and nparents <= 1 and pg_trigger_depth() = 1 then raise exception 'SF:last_parent'; end if;
    return old;
  end if;
  new.family_id := old.family_id; new.user_id := old.user_id;
  if new.role is distinct from old.role then
    if not private.is_parent(old.family_id) then raise exception 'SF:rights_parent_only'; end if;
    if old.role = 'parent' and nparents <= 1 then raise exception 'SF:last_parent'; end if;
  end if;
  return new;
end $function$;

create or replace function public.apply_penalty(p_child uuid, p_penalty uuid, p_title text, p_emoji text, p_stars integer)
 returns integer language plpgsql security definer set search_path to ''
as $function$
declare fid uuid; pen record; t text; e text; n int; bal int;
begin
  select family_id into fid from public.children where id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:penalty_parent_only'; end if;
  if p_penalty is not null then
    select * into pen from public.penalties where id = p_penalty and family_id = fid;
    if not found then raise exception 'SF:penalty_not_found'; end if;
    t := pen.title; e := pen.emoji; n := pen.stars;
  else
    t := nullif(trim(p_title), ''); e := coalesce(nullif(trim(p_emoji), ''), '💔'); n := p_stars;
    if t is null then raise exception 'SF:need_reason'; end if;
  end if;
  n := greatest(1, least(3, coalesce(n, 1)));
  bal := coalesce(private.balance(p_child), 0);
  if bal <= 0 then raise exception 'SF:balance_zero'; end if;
  n := least(n, bal);
  insert into public.penalty_events(family_id, child_id, penalty_id, title, emoji, stars, created_by)
  values (fid, p_child, p_penalty, t, e, n, auth.uid());
  return n;
end $function$;

create or replace function public.child_pair(p_code text, p_label text default null::text)
 returns json language plpgsql security definer set search_path to ''
as $function$
declare rec record; tok text;
begin
  select * into rec from public.child_device_codes where code = upper(trim(p_code)) and expires_at > now();
  if not found then raise exception 'SF:bad_code'; end if;
  tok := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.child_devices(child_id, family_id, token_hash, label)
  values (rec.child_id, rec.family_id, encode(extensions.digest(tok, 'sha256'), 'hex'), nullif(left(trim(p_label), 60), ''));
  delete from public.child_device_codes where code = rec.code;
  return json_build_object('token', tok, 'child_id', rec.child_id);
end $function$;

create or replace function public.child_redeem(p_token text, p_reward uuid)
 returns json language plpgsql security definer set search_path to ''
as $function$
declare d record; w public.rewards; price int;
begin
  select * into d from private.device_child(p_token);
  select * into w from public.rewards where id = p_reward and family_id = d.family_id and active
    and (child_id is null or child_id = d.child_id);
  if not found then raise exception 'SF:reward_not_found'; end if;
  price := private.reward_cost(w, d.child_id);
  if coalesce(private.balance(d.child_id), 0) < price then raise exception 'SF:not_enough_stars'; end if;
  insert into public.redemptions(family_id, child_id, reward_id, title, emoji, cost)
  values (d.family_id, d.child_id, w.id, w.title, w.emoji, price);
  return json_build_object('ok', true);
end $function$;

create or replace function public.child_toggle(p_token text, p_routine uuid, p_day date, p_done boolean, p_source text default 'child')
 returns json language plpgsql security definer set search_path to ''
as $function$
declare d record; today date; r record;
begin
  select * into d from private.device_child(p_token);
  today := private.family_today(d.family_id);
  select * into r from public.routines where id = p_routine and child_id = d.child_id and active;
  if not found then raise exception 'SF:routine_not_found'; end if;
  if p_day < today - 2 or p_day > today then raise exception 'SF:day_locked'; end if;
  if r.kind = 'oneoff' and (p_day < r.start_day or p_day > r.end_day) then raise exception 'SF:oneoff_out_of_range'; end if;
  if p_done then
    insert into public.completions(family_id, child_id, routine_id, day, source)
    values (d.family_id, d.child_id, p_routine, p_day, case when p_source in ('child','timer') then p_source else 'child' end)
    on conflict (routine_id, day) do nothing;
  else
    if exists (select 1 from public.completions where routine_id = p_routine and day = p_day and validated_at is not null) then
      raise exception 'SF:validated_by_parent';
    end if;
    delete from public.completions where routine_id = p_routine and day = p_day and child_id = d.child_id and validated_at is null;
  end if;
  return json_build_object('ok', true);
end $function$;

create or replace function public.create_child_code(p_child uuid)
 returns text language plpgsql security definer set search_path to ''
as $function$
declare fid uuid; c text;
begin
  select family_id into fid from public.children where id = p_child;
  if fid is null or not private.is_parent(fid) then raise exception 'SF:device_parent_only'; end if;
  delete from public.child_device_codes where child_id = p_child or expires_at < now();
  c := private.random_code(6);
  insert into public.child_device_codes(code, child_id, family_id, expires_at) values (c, p_child, fid, now() + interval '15 minutes');
  return c;
end $function$;

create or replace function public.create_family(p_name text, p_display_name text, p_week_start smallint default 1, p_weekend smallint[] default '{6,7}'::smallint[], p_timezone text default 'Europe/Paris'::text)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare fid uuid; uid uuid := auth.uid(); ws smallint; we smallint[]; tz text;
begin
  if uid is null then raise exception 'SF:login_required'; end if;
  select family_id into fid from public.family_members where user_id = uid order by created_at limit 1;
  if fid is not null then return fid; end if;
  ws := case when p_week_start between 1 and 7 then p_week_start else 1 end;
  we := case when p_weekend is not null and p_weekend <@ array[1,2,3,4,5,6,7]::smallint[] and cardinality(p_weekend) <= 3
             then coalesce((select array_agg(distinct x order by x) from unnest(p_weekend) x), '{}') else '{6,7}' end;
  tz := case when private.valid_tz(p_timezone) then p_timezone else 'Europe/Paris' end;
  insert into public.families(name, week_start, weekend_days, timezone)
  values (coalesce(nullif(trim(p_name), ''), 'Ma famille'), ws, we, tz) returning id into fid;
  insert into public.family_members(family_id, user_id, role, display_name) values (fid, uid, 'parent', nullif(trim(p_display_name), ''));
  return fid;
end $function$;

create or replace function public.create_invite(p_family uuid, p_relation text default null::text, p_role text default 'parent'::text)
 returns text language plpgsql security definer set search_path to ''
as $function$
declare c text;
begin
  if not private.is_parent(p_family) then raise exception 'SF:invite_parent_only'; end if;
  if p_role not in ('parent','helper') then raise exception 'SF:unknown_role'; end if;
  delete from public.invites where family_id = p_family and (expires_at < now() or used_at is not null);
  c := private.random_code(6);
  insert into public.invites(code, family_id, created_by, expires_at, relation, role)
  values (c, p_family, auth.uid(), now() + interval '48 hours', nullif(trim(p_relation), ''), p_role);
  return c;
end $function$;

create or replace function public.family_gardens(p_family uuid)
 returns json language plpgsql security definer set search_path to ''
as $function$
declare res json;
begin
  if not private.is_member(p_family) then raise exception 'SF:access_denied'; end if;
  select coalesce(json_object_agg(c.id, private.garden_payload(c.id)), '{}'::json) into res
  from public.children c where c.family_id = p_family;
  return res;
end $function$;

create or replace function public.join_family(p_code text, p_display_name text)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare inv record; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'SF:login_required'; end if;
  select * into inv from public.invites where code = upper(trim(p_code)) and used_at is null and expires_at > now();
  if not found then raise exception 'SF:bad_code'; end if;
  insert into public.family_members(family_id, user_id, role, display_name, relation)
  values (inv.family_id, uid, inv.role, nullif(trim(p_display_name), ''), inv.relation)
  on conflict (family_id, user_id) do nothing;
  update public.invites set used_at = now() where code = inv.code;
  return inv.family_id;
end $function$;

-- 3. Abonnements aux rappels : langue de l'appareil --------------------------------------------
drop function if exists public.parent_push_subscribe(uuid, text, text, text, text[]);
create function public.parent_push_subscribe(p_family uuid, p_endpoint text, p_p256dh text, p_auth text, p_times text[], p_locale text default 'fr')
 returns void language plpgsql security definer set search_path to ''
as $function$
declare loc text := case when p_locale in ('fr', 'ar', 'en') then p_locale else 'fr' end;
begin
  if not private.is_member(p_family) then raise exception 'SF:access_denied'; end if;
  insert into public.push_subscriptions(family_id, user_id, child_device_id, endpoint, p256dh, auth, reminder_times, locale)
  values (p_family, auth.uid(), null, p_endpoint, p_p256dh, p_auth, p_times, loc)
  on conflict (endpoint) do update set family_id = excluded.family_id, user_id = excluded.user_id,
    child_device_id = null, p256dh = excluded.p256dh, auth = excluded.auth, reminder_times = excluded.reminder_times, locale = excluded.locale;
end $function$;
revoke execute on function public.parent_push_subscribe(uuid, text, text, text, text[], text) from public, anon;
grant execute on function public.parent_push_subscribe(uuid, text, text, text, text[], text) to authenticated;

drop function if exists public.child_push_subscribe(text, text, text, text, text[]);
create function public.child_push_subscribe(p_token text, p_endpoint text, p_p256dh text, p_auth text, p_times text[], p_locale text default 'fr')
 returns void language plpgsql security definer set search_path to ''
as $function$
declare d record; loc text := case when p_locale in ('fr', 'ar', 'en') then p_locale else 'fr' end;
begin
  select * into d from private.device_child(p_token);
  insert into public.push_subscriptions(family_id, user_id, child_device_id, endpoint, p256dh, auth, reminder_times, locale)
  values (d.family_id, null, d.device_id, p_endpoint, p_p256dh, p_auth, p_times, loc)
  on conflict (endpoint) do update set family_id = excluded.family_id, user_id = null,
    child_device_id = excluded.child_device_id, p256dh = excluded.p256dh, auth = excluded.auth, reminder_times = excluded.reminder_times, locale = excluded.locale;
end $function$;
grant execute on function public.child_push_subscribe(text, text, text, text, text[], text) to anon, authenticated;

-- Langue de l'appareil, modifiable sans réactiver les rappels
create or replace function public.push_set_locale(p_endpoint text, p_locale text)
 returns void language sql security definer set search_path to ''
as $$ update public.push_subscriptions set locale = p_locale where endpoint = p_endpoint and p_locale in ('fr', 'ar', 'en') $$;
grant execute on function public.push_set_locale(text, text) to anon, authenticated;

-- 4. Rappels : données brutes, le texte est composé par la fonction send-reminders --------------
create or replace function public.reminders_due(p_secret text) returns json
 language plpgsql security definer set search_path to ''
as $function$
declare items json;
begin
  if p_secret is null or p_secret is distinct from (select value from private.config where key = 'cron_secret') then
    raise exception 'SF:access_denied';
  end if;
  with fam as (
    select f.id, (now() at time zone f.timezone) as now_l from public.families f
  ),
  due as (
    select s.* from public.push_subscriptions s join fam on fam.id = s.family_id
    where exists (select 1 from unnest(s.reminder_times) t
                  where t ~ '^\d{2}:\d{2}$' and fam.now_l::time >= t::time and fam.now_l::time < t::time + interval '15 minutes')
  ),
  todo as (
    select c.id as child_id, c.family_id, c.name,
      count(r.id) filter (where r.days @> array[extract(isodow from fam.now_l)::smallint] and not r.is_bonus) as total,
      count(r.id) filter (where r.days @> array[extract(isodow from fam.now_l)::smallint] and not r.is_bonus
        and exists (select 1 from public.completions x where x.routine_id = r.id and x.day = fam.now_l::date)) as done,
      (select count(*) from public.completions x where x.child_id = c.id and x.validated_at is null) as pending
    from public.children c
    join fam on fam.id = c.family_id
    left join public.routines r on r.child_id = c.id and r.active
    group by c.id, fam.now_l
  )
  select coalesce(json_agg(json_build_object(
    'endpoint', d.endpoint, 'p256dh', d.p256dh, 'auth', d.auth, 'locale', d.locale,
    'kind', case when d.child_device_id is not null then 'child' else 'parent' end,
    'left', case when d.child_device_id is not null then
        (select t.total - t.done from todo t join public.child_devices cd on cd.child_id = t.child_id where cd.id = d.child_device_id) end,
    'children', case when d.child_device_id is null then
        (select json_agg(json_build_object('name', t.name, 'done', t.done, 'total', t.total, 'pending', t.pending) order by t.name)
         from todo t where t.family_id = d.family_id and (t.total > 0 or t.pending > 0)) end
  )), '[]'::json) into items from due d;
  return json_build_object(
    'vapid_public', (select value from private.config where key = 'vapid_public'),
    'vapid_private', (select value from private.config where key = 'vapid_private'),
    'subject', (select value from private.config where key = 'vapid_subject'),
    'items', items);
end $function$;

-- 5. Astuces du jour en arabe (traduction à faire relire) ----------------------------------------
insert into public.tips(text, locale) values
 ('امدحوا الجهد لا النتيجة: «أخذتَ وقتك لترتّب جيدًا» تحفّز أكثر من «أنت ولد مطيع».', 'ar'),
 ('تكفي ثلاثة إلى خمسة أنشطة في كل فترة من اليوم. أكثر من ذلك يفقد الطفل تركيزه.', 'ar'),
 ('اتركوا طفلكم يختار ترتيب أنشطته متى أمكن: يشعر بأنه صاحب القرار.', 'ar'),
 ('فضّلوا المكافآت المشتركة (قصة إضافية، اختيار الفيلم) على الأشياء: فهي تقوّي العلاقة.', 'ar'),
 ('النشاط المنسيّ ليس فشلًا. غدًا يوم جديد، بلا لوم.', 'ar'),
 ('كونوا قدوة: ترتيب سريركم في الوقت نفسه معه هو نصف الطريق.', 'ar'),
 ('صِفوا ما ترونه بدل الحكم: «أرى أن حذاءك في مكانه!»', 'ar'),
 ('للصغار، النشاط الواحد = فعل واحد. «تنظيف الأسنان» بدل «الاستعداد».', 'ar'),
 ('غيّروا المكافأة حين تفقد جاذبيتها. اسألوه عمّا يسعده.', 'ar'),
 ('المؤقّت يحوّل المهمة المملّة إلى تحدٍّ. استعملوه للأنشطة التي تتأخر.', 'ar'),
 ('في المساء، خذوا دقيقتين لتنظروا معًا إلى النبتة وتتحدثوا عن اليوم.', 'ar'),
 ('تجنّبوا سحب النجوم كعقاب: يجب أن تبقى النبتة مساحة إيجابية.', 'ar'),
 ('أضيفوا نشاطًا إضافيًا للتحديات الصغيرة: يمنح نجومًا دون ضغط.', 'ar'),
 ('أعلنوا الانتقالات مسبقًا: «بعد خمس دقائق، يحين وقت الاستحمام.»', 'ar'),
 ('حين يُتقن الطفل نشاطًا منذ أسابيع، احذفوه واحتفلوا: لقد كبر!', 'ar');

-- 6. Contrôles : en cas d'échec, l'erreur annule toute la migration -------------------------------
do $$
declare n int; r json;
begin
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname in ('public', 'private') and p.prosrc ~* 'raise exception ''(?!SF:)';
  if n > 0 then raise exception 'Contrôle : % fonction(s) avec un message non codé', n; end if;
  select count(*) into n from public.tips where locale = 'ar';
  if n < 15 then raise exception 'Contrôle : astuces arabes manquantes (%)', n; end if;
  r := public.reminders_due((select value from private.config where key = 'cron_secret'));
  if json_typeof(r -> 'items') <> 'array' then raise exception 'Contrôle : reminders_due ne renvoie pas de liste'; end if;
  select count(*) into n from pg_proc where proname in ('parent_push_subscribe', 'child_push_subscribe');
  if n <> 2 then raise exception 'Contrôle : % versions des fonctions d''abonnement (2 attendues)', n; end if;
end $$;

commit;
