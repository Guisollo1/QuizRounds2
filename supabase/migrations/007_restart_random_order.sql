-- QuizRounds v2.0
-- Reinício autoritativo da partida e ordem aleatória da fila, mantendo Supabase + GitHub Pages.

alter table public.quiz_rooms
  add column if not exists randomize_queue boolean not null default false;

create or replace function private.shuffle_room_queue(p_room_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare
  v_count integer:=0;
begin
  with shuffled as (
    select id,row_number() over(order by random(),id)::integer as new_position
    from public.quiz_room_queue
    where room_id=p_room_id and status='queued'
  )
  update public.quiz_room_queue q
  set position=s.new_position
  from shuffled s
  where q.id=s.id;
  get diagnostics v_count=row_count;
  return v_count;
end $$;
revoke all on function private.shuffle_room_queue(uuid) from public;

create or replace function public.admin_set_randomize_queue(p_room_id uuid,p_enabled boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.phase<>'lobby' then raise exception 'A ordem aleatória só pode ser alterada antes do início'; end if;
  update public.quiz_rooms set randomize_queue=coalesce(p_enabled,false) where id=p_room_id;
  perform private.audit_event(p_room_id,v_uid,'random_order_changed','room',p_room_id,jsonb_build_object('enabled',coalesce(p_enabled,false)));
  perform private.publish_room_event(p_room_id,'room_config_changed',jsonb_build_object('randomize_queue',coalesce(p_enabled,false)));
  return coalesce(p_enabled,false);
end $$;
revoke all on function public.admin_set_randomize_queue(uuid,boolean) from public;
grant execute on function public.admin_set_randomize_queue(uuid,boolean) to authenticated;

create or replace function public.admin_shuffle_queue(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_count integer:=0;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.phase<>'lobby' then raise exception 'A fila só pode ser embaralhada antes do início'; end if;
  select count(*) into v_count from public.quiz_room_queue where room_id=p_room_id and status='queued';
  if v_count<2 then raise exception 'Escolha pelo menos duas perguntas para embaralhar'; end if;
  perform private.shuffle_room_queue(p_room_id);
  perform private.audit_event(p_room_id,v_uid,'queue_shuffled','room',p_room_id,jsonb_build_object('count',v_count,'automatic',false));
  perform private.publish_room_event(p_room_id,'queue_shuffled',jsonb_build_object('count',v_count));
  return jsonb_build_object('shuffled',true,'count',v_count);
end $$;
revoke all on function public.admin_shuffle_queue(uuid) from public;
grant execute on function public.admin_shuffle_queue(uuid) to authenticated;

create or replace function private.protect_closed_round()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status='closed' and coalesce(current_setting('quiz.allow_round_reset',true),'off')<>'on' then
    raise exception 'Round encerrado é imutável';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function private.protect_closed_round() from public;

create or replace function public.admin_start_quiz(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_count integer;
  v_round public.quiz_rounds;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala inválida'; end if;

  if v_room.phase<>'lobby' then
    select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1;
    return jsonb_build_object('already_applied',true,'phase',v_room.phase,'round',case when v_round.id is null then null else to_jsonb(v_round) end);
  end if;

  if exists(select 1 from public.quiz_rounds where room_id=p_room_id) then raise exception 'Esta sala já possui rounds iniciados'; end if;
  select count(*) into v_count from public.quiz_room_queue where room_id=p_room_id and status='queued';
  if v_count<>v_room.planned_rounds then raise exception 'Escolha exatamente a quantidade configurada de perguntas antes de começar'; end if;

  if v_room.randomize_queue then
    perform private.shuffle_room_queue(p_room_id);
    perform private.audit_event(p_room_id,v_uid,'queue_shuffled','room',p_room_id,jsonb_build_object('count',v_count,'automatic',true));
  end if;

  update public.quiz_rooms set status='live',game_status='running',phase='question_open',started_at=clock_timestamp(),finished_at=null,final_ranking_snapshot=null where id=p_room_id;
  select * into v_round from private.open_round_from_queue(p_room_id,1);
  perform private.audit_event(p_room_id,v_uid,'quiz_started','round',v_round.id,jsonb_build_object('round_no',1,'randomized',v_room.randomize_queue));
  perform private.publish_room_event(p_room_id,'round_opened',jsonb_build_object('round_no',1,'randomized',v_room.randomize_queue));
  return jsonb_build_object('already_applied',false,'phase','question_open','round',to_jsonb(v_round),'randomized',v_room.randomize_queue);
end $$;
revoke all on function public.admin_start_quiz(uuid) from public;
grant execute on function public.admin_start_quiz(uuid) to authenticated;

create or replace function public.admin_restart_quiz(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_round public.quiz_rounds;
  v_count integer:=0;
  v_previous_phase text;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala não encontrada'; end if;
  v_previous_phase:=v_room.phase;

  select count(*) into v_count from public.quiz_room_queue where room_id=p_room_id;
  if v_count<>v_room.planned_rounds then raise exception 'A fila precisa conter exatamente a quantidade configurada de perguntas'; end if;
  if not exists(select 1 from public.quiz_rounds where room_id=p_room_id) then raise exception 'A partida ainda não foi iniciada'; end if;

  perform set_config('quiz.allow_round_reset','on',true);
  delete from public.quiz_rounds where room_id=p_room_id;
  perform set_config('quiz.allow_round_reset','off',true);

  update public.quiz_room_queue
  set status='queued',round_id=null,used_at=null
  where room_id=p_room_id;

  update public.quiz_participants
  set total_points=0
  where room_id=p_room_id;

  if v_room.randomize_queue then
    perform private.shuffle_room_queue(p_room_id);
  end if;

  update public.quiz_rooms
  set status='live',game_status='running',phase='question_open',started_at=clock_timestamp(),finished_at=null,final_ranking_snapshot=null
  where id=p_room_id;

  select * into v_round from private.open_round_from_queue(p_room_id,1);
  perform private.audit_event(p_room_id,v_uid,'quiz_restarted','round',v_round.id,jsonb_build_object('round_no',1,'previous_phase',v_previous_phase,'randomized',v_room.randomize_queue));
  perform private.publish_room_event(p_room_id,'quiz_restarted',jsonb_build_object('round_no',1,'randomized',v_room.randomize_queue));
  return jsonb_build_object('restarted',true,'phase','question_open','round',to_jsonb(v_round),'randomized',v_room.randomize_queue);
exception when others then
  perform set_config('quiz.allow_round_reset','off',true);
  raise;
end $$;
revoke all on function public.admin_restart_quiz(uuid) from public;
grant execute on function public.admin_restart_quiz(uuid) to authenticated;

create or replace function public.admin_get_latest_room()
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room
  from public.quiz_rooms
  where created_by=v_uid
  order by created_at desc
  limit 1;
  if not found then return null; end if;
  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at)
  values(v_uid,v_room.id,'admin',clock_timestamp())
  on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;
  return to_jsonb(v_room);
end $$;
revoke all on function public.admin_get_latest_room() from public;
grant execute on function public.admin_get_latest_room() to authenticated;

create or replace function public.admin_get_room_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_round public.quiz_rounds;
  v_round_json jsonb;
  v_rank jsonb;
  v_now timestamptz:=clock_timestamp();
  v_participants integer:=0;
  v_active integer:=0;
  v_answers integer:=0;
  v_used integer:=0;
  v_queued integer:=0;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id;
  if not found then raise exception 'Sala não encontrada'; end if;
  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at)
  values(v_uid,p_room_id,'admin',v_now)
  on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;

  select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1;
  if found then
    v_round_json:=jsonb_build_object(
      'id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,'closed_at',v_round.closed_at,
      'result_text',v_round.result_text,'time_limit_seconds',v_round.time_limit_seconds,'closes_at',v_round.closes_at,
      'accepting_responses',(v_room.phase='question_open' and v_round.status='open' and v_round.closes_at is not null and v_now<=v_round.closes_at),
      'prompt',v_round.prompt_snapshot,'question_type',v_round.question_type_snapshot,'options',coalesce(v_round.options_snapshot,'[]'::jsonb),'points',v_round.points_snapshot,
      'answer_count_snapshot',v_round.answer_count_snapshot,'winner_snapshot',v_round.winner_snapshot
    );
  end if;

  if v_room.phase in ('result','finished') and v_round.id is not null then
    v_rank:=coalesce(v_round.ranking_snapshot,v_room.final_ranking_snapshot,'[]'::jsonb);
  else
    select coalesce(r.ranking_snapshot,'[]'::jsonb) into v_rank
    from public.quiz_rounds r where r.room_id=p_room_id and r.status='closed' order by r.round_no desc limit 1;
    v_rank:=coalesce(v_rank,'[]'::jsonb);
  end if;

  select count(*) into v_participants from public.quiz_participants where room_id=p_room_id;
  select count(*) into v_active from public.quiz_participants where room_id=p_room_id and last_seen_at>=v_now-interval '90 seconds';
  select count(*) into v_used from public.quiz_rounds where room_id=p_room_id;
  select count(*) into v_queued from public.quiz_room_queue where room_id=p_room_id and status='queued';
  if v_round.id is not null and v_round.status='open' then select count(*) into v_answers from public.quiz_answers where round_id=v_round.id; else v_answers:=coalesce(v_round.answer_count_snapshot,0); end if;

  return jsonb_build_object(
    'room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'game_status',v_room.game_status,'phase',v_room.phase,'state_version',v_room.state_version,'started_at',v_room.started_at,'finished_at',v_room.finished_at,'randomize_queue',v_room.randomize_queue),
    'round',v_round_json,'ranking',v_rank,'participant_count',v_participants,'active_count',v_active,'answer_count',v_answers,
    'used_rounds',v_used,'queued_count',v_queued,'server_now',v_now
  );
end $$;
revoke all on function public.admin_get_room_state(uuid) from public;
grant execute on function public.admin_get_room_state(uuid) to authenticated;
