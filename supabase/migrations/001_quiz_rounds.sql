create extension if not exists pgcrypto;
create schema if not exists private;

create table if not exists public.quiz_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id),
  prompt text not null check (length(prompt) between 1 and 1000),
  question_type text not null check (question_type in ('choice','numeric')),
  options jsonb,
  points integer not null default 1000 check (points between 1 and 100000),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check ((question_type='choice' and jsonb_typeof(options)='array' and jsonb_array_length(options)=4) or (question_type='numeric' and options is null))
);

create table if not exists private.quiz_answer_keys (
  question_id uuid primary key references public.quiz_questions(id) on delete cascade,
  correct_choice text,
  correct_number numeric,
  check ((correct_choice is not null and correct_number is null) or (correct_choice is null and correct_number is not null))
);

create table if not exists public.quiz_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  created_by uuid not null references auth.users(id),
  status text not null default 'waiting' check (status in ('waiting','live','finished')),
  created_at timestamptz not null default now()
);

create table if not exists public.quiz_participants (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.quiz_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (length(display_name) between 1 and 32),
  total_points integer not null default 0,
  joined_at timestamptz not null default now(),
  unique(room_id,user_id)
);
create index if not exists quiz_participants_room_score_idx on public.quiz_participants(room_id,total_points desc,joined_at);

