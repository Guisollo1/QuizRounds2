-- QuizRounds v1.7
-- Retomada do jogador: rounds encerrados sem resposta contam como 0 ponto.
-- A identidade continua vinculada à sessão Auth anônima persistida no navegador.

create or replace function public.get_game_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_part public.quiz_participants;
  v_room public.quiz_rooms;
  v_round public.quiz_rounds;
  v_my public.quiz_answers;
  v_round_json jsonb;
  v_rank jsonb;
  v_now timestamptz:=clock_timestamp();
  v_closed_rounds integer:=0;
  v_answered_closed integer:=0;
  v_missed_rounds integer:=0;
begin
  select * into v_part from public.quiz_participants where room_id=p_room_id and user_id=v_uid;
  if not found then raise exception 'Participante não pertence à sala'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id;
  if not found then raise exception 'Sala não encontrada'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1;

  if found then
    select * into v_my from public.quiz_answers where round_id=v_round.id and participant_id=v_part.id;
    v_round_json:=jsonb_build_object(
      'id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,
      'closes_at',v_round.closes_at,'time_limit_seconds',v_round.time_limit_seconds,
      'accepting_responses',(v_room.phase='question_open' and v_round.status='open' and v_round.closes_at is not null and v_now<=v_round.closes_at),
      'prompt',v_round.prompt_snapshot,'question_type',v_round.question_type_snapshot,'options',coalesce(v_round.options_snapshot,'[]'::jsonb),
      'points',v_round.points_snapshot,'my_answer',case when v_my.id is null then null else to_jsonb(v_my) end,
      'result_text',case when v_round.status='closed' then v_round.result_text else null end
    );
  else
    v_round_json:=null;
  end if;

  if v_room.phase in ('result','finished') and v_round.id is not null and v_round.status='closed' then
    v_rank:=coalesce(v_round.ranking_snapshot,'[]'::jsonb);
  else
    select coalesce(r.ranking_snapshot,'[]'::jsonb) into v_rank
    from public.quiz_rounds r where r.room_id=p_room_id and r.status='closed' order by r.round_no desc limit 1;
    v_rank:=coalesce(v_rank,'[]'::jsonb);
  end if;

  select count(*) into v_closed_rounds
  from public.quiz_rounds r
  where r.room_id=p_room_id and r.status='closed';

  select count(*) into v_answered_closed
  from public.quiz_answers a
  join public.quiz_rounds r on r.id=a.round_id
  where a.participant_id=v_part.id and r.room_id=p_room_id and r.status='closed';

  v_missed_rounds:=greatest(0,v_closed_rounds-v_answered_closed);

  return jsonb_build_object(
    'room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'game_status',v_room.game_status,'phase',v_room.phase,'state_version',v_room.state_version),
    'round',v_round_json,'ranking',v_rank,'server_now',v_now,
    'closed_rounds',v_closed_rounds,'answered_closed_rounds',v_answered_closed,'missed_rounds',v_missed_rounds
  );
end $$;
revoke all on function public.get_game_state(uuid) from public, anon;
grant execute on function public.get_game_state(uuid) to authenticated;
