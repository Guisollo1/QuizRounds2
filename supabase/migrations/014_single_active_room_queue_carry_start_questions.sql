-- QuizRounds v3.17 — uma sala ativa por ADM, herança da fila e início por perguntas.
-- Objetivos:
-- 1) ao criar uma nova sala, encerrar qualquer sala anterior ativa do mesmo ADM;
-- 2) na criação normal, copiar a seleção/fila da sala anterior para a nova sala;
-- 3) permitir iniciar com qualquer quantidade >= 1 de perguntas, sem exigir participante prévio;
-- 4) sincronizar planned_rounds com a quantidade real de perguntas ao iniciar.

create or replace function public.admin_create_room_v3(p_title text,p_planned_rounds integer)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_old record;
  v_code text;
  v_rounds integer:=greatest(1,least(200,coalesce(p_planned_rounds,10)));
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;

  for v_old in
    select r.id,r.code
    from public.quiz_rooms r
    where r.created_by=v_uid
      and r.status<>'finished'
    order by r.created_at desc
    for update
  loop
    update public.quiz_rooms
    set status='finished',
        game_status='finished',
        phase='finished',
        finished_at=coalesce(finished_at,clock_timestamp())
    where id=v_old.id;

    perform private.audit_event(
      v_old.id,v_uid,'room_superseded','room',v_old.id,
      jsonb_build_object('reason','new_room_created')
    );
    perform private.notify_room(v_old.id);
  end loop;

  loop
    v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
    exit when not exists(select 1 from public.quiz_rooms where code=v_code);
  end loop;

  insert into public.quiz_rooms(code,title,created_by,status,planned_rounds,game_status,phase)
  values(v_code,coalesce(nullif(trim(p_title),''),'Quiz ao vivo'),v_uid,'live',v_rounds,'lobby','lobby')
  returning * into v_room;

  insert into public.quiz_realtime_memberships(user_id,room_id,role)
  values(v_uid,v_room.id,'admin') on conflict do nothing;

  perform private.audit_event(
    v_room.id,v_uid,'room_created','room',v_room.id,
    jsonb_build_object('planned_rounds',v_rounds,'title',v_room.title)
  );
  perform private.publish_room_event(v_room.id,'room_created','{}'::jsonb);

  select * into v_room from public.quiz_rooms where id=v_room.id;
  return to_jsonb(v_room);
end
$$;
revoke all on function public.admin_create_room_v3(text,integer) from public,anon;
grant execute on function public.admin_create_room_v3(text,integer) to authenticated;

create or replace function public.admin_create_room_v4(p_title text,p_planned_rounds integer)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_source public.quiz_rooms;
  v_created jsonb;
  v_new_id uuid;
  v_room public.quiz_rooms;
  v_q record;
  v_copied integer:=0;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;

  select * into v_source
  from public.quiz_rooms r
  where r.created_by=v_uid
    and r.status<>'finished'
  order by r.created_at desc
  limit 1;

  v_created:=public.admin_create_room_v3(p_title,p_planned_rounds);
  v_new_id:=(v_created->>'id')::uuid;

  if v_source.id is not null then
    for v_q in
      select rq.question_id
      from public.quiz_room_queue rq
      join public.quiz_questions q on q.id=rq.question_id
      where rq.room_id=v_source.id
        and q.created_by=v_uid
        and q.active
        and q.archived_at is null
      order by rq.position
      limit 200
    loop
      begin
        perform public.admin_queue_question(v_new_id,v_q.question_id);
        v_copied:=v_copied+1;
      exception when others then
        -- Uma pergunta inválida não deve impedir a criação da nova sala.
        null;
      end;
    end loop;
  end if;

  if v_copied>0 then
    update public.quiz_rooms
    set planned_rounds=v_copied
    where id=v_new_id;

    perform private.audit_event(
      v_new_id,v_uid,'queue_carried_from_previous_room','room',v_new_id,
      jsonb_build_object(
        'source_room_id',v_source.id,
        'source_code',v_source.code,
        'count',v_copied
      )
    );
  end if;

  select * into v_room from public.quiz_rooms where id=v_new_id;
  return to_jsonb(v_room)||jsonb_build_object(
    'carried_queue_count',v_copied,
    'source_room_id',v_source.id,
    'source_code',v_source.code
  );
end
$$;
revoke all on function public.admin_create_room_v4(text,integer) from public,anon;
grant execute on function public.admin_create_room_v4(text,integer) to authenticated;

create or replace function public.admin_start_quiz(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_count integer;
begin
  if not private.is_admin(v_uid) then
    raise exception 'Acesso negado';
  end if;

  select * into v_room
  from public.quiz_rooms
  where id=p_room_id and created_by=v_uid
  for update;

  if not found then
    raise exception 'Sala inválida';
  end if;

  if v_room.phase <> 'lobby' then
    return jsonb_build_object('already_applied',true,'phase',v_room.phase);
  end if;

  if exists(select 1 from public.quiz_rounds where room_id=p_room_id) then
    raise exception 'Esta sala já possui rounds iniciados';
  end if;

  select count(*) into v_count
  from public.quiz_room_queue
  where room_id=p_room_id
    and status='queued';

  if v_count < 1 then
    raise exception 'Adicione pelo menos 1 pergunta antes de começar';
  end if;

  update public.quiz_rooms
  set planned_rounds=v_count
  where id=p_room_id;

  if v_room.randomize_queue then
    perform private.shuffle_room_queue(p_room_id);
  end if;

  update public.quiz_rooms
  set status='live',
      game_status='running',
      started_at=clock_timestamp(),
      finished_at=null,
      final_ranking_snapshot=null,
      reveal_stage='hidden'
  where id=p_room_id;

  return public.admin_prepare_next_round(p_room_id);
end
$$;
revoke all on function public.admin_start_quiz(uuid) from public,anon;
grant execute on function public.admin_start_quiz(uuid) to authenticated;
