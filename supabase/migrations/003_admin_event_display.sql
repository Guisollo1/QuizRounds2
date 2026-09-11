-- Quiz Rounds v1.2: fluxo de evento, quantidade fixa de rounds e tela pública de perguntas.

alter table public.quiz_rooms
  add column if not exists planned_rounds integer not null default 10 check (planned_rounds between 1 and 200),
  add column if not exists game_status text not null default 'lobby' check (game_status in ('setup','lobby','running','finished')),
  add column if not exists started_at timestamptz,
  add column if not exists finished_at timestamptz;

update public.quiz_rooms
set game_status=case when status='finished' then 'finished' else coalesce(game_status,'lobby') end,
    finished_at=case when status='finished' then coalesce(finished_at,created_at) else finished_at end;

create or replace function public.admin_create_room_v3(p_title text,p_planned_rounds integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_code text;
  v_rounds integer:=greatest(1,least(200,coalesce(p_planned_rounds,10)));
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  loop
    v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
    exit when not exists(select 1 from public.quiz_rooms where code=v_code);
  end loop;
  insert into public.quiz_rooms(code,title,created_by,status,planned_rounds,game_status)
  values(v_code,coalesce(nullif(trim(p_title),''),'Quiz ao vivo'),v_uid,'live',v_rounds,'lobby')
  returning * into v_room;
  perform private.notify_room(v_room.id);
  return to_jsonb(v_room);
end $$;
revoke all on function public.admin_create_room_v3(text,integer) from public;
grant execute on function public.admin_create_room_v3(text,integer) to authenticated;

create or replace function public.admin_update_planned_rounds(p_room_id uuid,p_planned_rounds integer)
returns integer language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_rounds integer:=greatest(1,least(200,coalesce(p_planned_rounds,10)));
  v_selected integer:=0;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.game_status not in ('setup','lobby') then raise exception 'A quantidade de rounds fica bloqueada depois do início'; end if;
  select count(*) into v_selected from public.quiz_room_queue where room_id=p_room_id;
  if v_rounds<v_selected then raise exception 'Remova perguntas antes de reduzir a quantidade de rounds'; end if;
  update public.quiz_rooms set planned_rounds=v_rounds where id=p_room_id;
  perform private.notify_room(p_room_id);
  return v_rounds;
end $$;
revoke all on function public.admin_update_planned_rounds(uuid,integer) from public;
grant execute on function public.admin_update_planned_rounds(uuid,integer) to authenticated;

create or replace function public.admin_queue_question(p_room_id uuid,p_question_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_id uuid;
  v_pos integer;
  v_room public.quiz_rooms;
  v_count integer;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found or v_room.status='finished' then raise exception 'Sala inválida'; end if;
  if v_room.game_status not in ('setup','lobby') then raise exception 'As perguntas ficam bloqueadas depois que o quiz começa'; end if;
  if not exists(select 1 from public.quiz_questions where id=p_question_id and active and archived_at is null) then raise exception 'Pergunta indisponível ou arquivada'; end if;
  if exists(select 1 from public.quiz_room_queue where room_id=p_room_id and question_id=p_question_id) then raise exception 'Esta pergunta já foi escolhida'; end if;
  select count(*) into v_count from public.quiz_room_queue where room_id=p_room_id;
  if v_count>=v_room.planned_rounds then raise exception 'A quantidade de perguntas já atingiu o número de rounds'; end if;
  select coalesce(max(position),0)+1 into v_pos from public.quiz_room_queue where room_id=p_room_id;
  insert into public.quiz_room_queue(room_id,question_id,position)
  values(p_room_id,p_question_id,v_pos)
  returning id into v_id;
  perform private.notify_room(p_room_id);
  return v_id;
end $$;
revoke all on function public.admin_queue_question(uuid,uuid) from public;
grant execute on function public.admin_queue_question(uuid,uuid) to authenticated;

create or replace function public.admin_remove_queue_item(p_room_id uuid,p_queue_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_status text;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select game_status into v_status from public.quiz_rooms where id=p_room_id;
  if v_status not in ('setup','lobby') then raise exception 'A lista de rounds está bloqueada'; end if;
  delete from public.quiz_room_queue where id=p_queue_id and room_id=p_room_id and status='queued';
  if not found then raise exception 'Item não pode ser removido'; end if;
  perform private.notify_room(p_room_id);
end $$;
revoke all on function public.admin_remove_queue_item(uuid,uuid) from public;
grant execute on function public.admin_remove_queue_item(uuid,uuid) to authenticated;

create or replace function public.admin_move_queue_item(p_room_id uuid,p_queue_id uuid,p_direction integer)
returns void language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_status text;
  v_cur public.quiz_room_queue;
  v_other public.quiz_room_queue;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_direction not in (-1,1) then raise exception 'Direção inválida'; end if;
  select game_status into v_status from public.quiz_rooms where id=p_room_id;
  if v_status not in ('setup','lobby') then raise exception 'A ordem dos rounds está bloqueada'; end if;
  select * into v_cur from public.quiz_room_queue where id=p_queue_id and room_id=p_room_id and status='queued';
  if not found then raise exception 'Item não encontrado'; end if;
  if p_direction=-1 then
    select * into v_other from public.quiz_room_queue where room_id=p_room_id and status='queued' and position<v_cur.position order by position desc,added_at desc limit 1;
  else
    select * into v_other from public.quiz_room_queue where room_id=p_room_id and status='queued' and position>v_cur.position order by position asc,added_at asc limit 1;
  end if;
  if found then
    update public.quiz_room_queue set position=v_other.position where id=v_cur.id;
    update public.quiz_room_queue set position=v_cur.position where id=v_other.id;
    perform private.notify_room(p_room_id);
  end if;
end $$;
revoke all on function public.admin_move_queue_item(uuid,uuid,integer) from public;
grant execute on function public.admin_move_queue_item(uuid,uuid,integer) to authenticated;

create or replace function public.admin_start_quiz(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_count integer;
  v_item public.quiz_room_queue;
  v_q public.quiz_questions;
  v_r public.quiz_rounds;
  v_now timestamptz:=clock_timestamp();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found or v_room.status='finished' then raise exception 'Sala inválida'; end if;
  if v_room.game_status not in ('setup','lobby') then raise exception 'O quiz já foi iniciado'; end if;
  if exists(select 1 from public.quiz_rounds where room_id=p_room_id) then raise exception 'Esta sala já possui rounds iniciados'; end if;
  select count(*) into v_count from public.quiz_room_queue where room_id=p_room_id and status='queued';
  if v_count<v_room.planned_rounds then raise exception 'Escolha todas as perguntas antes de começar'; end if;
  update public.quiz_rooms set game_status='running',started_at=v_now where id=p_room_id;
  select * into v_item from public.quiz_room_queue where room_id=p_room_id and status='queued' order by position asc,added_at asc limit 1 for update;
  select * into v_q from public.quiz_questions where id=v_item.question_id and active;
  if not found then raise exception 'A primeira pergunta não está disponível'; end if;
  insert into public.quiz_rounds(room_id,question_id,round_no,status,opened_at,time_limit_seconds,closes_at)
  values(p_room_id,v_q.id,1,'open',v_now,v_q.time_limit_seconds,v_now+make_interval(secs=>v_q.time_limit_seconds))
  returning * into v_r;
  update public.quiz_room_queue set status='used',round_id=v_r.id,used_at=v_now where id=v_item.id;
  perform private.notify_room(p_room_id);
  return to_jsonb(v_r);
end $$;
revoke all on function public.admin_start_quiz(uuid) from public;
grant execute on function public.admin_start_quiz(uuid) to authenticated;

create or replace function public.admin_open_next_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_no integer;
  v_r public.quiz_rounds;
  v_item public.quiz_room_queue;
  v_q public.quiz_questions;
  v_now timestamptz:=clock_timestamp();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found or v_room.status='finished' or v_room.game_status<>'running' then raise exception 'Quiz não está em execução'; end if;
  if exists(select 1 from public.quiz_rounds where room_id=p_room_id and status='open') then raise exception 'Já existe um round aberto'; end if;
  select coalesce(max(round_no),0)+1 into v_no from public.quiz_rounds where room_id=p_room_id;
  if v_no>v_room.planned_rounds then raise exception 'Todos os rounds configurados já foram usados'; end if;
  select * into v_item from public.quiz_room_queue where room_id=p_room_id and status='queued' order by position asc,added_at asc limit 1 for update skip locked;
  if not found then raise exception 'A fila de rounds está vazia'; end if;
  select * into v_q from public.quiz_questions where id=v_item.question_id and active;
  if not found then raise exception 'Pergunta da fila não está disponível'; end if;
  insert into public.quiz_rounds(room_id,question_id,round_no,status,opened_at,time_limit_seconds,closes_at)
  values(p_room_id,v_q.id,v_no,'open',v_now,v_q.time_limit_seconds,v_now+make_interval(secs=>v_q.time_limit_seconds))
  returning * into v_r;
  update public.quiz_room_queue set status='used',round_id=v_r.id,used_at=v_now where id=v_item.id;
  perform private.notify_room(p_room_id);
  return to_jsonb(v_r);
end $$;
revoke all on function public.admin_open_next_round(uuid) from public;
grant execute on function public.admin_open_next_round(uuid) to authenticated;

create or replace function public.admin_close_and_score_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_r public.quiz_rounds;
  v_q public.quiz_questions;
  v_k private.quiz_answer_keys;
  v_count integer:=0;
  v_round_count integer:=0;
  v_winner uuid;
  v_correct_text text;
  v_result text;
  v_finished boolean:=false;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala inválida'; end if;
  select * into v_r from public.quiz_rounds where room_id=p_room_id and status='open' order by round_no desc limit 1 for update;
  if not found then raise exception 'Nenhum round aberto'; end if;
  select * into v_q from public.quiz_questions where id=v_r.question_id;
  select * into v_k from private.quiz_answer_keys where question_id=v_q.id;
  update public.quiz_answers set awarded_points=0 where round_id=v_r.id;
  if v_q.question_type='choice' then
    update public.quiz_answers set awarded_points=v_q.points where round_id=v_r.id and choice_value=v_k.correct_choice;
    select x->>'text' into v_correct_text from jsonb_array_elements(coalesce(v_q.options,'[]'::jsonb)) x where x->>'key'=v_k.correct_choice limit 1;
    v_result:='Resposta correta: '||v_k.correct_choice||case when v_correct_text is null then '' else ' — '||v_correct_text end;
  else
    select a.id into v_winner from public.quiz_answers a where a.round_id=v_r.id order by abs(a.numeric_value-v_k.correct_number) asc,a.response_ms asc,a.submitted_at asc limit 1;
    if v_winner is not null then update public.quiz_answers set awarded_points=v_q.points where id=v_winner; end if;
    v_result:='Valor correto: '||v_k.correct_number::text;
  end if;
  update public.quiz_participants p
  set total_points=(select coalesce(sum(a.awarded_points),0)::integer from public.quiz_answers a join public.quiz_rounds rr on rr.id=a.round_id where a.participant_id=p.id and rr.room_id=p_room_id)
  where p.room_id=p_room_id;
  select count(*) into v_count from public.quiz_answers where round_id=v_r.id;
  update public.quiz_rounds set status='closed',closed_at=clock_timestamp(),result_text=v_result where id=v_r.id;
  select count(*) into v_round_count from public.quiz_rounds where room_id=p_room_id;
  if v_round_count>=v_room.planned_rounds then
    update public.quiz_rooms set game_status='finished',status='finished',finished_at=clock_timestamp() where id=p_room_id;
    v_finished:=true;
  end if;
  perform private.notify_room(p_room_id);
  return jsonb_build_object('round_id',v_r.id,'answers',v_count,'finished',v_finished,'result_text',v_result);
end $$;
revoke all on function public.admin_close_and_score_round(uuid) from public;
grant execute on function public.admin_close_and_score_round(uuid) to authenticated;

create or replace function public.get_game_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_part public.quiz_participants;
  v_room public.quiz_rooms;
  v_round public.quiz_rounds;
  v_q public.quiz_questions;
  v_my public.quiz_answers;
  v_round_json jsonb;
  v_rank jsonb;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_part from public.quiz_participants where room_id=p_room_id and user_id=v_uid;
  if not found then raise exception 'Participante não pertence à sala'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id;
  if not found then raise exception 'Sala não encontrada'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1;
  if found then
    select * into v_q from public.quiz_questions where id=v_round.question_id;
    select * into v_my from public.quiz_answers where round_id=v_round.id and participant_id=v_part.id;
    v_round_json:=jsonb_build_object(
      'id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,
      'closes_at',v_round.closes_at,'time_limit_seconds',v_round.time_limit_seconds,
      'accepting_responses',(v_room.game_status='running' and v_round.status='open' and v_round.closes_at is not null and v_now<=v_round.closes_at),
      'prompt',v_q.prompt,'question_type',v_q.question_type,'options',coalesce(v_q.options,'[]'::jsonb),
      'points',v_q.points,'my_answer',case when v_my.id is null then null else to_jsonb(v_my) end,
      'result_text',case when v_round.status='closed' then v_round.result_text else null end
    );
  else
    v_round_json:=null;
  end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_points desc,x.joined_at asc),'[]'::jsonb)
  into v_rank from (select display_name,total_points,joined_at from public.quiz_participants where room_id=p_room_id order by total_points desc,joined_at asc limit 200) x;
  return jsonb_build_object(
    'room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'game_status',v_room.game_status),
    'round',v_round_json,'ranking',v_rank,'server_now',v_now
  );
end $$;
revoke all on function public.get_game_state(uuid) from public;
grant execute on function public.get_game_state(uuid) to authenticated;

create or replace function public.admin_get_room_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_round_json jsonb;
  v_rank jsonb;
  v_now timestamptz:=clock_timestamp();
  v_participants integer:=0;
  v_answers integer:=0;
  v_used integer:=0;
  v_queued integer:=0;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id;
  if not found then raise exception 'Sala não encontrada'; end if;
  select jsonb_build_object(
    'id',r.id,'round_no',r.round_no,'status',r.status,'opened_at',r.opened_at,'closed_at',r.closed_at,
    'result_text',r.result_text,'time_limit_seconds',r.time_limit_seconds,'closes_at',r.closes_at,
    'accepting_responses',(v_room.game_status='running' and r.status='open' and r.closes_at is not null and v_now<=r.closes_at),
    'prompt',q.prompt,'question_type',q.question_type,'options',coalesce(q.options,'[]'::jsonb),'points',q.points
  ) into v_round_json
  from public.quiz_rounds r join public.quiz_questions q on q.id=r.question_id
  where r.room_id=p_room_id order by r.round_no desc limit 1;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_points desc,x.joined_at asc),'[]'::jsonb)
  into v_rank from (select display_name,total_points,joined_at from public.quiz_participants where room_id=p_room_id order by total_points desc,joined_at asc limit 200) x;
  select count(*) into v_participants from public.quiz_participants where room_id=p_room_id;
  select count(*) into v_used from public.quiz_rounds where room_id=p_room_id;
  select count(*) into v_queued from public.quiz_room_queue where room_id=p_room_id and status='queued';
  if v_round_json is not null then select count(*) into v_answers from public.quiz_answers where round_id=(v_round_json->>'id')::uuid; end if;
  return jsonb_build_object(
    'room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'game_status',v_room.game_status,'started_at',v_room.started_at,'finished_at',v_room.finished_at),
    'round',v_round_json,'ranking',v_rank,'participant_count',v_participants,'answer_count',v_answers,
    'used_rounds',v_used,'queued_count',v_queued,'server_now',v_now
  );
