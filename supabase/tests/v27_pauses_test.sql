-- Test de la migration v27_pauses : à coller dans l'éditeur SQL AVANT d'appliquer la migration.
-- Tout se passe dans une transaction annulée (famille et enfant fictifs, rien n'est conservé).
-- Résultat attendu (une seule ligne, message d'erreur « RESULT: … ») :
--  1.del_old=SF:pause_started 2.start_old=SF:pause_started 3.stop_old=OK 4.shrink_more=SF:pause_started
--  5.extend=OK 6.del_recent=OK 7.future=OK/OK 8.del_today=OK 9.cascade=OK left=0
begin;
do $t$
declare fid uuid; cid uuid; td date; p_old uuid; p_new uuid; p_fut uuid; res text := '';
begin
  create or replace function pg_temp.tryit(q text) returns text language plpgsql as $f$ begin execute q; return 'OK'; exception when others then return sqlerrm; end $f$;
  insert into public.families(name) values ('Famille test v27') returning id into fid;
  insert into public.children(family_id, name) values (fid, 'Enfant 1') returning id into cid;
  td := private.family_today(fid);
  execute $m$
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
create trigger pauses_check before update or delete on public.pauses for each row execute function private.pause_check();
$m$;
  -- commencée il y a 5 jours, créée il y a 3 jours (verrouillée)
  insert into public.pauses(family_id, child_id, start_day, end_day, reason, created_at) values (fid, cid, td-5, td+2, 'sick', now()-interval '3 days') returning id into p_old;
  -- commencée hier, créée il y a 2 h (dans les 24 h de grâce)
  insert into public.pauses(family_id, child_id, start_day, end_day, reason, created_at) values (fid, cid, td-1, td+2, 'trip', now()-interval '2 hours') returning id into p_new;
  -- à venir
  insert into public.pauses(family_id, child_id, start_day, end_day, reason) values (fid, cid, td+3, td+5, 'other') returning id into p_fut;
  res := res || ' 1.del_old=' || pg_temp.tryit(format('delete from public.pauses where id=%L', p_old));
  res := res || ' 2.start_old=' || pg_temp.tryit(format('update public.pauses set start_day=start_day-1 where id=%L', p_old));
  res := res || ' 3.stop_old=' || pg_temp.tryit(format('update public.pauses set end_day=%L where id=%L', td-1, p_old));
  res := res || ' 4.shrink_more=' || pg_temp.tryit(format('update public.pauses set end_day=%L where id=%L', td-2, p_old));
  res := res || ' 5.extend=' || pg_temp.tryit(format('update public.pauses set end_day=%L, reason=%L where id=%L', td+10, 'trip', p_old));
  res := res || ' 6.del_recent=' || pg_temp.tryit(format('delete from public.pauses where id=%L', p_new));
  res := res || ' 7.future=' || pg_temp.tryit(format('update public.pauses set start_day=%L where id=%L', td+4, p_fut)) || '/' || pg_temp.tryit(format('delete from public.pauses where id=%L', p_fut));
  -- commence aujourd'hui (pas encore « commencée »), créée il y a 3 jours
  insert into public.pauses(family_id, child_id, start_day, end_day, reason, created_at) values (fid, cid, td, td+1, 'sick', now()-interval '3 days') returning id into p_fut;
  res := res || ' 8.del_today=' || pg_temp.tryit(format('delete from public.pauses where id=%L', p_fut));
  -- suppression de l'enfant fictif : la cascade passe
  -- (deux instructions : un comptage dans la même instruction verrait l'état d'avant la suppression)
  res := res || ' 9.cascade=' || pg_temp.tryit(format('delete from public.children where id=%L', cid));
  res := res || ' left=' || (select count(*) from public.pauses where child_id = cid);
  raise exception 'RESULT:%', res;
end $t$;
rollback;
