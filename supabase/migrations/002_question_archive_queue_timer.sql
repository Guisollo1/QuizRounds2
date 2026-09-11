-- Quiz Rounds v1.1: arquivo de perguntas, fila por sala e limite de tempo no servidor.

alter table public.quiz_questions
  add column if not exists time_limit_seconds integer not null default 30 check (time_limit_seconds between 5 and 600),
  add column if not exists archived_at timestamptz;

alter table public.quiz_rounds
  add column if not exists time_limit_seconds integer,
  add column if not exists closes_at timestamptz;

update public.quiz_rounds r
set time_limit_seconds = coalesce(r.time_limit_seconds, q.time_limit_seconds, 30),
    closes_at = coalesce(r.closes_at, r.opened_at + make_interval(secs => coalesce(q.time_limit_seconds, 30)))
from public.quiz_questions q
where q.id = r.question_id
  and (r.time_limit_seconds is null or r.closes_at is null);

alter table public.quiz_rounds alter column time_limit_seconds set default 30;
alter table public.quiz_rounds alter column time_limit_seconds set not null;

create table if not exists public.quiz_room_queue (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.quiz_rooms(id) on delete cascade,
  question_id uuid not null references public.quiz_questions(id),
  position integer not null check (position > 0),
  status text not null default 'queued' check (status in ('queued','used')),
  round_id uuid references public.quiz_rounds(id) on delete set null,
  added_at timestamptz not null default now(),
  used_at timestamptz,
  unique(room_id, question_id)
);
create index if not exists quiz_room_queue_room_position_idx on public.quiz_room_queue(room_id,status,position,added_at);
alter table public.quiz_room_queue enable row level security;
revoke all on public.quiz_room_queue from anon, authenticated;

create or replace function public.admin_create_question_v2(
  p_prompt text,
  p_type text,
  p_options jsonb,
  p_correct_choice text,
  p_correct_number numeric,
  p_points integer,
  p_time_limit integer
)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_id uuid; v_limit integer;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if length(trim(coalesce(p_prompt,''))) < 1 then raise exception 'Pergunta obrigatória'; end if;
  if p_type not in ('choice','numeric') then raise exception 'Tipo inválido'; end if;
  v_limit:=greatest(5,least(600,coalesce(p_time_limit,30)));
  if p_type='choice' then
    if jsonb_typeof(p_options)<>'array' or jsonb_array_length(p_options)<>4 or p_correct_choice not in ('A','B','C','D') then raise exception 'Alternativas inválidas'; end if;
    p_correct_number:=null;
  else
    if p_correct_number is null then raise exception 'Valor correto obrigatório'; end if;
    p_options:=null; p_correct_choice:=null;
  end if;
  insert into public.quiz_questions(created_by,prompt,question_type,options,points,time_limit_seconds)
  values(v_uid,trim(p_prompt),p_type,p_options,greatest(1,least(100000,coalesce(p_points,1000))),v_limit)
  returning id into v_id;
  insert into private.quiz_answer_keys(question_id,correct_choice,correct_number)
  values(v_id,p_correct_choice,p_correct_number);
  return v_id;
end $$;
revoke all on function public.admin_create_question_v2(text,text,jsonb,text,numeric,integer,integer) from public;
grant execute on function public.admin_create_question_v2(text,text,jsonb,text,numeric,integer,integer) to authenticated;

create or replace function public.admin_list_question_bank(p_scope text default 'active')
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_result jsonb; v_scope text:=lower(coalesce(p_scope,'active'));
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if v_scope not in ('active','archived','all') then v_scope:='active'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'prompt',q.prompt,'question_type',q.question_type,'options',q.options,
    'points',q.points,'time_limit_seconds',q.time_limit_seconds,
    'correct_choice',k.correct_choice,'correct_number',k.correct_number,
    'archived',q.archived_at is not null,'archived_at',q.archived_at,'created_at',q.created_at
  ) order by q.created_at desc),'[]'::jsonb)
  into v_result
  from public.quiz_questions q
  join private.quiz_answer_keys k on k.question_id=q.id
  where q.active
    and (v_scope='all' or (v_scope='active' and q.archived_at is null) or (v_scope='archived' and q.archived_at is not null));
  return v_result;
end $$;
revoke all on function public.admin_list_question_bank(text) from public;
grant execute on function public.admin_list_question_bank(text) to authenticated;