end $$;
revoke all on function public.admin_get_room_state(uuid) from public;
grant execute on function public.admin_get_room_state(uuid) to authenticated;

create or replace function public.get_public_display_state(p_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_room public.quiz_rooms;
  v_round_json jsonb;
  v_rank jsonb;
  v_now timestamptz:=clock_timestamp();
  v_participants integer:=0;
  v_answers integer:=0;
  v_used integer:=0;
begin
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;
  select jsonb_build_object(
    'id',r.id,'round_no',r.round_no,'status',r.status,'opened_at',r.opened_at,'closed_at',r.closed_at,
    'closes_at',r.closes_at,'time_limit_seconds',r.time_limit_seconds,
    'prompt',q.prompt,'question_type',q.question_type,'options',coalesce(q.options,'[]'::jsonb),'points',q.points,
    'result_text',case when r.status='closed' then r.result_text else null end
  ) into v_round_json
  from public.quiz_rounds r join public.quiz_questions q on q.id=r.question_id
  where r.room_id=v_room.id order by r.round_no desc limit 1;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_points desc,x.joined_at asc),'[]'::jsonb)
  into v_rank from (select display_name,total_points,joined_at from public.quiz_participants where room_id=v_room.id order by total_points desc,joined_at asc limit 20) x;
  select count(*) into v_participants from public.quiz_participants where room_id=v_room.id;
  select count(*) into v_used from public.quiz_rounds where room_id=v_room.id;
  if v_round_json is not null then select count(*) into v_answers from public.quiz_answers where round_id=(v_round_json->>'id')::uuid; end if;
  return jsonb_build_object(
    'room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'game_status',v_room.game_status),
    'round',v_round_json,'ranking',v_rank,'participant_count',v_participants,'answer_count',v_answers,'used_rounds',v_used,'server_now',v_now
  );
end $$;
revoke all on function public.get_public_display_state(text) from public;
grant execute on function public.get_public_display_state(text) to anon, authenticated;

grant usage on schema public to anon, authenticated;
