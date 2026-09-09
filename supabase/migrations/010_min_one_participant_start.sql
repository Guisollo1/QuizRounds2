-- QuizRounds v3.11 — iniciar somente com pelo menos 1 participante cadastrado.
-- Não cria limite máximo de participantes no fluxo de início.

create or replace function public.admin_start_quiz(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.quiz_rooms;
  v_count integer;
  v_participants integer;
begin
  if not private.is_admin(v_uid) then
    raise exception 'Acesso negado';
  end if;

  select * into v_room
  from public.quiz_rooms
  where id=p_room_id
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

  select count(*) into v_participants
  from public.quiz_participants
  where room_id=p_room_id
    and not kicked;

  if v_participants < 1 then
    raise exception 'Entre com pelo menos 1 participante no lobby antes de começar';
  end if;

  select count(*) into v_count
  from public.quiz_room_queue
  where room_id=p_room_id
    and status='queued';

  if v_count <> v_room.planned_rounds then
    raise exception 'Escolha exatamente a quantidade configurada de perguntas';
  end if;

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

revoke all on function public.admin_start_quiz(uuid) from public;
grant execute on function public.admin_start_quiz(uuid) to authenticated;