create or replace function public.admin_set_question_archived(p_question_id uuid,p_archived boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  update public.quiz_questions
  set archived_at=case when coalesce(p_archived,false) then coalesce(archived_at,clock_timestamp()) else null end
  where id=p_question_id and active;
  if not found then raise exception 'Pergunta não encontrada'; end if;
end $$;
revoke all on function public.admin_set_question_archived(uuid,boolean) from public;
grant execute on function public.admin_set_question_archived(uuid,boolean) to authenticated;

create or replace function public.admin_queue_question(p_room_id uuid,p_question_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_id uuid; v_pos integer;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if not exists(select 1 from public.quiz_rooms where id=p_room_id and status<>'finished') then raise exception 'Sala inválida'; end if;
  if not exists(select 1 from public.quiz_questions where id=p_question_id and active) then raise exception 'Pergunta inválida'; end if;
  select coalesce(max(position),0)+1 into v_pos from public.quiz_room_queue where room_id=p_room_id;
  insert into public.quiz_room_queue(room_id,question_id,position)
  values(p_room_id,p_question_id,v_pos)
  on conflict(room_id,question_id) do update set
    status=case when public.quiz_room_queue.status='used' then public.quiz_room_queue.status else 'queued' end
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.admin_queue_question(uuid,uuid) from public;
grant execute on function public.admin_queue_question(uuid,uuid) to authenticated;

create or replace function public.admin_list_room_queue(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_result jsonb;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',rq.id,'question_id',q.id,'position',rq.position,'status',rq.status,'round_id',rq.round_id,
    'prompt',q.prompt,'question_type',q.question_type,'points',q.points,'time_limit_seconds',q.time_limit_seconds,
    'archived',q.archived_at is not null
  ) order by rq.position asc,rq.added_at asc),'[]'::jsonb)
  into v_result
  from public.quiz_room_queue rq
  join public.quiz_questions q on q.id=rq.question_id
  where rq.room_id=p_room_id;
  return v_result;
end $$;
revoke all on function public.admin_list_room_queue(uuid) from public;
grant execute on function public.admin_list_room_queue(uuid) to authenticated;

create or replace function public.admin_remove_queue_item(p_room_id uuid,p_queue_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  delete from public.quiz_room_queue where id=p_queue_id and room_id=p_room_id and status='queued';
  if not found then raise exception 'Item não pode ser removido'; end if;
end $$;
revoke all on function public.admin_remove_queue_item(uuid,uuid) from public;
grant execute on function public.admin_remove_queue_item(uuid,uuid) to authenticated;

create or replace function public.admin_move_queue_item(p_room_id uuid,p_queue_id uuid,p_direction integer)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_cur public.quiz_room_queue; v_other public.quiz_room_queue;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_direction not in (-1,1) then raise exception 'Direção inválida'; end if;
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
  end if;
end $$;
revoke all on function public.admin_move_queue_item(uuid,uuid,integer) from public;
grant execute on function public.admin_move_queue_item(uuid,uuid,integer) to authenticated;

create or replace function public.admin_open_next_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_no integer; v_r public.quiz_rounds; v_item public.quiz_room_queue; v_q public.quiz_questions; v_now timestamptz:=clock_timestamp();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if not exists(select 1 from public.quiz_rooms where id=p_room_id and status<>'finished') then raise exception 'Sala inválida'; end if;
  if exists(select 1 from public.quiz_rounds where room_id=p_room_id and status='open') then raise exception 'Já existe um round aberto'; end if;
  select * into v_item from public.quiz_room_queue where room_id=p_room_id and status='queued' order by position asc,added_at asc limit 1 for update skip locked;
  if not found then raise exception 'A fila de rounds está vazia'; end if;
  select * into v_q from public.quiz_questions where id=v_item.question_id and active;
  if not found then raise exception 'Pergunta da fila não está disponível'; end if;
  select coalesce(max(round_no),0)+1 into v_no from public.quiz_rounds where room_id=p_room_id;
  insert into public.quiz_rounds(room_id,question_id,round_no,status,opened_at,time_limit_seconds,closes_at)
  values(p_room_id,v_q.id,v_no,'open',v_now,v_q.time_limit_seconds,v_now+make_interval(secs=>v_q.time_limit_seconds))
  returning * into v_r;
  update public.quiz_room_queue set status='used',round_id=v_r.id,used_at=v_now where id=v_item.id;
  perform private.notify_room(p_room_id);
  return to_jsonb(v_r);
end $$;
revoke all on function public.admin_open_next_round(uuid) from public;
grant execute on function public.admin_open_next_round(uuid) to authenticated;

create or replace function public.get_game_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_part public.quiz_participants; v_round public.quiz_rounds; v_q public.quiz_questions; v_my public.quiz_answers; v_round_json jsonb; v_rank jsonb; v_now timestamptz:=clock_timestamp();
begin
  select * into v_part from public.quiz_participants where room_id=p_room_id and user_id=v_uid;
  if not found then raise exception 'Participante não pertence à sala'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1;
  if found then
    select * into v_q from public.quiz_questions where id=v_round.question_id;
    select * into v_my from public.quiz_answers where round_id=v_round.id and participant_id=v_part.id;
    v_round_json:=jsonb_build_object(
      'id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,
      'closes_at',v_round.closes_at,'time_limit_seconds',v_round.time_limit_seconds,
      'accepting_responses',(v_round.status='open' and v_round.closes_at is not null and v_now<=v_round.closes_at),
      'prompt',v_q.prompt,'question_type',v_q.question_type,'options',coalesce(v_q.options,'[]'::jsonb),
      'points',v_q.points,'my_answer',case when v_my.id is null then null else to_jsonb(v_my) end,
      'result_text',v_round.result_text
    );
  else
    v_round_json:=null;
  end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_points desc,x.joined_at asc),'[]'::jsonb)
  into v_rank from (select display_name,total_points,joined_at from public.quiz_participants where room_id=p_room_id order by total_points desc,joined_at asc limit 200) x;
  return jsonb_build_object('round',v_round_json,'ranking',v_rank,'server_now',v_now);
