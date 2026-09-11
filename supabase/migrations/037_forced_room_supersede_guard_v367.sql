-- QuizRounds v3.67 / r25
-- Separa o encerramento administrativo por substituição da proteção normal
-- que impede pular diretamente da pergunta para o fim da apresentação.

create or replace function private.quiz_hold_result_before_finish()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('quiz.allow_room_supersede', true) = 'on' then
    return new;
  end if;

  if old.phase = 'question_open' and new.phase in ('result','finished') then
    new.reveal_stage := 'hidden';
    if new.phase = 'finished' then
      new.phase := 'result';
      new.game_status := 'running';
      new.status := 'live';
      new.finished_at := null;
    end if;
  end if;
  return new;
end
$$;

revoke all on function private.quiz_hold_result_before_finish() from public;
revoke all on function private.quiz_hold_result_before_finish() from anon;
revoke all on function private.quiz_hold_result_before_finish() from authenticated;

create or replace function public.admin_create_room_v3(p_title text, p_planned_rounds integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.quiz_rooms;
  v_old record;
  v_code text;
  v_rounds integer := greatest(1, least(200, coalesce(p_planned_rounds, 10)));
begin
  if not private.is_admin(v_uid) then
    raise exception 'Acesso negado';
  end if;

  perform set_config('quiz.allow_room_supersede', 'on', true);

  for v_old in
    select r.id, r.code
    from public.quiz_rooms r
    where r.created_by = v_uid
      and r.status <> 'finished'
    order by r.created_at desc
    for update
  loop
    update public.quiz_rounds
       set status = 'closed',
           closed_at = coalesce(closed_at, clock_timestamp()),
           closes_at = least(coalesce(closes_at, clock_timestamp()), clock_timestamp()),
           annulled = true,
           result_locked = true,
           result_text = coalesce(nullif(result_text, ''), 'Round encerrado porque uma nova sala foi criada.')
     where room_id = v_old.id
       and status = 'open';

    update public.quiz_rooms
       set status = 'finished',
           game_status = 'finished',
           phase = 'finished',
           finished_at = coalesce(finished_at, clock_timestamp()),
           prepared_queue_id = null,
           prepared_until = null
     where id = v_old.id;

    perform private.audit_event(
      v_old.id,
      v_uid,
      'room_superseded',
      'room',
      v_old.id,
      jsonb_build_object('reason', 'new_room_created')
    );
    perform private.notify_room(v_old.id);
  end loop;

  perform set_config('quiz.allow_room_supersede', 'off', true);

  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists(select 1 from public.quiz_rooms where code = v_code);
  end loop;

  insert into public.quiz_rooms(code, title, created_by, status, planned_rounds, game_status, phase)
  values(v_code, coalesce(nullif(trim(p_title), ''), 'Quiz ao vivo'), v_uid, 'live', v_rounds, 'lobby', 'lobby')
  returning * into v_room;

  insert into public.quiz_realtime_memberships(user_id, room_id, role)
  values(v_uid, v_room.id, 'admin')
  on conflict do nothing;

  perform private.audit_event(
    v_room.id,
    v_uid,
    'room_created',
    'room',
    v_room.id,
    jsonb_build_object('planned_rounds', v_rounds, 'title', v_room.title)
  );
  perform private.publish_room_event(v_room.id, 'room_created', '{}'::jsonb);

  select * into v_room from public.quiz_rooms where id = v_room.id;
  return to_jsonb(v_room);
exception
  when others then
    perform set_config('quiz.allow_room_supersede', 'off', true);
    raise;
end
$$;

revoke all on function public.admin_create_room_v3(text, integer) from public;
revoke all on function public.admin_create_room_v3(text, integer) from anon;
grant execute on function public.admin_create_room_v3(text, integer) to authenticated;
