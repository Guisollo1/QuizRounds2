-- QuizRounds v3.16 — proteção contra troca acidental de sala e recuperação segura de fila.
-- Não altera a função estável admin_start_quiz. Adiciona apenas leitura da sala atual
-- por id e recuperação explícita da fila de uma sala anterior compatível.

create or replace function public.admin_get_room_by_id(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.quiz_rooms;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room
  from public.quiz_rooms
  where id=p_room_id and created_by=v_uid;
  if not found then return null; end if;
  return to_jsonb(v_room);
end
$$;
revoke all on function public.admin_get_room_by_id(uuid) from public,anon;
grant execute on function public.admin_get_room_by_id(uuid) to authenticated;

create or replace function public.admin_recover_queue_for_room(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := auth.uid();
  v_target public.quiz_rooms;
  v_source public.quiz_rooms;
  v_existing integer := 0;
  v_recovered integer := 0;
  v_q record;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;

  select * into v_target
  from public.quiz_rooms
  where id=p_room_id and created_by=v_uid
  for update;
  if not found then raise exception 'Sala atual inválida'; end if;
  if v_target.phase <> 'lobby' then raise exception 'A recuperação só pode ser feita no lobby'; end if;
  if exists(select 1 from public.quiz_rounds where room_id=p_room_id) then
    raise exception 'A sala já possui rounds iniciados';
  end if;

  select count(*) into v_existing
  from public.quiz_room_queue
  where room_id=p_room_id and status='queued';
  if v_existing > 0 then
    return jsonb_build_object('recovered',0,'reason','target_not_empty','current_queue',v_existing);
  end if;

  select r.* into v_source
  from public.quiz_rooms r
  where r.created_by=v_uid
    and r.id<>p_room_id
    and r.created_at < v_target.created_at
    and r.planned_rounds=v_target.planned_rounds
    and (select count(*) from public.quiz_room_queue q where q.room_id=r.id and q.status='queued')=v_target.planned_rounds
  order by r.created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('recovered',0,'reason','no_compatible_source');
  end if;

  for v_q in
    select rq.question_id
    from public.quiz_room_queue rq
    join public.quiz_questions q on q.id=rq.question_id
    where rq.room_id=v_source.id
      and rq.status='queued'
      and q.created_by=v_uid
      and q.active
      and q.archived_at is null
    order by rq.position
  loop
    perform public.admin_queue_question(p_room_id,v_q.question_id);
    v_recovered:=v_recovered+1;
  end loop;

  perform private.audit_event(
    p_room_id,v_uid,'queue_recovered','room',p_room_id,
    jsonb_build_object('source_room_id',v_source.id,'source_code',v_source.code,'count',v_recovered)
  );

  return jsonb_build_object(
    'recovered',v_recovered,
    'source_room_id',v_source.id,
    'source_code',v_source.code
  );
end
$$;
revoke all on function public.admin_recover_queue_for_room(uuid) from public,anon;
grant execute on function public.admin_recover_queue_for_room(uuid) to authenticated;