end $$;
revoke all on function public.get_game_state(uuid) from public;
grant execute on function public.get_game_state(uuid) to authenticated;

create or replace function public.submit_quiz_answer(p_round_id uuid,p_choice text default null,p_number numeric default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_r public.quiz_rounds; v_q public.quiz_questions; v_p public.quiz_participants; v_ms integer; v_a public.quiz_answers; v_now timestamptz:=clock_timestamp();
begin
  select * into v_r from public.quiz_rounds where id=p_round_id for share;
  if not found or v_r.status<>'open' then raise exception 'Round encerrado'; end if;
  if v_r.closes_at is null or v_now>v_r.closes_at then raise exception 'Tempo esgotado'; end if;
  select * into v_q from public.quiz_questions where id=v_r.question_id;
  select * into v_p from public.quiz_participants where room_id=v_r.room_id and user_id=v_uid;
  if not found then raise exception 'Participante inválido'; end if;
  if v_q.question_type='choice' then
    if p_choice is null or p_choice not in ('A','B','C','D') then raise exception 'Alternativa inválida'; end if;
    p_number:=null;
  else
    if p_number is null then raise exception 'Informe um número'; end if;
    p_choice:=null;
  end if;
  v_ms:=greatest(0,least(2147483647,(extract(epoch from (v_now-v_r.opened_at))*1000)::bigint))::integer;
  insert into public.quiz_answers(round_id,participant_id,choice_value,numeric_value,response_ms)
  values(v_r.id,v_p.id,p_choice,p_number,v_ms) returning * into v_a;
  perform private.notify_room(v_r.room_id);
  return to_jsonb(v_a);
exception when unique_violation then raise exception 'Você já respondeu este round';
end $$;
revoke all on function public.submit_quiz_answer(uuid,text,numeric) from public;
grant execute on function public.submit_quiz_answer(uuid,text,numeric) to authenticated;

create or replace function public.admin_get_room_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_r jsonb; v_rank jsonb; v_now timestamptz:=clock_timestamp(); v_participants integer; v_answers integer;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select to_jsonb(x) into v_r from (
    select id,round_no,status,opened_at,closed_at,result_text,time_limit_seconds,closes_at,
      (status='open' and closes_at is not null and v_now<=closes_at) as accepting_responses
    from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1
  ) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_points desc,x.joined_at asc),'[]'::jsonb)
  into v_rank from (select display_name,total_points,joined_at from public.quiz_participants where room_id=p_room_id order by total_points desc,joined_at asc limit 200) x;
  select count(*) into v_participants from public.quiz_participants where room_id=p_room_id;
  if v_r is not null then select count(*) into v_answers from public.quiz_answers where round_id=(v_r->>'id')::uuid; else v_answers:=0; end if;
  return jsonb_build_object('round',v_r,'ranking',v_rank,'participant_count',v_participants,'answer_count',v_answers,'server_now',v_now);
end $$;
revoke all on function public.admin_get_room_state(uuid) from public;
grant execute on function public.admin_get_room_state(uuid) to authenticated;