create table if not exists public.quiz_rounds (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.quiz_rooms(id) on delete cascade,
  question_id uuid not null references public.quiz_questions(id),
  round_no integer not null,
  status text not null default 'open' check (status in ('open','closed')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  result_text text,
  unique(room_id,round_no)
);
create index if not exists quiz_rounds_room_idx on public.quiz_rounds(room_id,round_no desc);

create table if not exists public.quiz_answers (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.quiz_rounds(id) on delete cascade,
  participant_id uuid not null references public.quiz_participants(id) on delete cascade,
  choice_value text,
  numeric_value numeric,
  submitted_at timestamptz not null default now(),
  response_ms integer not null,
  awarded_points integer not null default 0,
  unique(round_id,participant_id),
  check ((choice_value is not null and numeric_value is null) or (choice_value is null and numeric_value is not null))
);
create index if not exists quiz_answers_round_idx on public.quiz_answers(round_id,submitted_at);

alter table public.quiz_admins enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_rooms enable row level security;
alter table public.quiz_participants enable row level security;
alter table public.quiz_rounds enable row level security;
alter table public.quiz_answers enable row level security;

revoke all on public.quiz_admins, public.quiz_questions, public.quiz_rooms, public.quiz_participants, public.quiz_rounds, public.quiz_answers from anon, authenticated;

create or replace function private.is_admin(p_uid uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.quiz_admins a where a.user_id=p_uid)
$$;
revoke all on function private.is_admin(uuid) from public;

create or replace function private.notify_room(p_room_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform realtime.send(jsonb_build_object('room_id',p_room_id,'at',clock_timestamp()),'state_changed','quiz:'||p_room_id::text,false);
exception when others then
  null;
end $$;
revoke all on function private.notify_room(uuid) from public;

create or replace function public.is_quiz_admin()
returns boolean language sql stable security definer set search_path='' as $$
  select private.is_admin(auth.uid())
$$;
revoke all on function public.is_quiz_admin() from public;
grant execute on function public.is_quiz_admin() to authenticated;

create or replace function public.join_quiz_room(p_code text,p_name text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_room public.quiz_rooms; v_part public.quiz_participants; v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  if length(trim(p_name))<1 or length(trim(p_name))>32 then raise exception 'Nome inválido'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) and status<>'finished';
  if not found then raise exception 'Sala não encontrada ou encerrada'; end if;
  insert into public.quiz_participants(room_id,user_id,display_name) values(v_room.id,v_uid,trim(p_name))
  on conflict(room_id,user_id) do update set display_name=excluded.display_name returning * into v_part;
  perform private.notify_room(v_room.id);
  return jsonb_build_object('room',to_jsonb(v_room),'participant',to_jsonb(v_part));
end $$;
revoke all on function public.join_quiz_room(text,text) from public;
grant execute on function public.join_quiz_room(text,text) to authenticated;

create or replace function public.get_game_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_part public.quiz_participants; v_round public.quiz_rounds; v_q public.quiz_questions; v_my public.quiz_answers; v_round_json jsonb; v_rank jsonb;
begin
  select * into v_part from public.quiz_participants where room_id=p_room_id and user_id=v_uid;
  if not found then raise exception 'Participante não pertence à sala'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1;
  if found then
    select * into v_q from public.quiz_questions where id=v_round.question_id;
    select * into v_my from public.quiz_answers where round_id=v_round.id and participant_id=v_part.id;
    v_round_json:=jsonb_build_object('id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,'prompt',v_q.prompt,'question_type',v_q.question_type,'options',coalesce(v_q.options,'[]'::jsonb),'points',v_q.points,'my_answer',case when v_my.id is null then null else to_jsonb(v_my) end,'result_text',v_round.result_text);
  else
    v_round_json:=null;
  end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_points desc,x.joined_at asc),'[]'::jsonb) into v_rank from (select display_name,total_points,joined_at from public.quiz_participants where room_id=p_room_id order by total_points desc,joined_at asc limit 100) x;
  return jsonb_build_object('round',v_round_json,'ranking',v_rank);
end $$;
revoke all on function public.get_game_state(uuid) from public;
grant execute on function public.get_game_state(uuid) to authenticated;

create or replace function public.submit_quiz_answer(p_round_id uuid,p_choice text default null,p_number numeric default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_r public.quiz_rounds; v_q public.quiz_questions; v_p public.quiz_participants; v_ms integer; v_a public.quiz_answers;
begin
  select * into v_r from public.quiz_rounds where id=p_round_id;
  if not found or v_r.status<>'open' then raise exception 'Round encerrado'; end if;
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
  v_ms:=greatest(0,least(2147483647,(extract(epoch from (clock_timestamp()-v_r.opened_at))*1000)::bigint))::integer;
  insert into public.quiz_answers(round_id,participant_id,choice_value,numeric_value,response_ms) values(v_r.id,v_p.id,p_choice,p_number,v_ms) returning * into v_a;
  perform private.notify_room(v_r.room_id);
  return to_jsonb(v_a);
exception when unique_violation then raise exception 'Você já respondeu este round';
end $$;
revoke all on function public.submit_quiz_answer(uuid,text,numeric) from public;
grant execute on function public.submit_quiz_answer(uuid,text,numeric) to authenticated;

create or replace function public.admin_create_room(p_title text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_code text;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  loop
    v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
    exit when not exists(select 1 from public.quiz_rooms where code=v_code);
  end loop;
  insert into public.quiz_rooms(code,title,created_by,status) values(v_code,coalesce(nullif(trim(p_title),''),'Quiz ao vivo'),v_uid,'live') returning * into v_room;
  return to_jsonb(v_room);
end $$;
revoke all on function public.admin_create_room(text) from public;
grant execute on function public.admin_create_room(text) to authenticated;

create or replace function public.admin_create_question(p_prompt text,p_type text,p_options jsonb,p_correct_choice text,p_correct_number numeric,p_points integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_id uuid;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_type not in ('choice','numeric') then raise exception 'Tipo inválido'; end if;
  if p_type='choice' then
    if jsonb_typeof(p_options)<>'array' or jsonb_array_length(p_options)<>4 or p_correct_choice not in ('A','B','C','D') then raise exception 'Alternativas inválidas'; end if;
    p_correct_number:=null;
  else
    if p_correct_number is null then raise exception 'Valor correto obrigatório'; end if;
    p_options:=null;p_correct_choice:=null;
  end if;
  insert into public.quiz_questions(created_by,prompt,question_type,options,points) values(v_uid,trim(p_prompt),p_type,p_options,greatest(1,coalesce(p_points,1000))) returning id into v_id;
  insert into private.quiz_answer_keys(question_id,correct_choice,correct_number) values(v_id,p_correct_choice,p_correct_number);
  return v_id;
end $$;
revoke all on function public.admin_create_question(text,text,jsonb,text,numeric,integer) from public;
grant execute on function public.admin_create_question(text,text,jsonb,text,numeric,integer) to authenticated;

create or replace function public.admin_list_questions()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_result jsonb;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.prompt,'question_type',q.question_type,'options',q.options,'points',q.points,'correct_choice',k.correct_choice,'correct_number',k.correct_number,'created_at',q.created_at) order by q.created_at desc),'[]'::jsonb) into v_result
  from public.quiz_questions q join private.quiz_answer_keys k on k.question_id=q.id where q.active;
  return v_result;
end $$;
revoke all on function public.admin_list_questions() from public;
grant execute on function public.admin_list_questions() to authenticated;

create or replace function public.admin_open_round(p_room_id uuid,p_question_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_no integer; v_r public.quiz_rounds;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if not exists(select 1 from public.quiz_rooms where id=p_room_id and status<>'finished') then raise exception 'Sala inválida'; end if;
  if exists(select 1 from public.quiz_rounds where room_id=p_room_id and status='open') then raise exception 'Já existe um round aberto'; end if;
  if not exists(select 1 from public.quiz_questions where id=p_question_id and active) then raise exception 'Pergunta inválida'; end if;
  select coalesce(max(round_no),0)+1 into v_no from public.quiz_rounds where room_id=p_room_id;
  insert into public.quiz_rounds(room_id,question_id,round_no,status) values(p_room_id,p_question_id,v_no,'open') returning * into v_r;
  perform private.notify_room(p_room_id);
  return to_jsonb(v_r);
end $$;
revoke all on function public.admin_open_round(uuid,uuid) from public;
grant execute on function public.admin_open_round(uuid,uuid) to authenticated;

create or replace function public.admin_close_and_score_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_r public.quiz_rounds; v_q public.quiz_questions; v_k private.quiz_answer_keys; v_count integer:=0; v_winner uuid;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_r from public.quiz_rounds where room_id=p_room_id and status='open' order by round_no desc limit 1 for update;
  if not found then raise exception 'Nenhum round aberto'; end if;
  select * into v_q from public.quiz_questions where id=v_r.question_id;
  select * into v_k from private.quiz_answer_keys where question_id=v_q.id;
  update public.quiz_answers set awarded_points=0 where round_id=v_r.id;
  if v_q.question_type='choice' then
    update public.quiz_answers set awarded_points=v_q.points where round_id=v_r.id and choice_value=v_k.correct_choice;
  else
    select a.id into v_winner from public.quiz_answers a where a.round_id=v_r.id order by abs(a.numeric_value-v_k.correct_number) asc,a.response_ms asc,a.submitted_at asc limit 1;
    if v_winner is not null then update public.quiz_answers set awarded_points=v_q.points where id=v_winner; end if;
  end if;
  update public.quiz_participants p set total_points=(select coalesce(sum(a.awarded_points),0)::integer from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id where a.participant_id=p.id and r.room_id=p_room_id) where p.room_id=p_room_id;
  select count(*) into v_count from public.quiz_answers where round_id=v_r.id;
  update public.quiz_rounds set status='closed',closed_at=clock_timestamp(),result_text=case when v_q.question_type='choice' then 'Resposta correta: '||v_k.correct_choice else 'Valor correto: '||v_k.correct_number::text end where id=v_r.id;
  perform private.notify_room(p_room_id);
  return jsonb_build_object('round_id',v_r.id,'answers',v_count);
end $$;
revoke all on function public.admin_close_and_score_round(uuid) from public;
grant execute on function public.admin_close_and_score_round(uuid) to authenticated;

create or replace function public.admin_get_room_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_r jsonb; v_rank jsonb;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select to_jsonb(x) into v_r from (select id,round_no,status,opened_at,closed_at,result_text from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_points desc,x.joined_at asc),'[]'::jsonb) into v_rank from (select display_name,total_points,joined_at from public.quiz_participants where room_id=p_room_id order by total_points desc,joined_at asc limit 200) x;
  return jsonb_build_object('round',v_r,'ranking',v_rank);
end $$;
revoke all on function public.admin_get_room_state(uuid) from public;
grant execute on function public.admin_get_room_state(uuid) to authenticated;

grant usage on schema public to authenticated;
