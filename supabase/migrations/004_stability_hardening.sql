-- Quiz Rounds v1.5: estabilidade, snapshots imutáveis, heartbeat, Broadcast privado, auditoria e recuperação.

alter table public.quiz_rooms
  add column if not exists phase text not null default 'lobby',
  add column if not exists state_version bigint not null default 0,
  add column if not exists last_state_at timestamptz not null default now(),
  add column if not exists final_ranking_snapshot jsonb;

do $$ begin
  alter table public.quiz_rooms add constraint quiz_rooms_phase_check check (phase in ('lobby','question_open','result','finished'));
exception when duplicate_object then null; end $$;

update public.quiz_rooms
set phase = case
  when status='finished' or game_status='finished' then 'finished'
  when exists(select 1 from public.quiz_rounds r where r.room_id=quiz_rooms.id and r.status='open') then 'question_open'
  when exists(select 1 from public.quiz_rounds r where r.room_id=quiz_rooms.id and r.status='closed') then 'result'
  else 'lobby'
end;

alter table public.quiz_participants
  add column if not exists last_seen_at timestamptz not null default now(),
  add column if not exists last_join_at timestamptz not null default now();

alter table public.quiz_room_queue
  add column if not exists prompt_snapshot text,
  add column if not exists question_type_snapshot text,
  add column if not exists options_snapshot jsonb,
  add column if not exists points_snapshot integer,
  add column if not exists time_limit_snapshot integer;

alter table public.quiz_rounds
  add column if not exists prompt_snapshot text,
  add column if not exists question_type_snapshot text,
  add column if not exists options_snapshot jsonb,
  add column if not exists points_snapshot integer,
  add column if not exists answer_count_snapshot integer,
  add column if not exists ranking_snapshot jsonb,
  add column if not exists winner_snapshot jsonb,
  add column if not exists result_locked boolean not null default false;

update public.quiz_room_queue rq
set prompt_snapshot=coalesce(rq.prompt_snapshot,q.prompt),
    question_type_snapshot=coalesce(rq.question_type_snapshot,q.question_type),
    options_snapshot=case when rq.options_snapshot is null then q.options else rq.options_snapshot end,
    points_snapshot=coalesce(rq.points_snapshot,q.points),
    time_limit_snapshot=coalesce(rq.time_limit_snapshot,q.time_limit_seconds)
from public.quiz_questions q
where q.id=rq.question_id;

update public.quiz_rounds r
set prompt_snapshot=coalesce(r.prompt_snapshot,q.prompt),
    question_type_snapshot=coalesce(r.question_type_snapshot,q.question_type),
    options_snapshot=case when r.options_snapshot is null then q.options else r.options_snapshot end,
    points_snapshot=coalesce(r.points_snapshot,q.points)
from public.quiz_questions q
where q.id=r.question_id;

create table if not exists private.quiz_queue_answer_keys (
  queue_id uuid primary key references public.quiz_room_queue(id) on delete cascade,
  correct_choice text,
  correct_number numeric,
  check ((correct_choice is not null and correct_number is null) or (correct_choice is null and correct_number is not null))
);

insert into private.quiz_queue_answer_keys(queue_id,correct_choice,correct_number)
select rq.id,k.correct_choice,k.correct_number
from public.quiz_room_queue rq
join private.quiz_answer_keys k on k.question_id=rq.question_id
on conflict(queue_id) do nothing;

create table if not exists private.quiz_round_answer_keys (
  round_id uuid primary key references public.quiz_rounds(id) on delete cascade,
  correct_choice text,
  correct_number numeric,
  check ((correct_choice is not null and correct_number is null) or (correct_choice is null and correct_number is not null))
);

insert into private.quiz_round_answer_keys(round_id,correct_choice,correct_number)
select r.id,k.correct_choice,k.correct_number
from public.quiz_rounds r
join private.quiz_answer_keys k on k.question_id=r.question_id
on conflict(round_id) do nothing;

create table if not exists public.quiz_realtime_memberships (
  user_id uuid not null references auth.users(id) on delete cascade,
  room_id uuid not null references public.quiz_rooms(id) on delete cascade,
  role text not null check (role in ('admin','participant','display')),
  authorized_at timestamptz not null default now(),
  primary key(user_id,room_id,role)
);

create table if not exists public.quiz_audit_log (
  id bigint generated always as identity primary key,
  room_id uuid references public.quiz_rooms(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.quiz_realtime_memberships enable row level security;
alter table public.quiz_audit_log enable row level security;
revoke all on public.quiz_realtime_memberships, public.quiz_audit_log from anon, authenticated;
grant select on public.quiz_realtime_memberships to authenticated;

drop policy if exists quiz_realtime_memberships_own_select on public.quiz_realtime_memberships;
create policy quiz_realtime_memberships_own_select
on public.quiz_realtime_memberships for select to authenticated
using ((select auth.uid()) is not null and user_id=(select auth.uid()));

-- Realtime Authorization: só membros autorizados da sala recebem Broadcast.
drop policy if exists quiz_realtime_read on realtime.messages;
create policy quiz_realtime_read
on realtime.messages for select to authenticated
using (
  realtime.messages.extension in ('broadcast','presence')
  and exists (
    select 1
    from public.quiz_realtime_memberships m
    where m.user_id=(select auth.uid())
      and ('quiz:'||m.room_id::text)=(select realtime.topic())
      and (realtime.messages.extension='broadcast' or m.role in ('participant','admin'))
  )
);

drop policy if exists quiz_realtime_presence_write on realtime.messages;
create policy quiz_realtime_presence_write
on realtime.messages for insert to authenticated
with check (
  realtime.messages.extension='presence'
  and exists (
    select 1
    from public.quiz_realtime_memberships m
    where m.user_id=(select auth.uid())
      and m.role='participant'
      and ('quiz:'||m.room_id::text)=(select realtime.topic())
  )
);

create index if not exists quiz_participants_room_last_seen_idx on public.quiz_participants(room_id,last_seen_at desc);
create index if not exists quiz_answers_round_choice_idx on public.quiz_answers(round_id,choice_value,response_ms,submitted_at);
create index if not exists quiz_answers_round_numeric_idx on public.quiz_answers(round_id,numeric_value,response_ms,submitted_at);
create index if not exists quiz_rounds_room_status_idx on public.quiz_rounds(room_id,status,round_no desc);
create index if not exists quiz_audit_room_created_idx on public.quiz_audit_log(room_id,created_at desc);
create index if not exists quiz_memberships_room_role_idx on public.quiz_realtime_memberships(room_id,role,user_id);

create or replace function private.audit_event(
  p_room_id uuid,
  p_actor uuid,
  p_action text,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_details jsonb default '{}'::jsonb
)
returns void language plpgsql security definer set search_path='' as $$
begin
  insert into public.quiz_audit_log(room_id,actor_user_id,action,entity_type,entity_id,details)
  values(p_room_id,p_actor,p_action,p_entity_type,p_entity_id,coalesce(p_details,'{}'::jsonb));
end $$;
revoke all on function private.audit_event(uuid,uuid,text,text,uuid,jsonb) from public;

create or replace function private.publish_room_event(
  p_room_id uuid,
  p_event text,
  p_payload jsonb default '{}'::jsonb
)
returns bigint language plpgsql security definer set search_path='' as $$
declare
  v_version bigint;
  v_now timestamptz:=clock_timestamp();
begin
  update public.quiz_rooms
  set state_version=state_version+1,last_state_at=v_now
  where id=p_room_id
  returning state_version into v_version;

  begin
    perform realtime.send(
      jsonb_build_object('room_id',p_room_id,'state_version',v_version,'event',p_event,'at',v_now) || coalesce(p_payload,'{}'::jsonb),
      'state_changed',
      'quiz:'||p_room_id::text,
      true
    );
  exception when others then
    null;
  end;
  return coalesce(v_version,0);
end $$;
revoke all on function private.publish_room_event(uuid,text,jsonb) from public;

create or replace function private.notify_room(p_room_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform private.publish_room_event(p_room_id,'state_changed','{}'::jsonb);
end $$;
revoke all on function private.notify_room(uuid) from public;

create or replace function private.open_round_from_queue(p_room_id uuid,p_round_no integer)
returns public.quiz_rounds language plpgsql security definer set search_path='' as $$
declare
  v_item public.quiz_room_queue;
  v_key private.quiz_queue_answer_keys;
  v_round public.quiz_rounds;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_item
  from public.quiz_room_queue
  where room_id=p_room_id and status='queued'
  order by position asc,added_at asc
  limit 1 for update skip locked;
  if not found then raise exception 'A fila de rounds está vazia'; end if;

  select * into v_key from private.quiz_queue_answer_keys where queue_id=v_item.id;
  if not found then raise exception 'Snapshot da resposta não encontrado'; end if;

  insert into public.quiz_rounds(
    room_id,question_id,round_no,status,opened_at,time_limit_seconds,closes_at,
    prompt_snapshot,question_type_snapshot,options_snapshot,points_snapshot,result_locked
  ) values(
    p_room_id,v_item.question_id,p_round_no,'open',v_now,coalesce(v_item.time_limit_snapshot,30),
    v_now+make_interval(secs=>coalesce(v_item.time_limit_snapshot,30)),
    v_item.prompt_snapshot,v_item.question_type_snapshot,v_item.options_snapshot,v_item.points_snapshot,false
  ) returning * into v_round;

  insert into private.quiz_round_answer_keys(round_id,correct_choice,correct_number)
  values(v_round.id,v_key.correct_choice,v_key.correct_number);

  update public.quiz_room_queue
  set status='used',round_id=v_round.id,used_at=v_now
  where id=v_item.id;
  return v_round;
end $$;
revoke all on function private.open_round_from_queue(uuid,integer) from public;

create or replace function private.protect_closed_round()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status='closed' then
    raise exception 'Round encerrado é imutável';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function private.protect_closed_round() from public;

drop trigger if exists quiz_rounds_protect_closed on public.quiz_rounds;
create trigger quiz_rounds_protect_closed
before update or delete on public.quiz_rounds
for each row execute function private.protect_closed_round();

create or replace function public.authorize_quiz_display(p_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;
  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at)
  values(v_uid,v_room.id,'display',clock_timestamp())
  on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;
  return jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title);
end $$;
revoke all on function public.authorize_quiz_display(text) from public, anon;
grant execute on function public.authorize_quiz_display(text) to authenticated;

create or replace function public.join_quiz_room(p_code text,p_name text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_room public.quiz_rooms;
  v_part public.quiz_participants;
  v_uid uuid:=auth.uid();
  v_now timestamptz:=clock_timestamp();
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  if length(trim(coalesce(p_name,'')))<1 or length(trim(p_name))>32 then raise exception 'Nome inválido'; end if;

  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;

  select * into v_part from public.quiz_participants where room_id=v_room.id and user_id=v_uid;
  if v_room.status='finished' and not found then raise exception 'Sala encerrada'; end if;

  insert into public.quiz_participants(room_id,user_id,display_name,last_seen_at,last_join_at)
  values(v_room.id,v_uid,trim(p_name),v_now,v_now)
  on conflict(room_id,user_id) do update
    set display_name=excluded.display_name,last_seen_at=v_now,last_join_at=v_now
  returning * into v_part;

  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at)
  values(v_uid,v_room.id,'participant',v_now)
  on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;

  perform private.audit_event(v_room.id,v_uid,'participant_join','participant',v_part.id,jsonb_build_object('display_name',v_part.display_name));
  return jsonb_build_object('room',to_jsonb(v_room),'participant',to_jsonb(v_part));
end $$;
revoke all on function public.join_quiz_room(text,text) from public, anon;
grant execute on function public.join_quiz_room(text,text) to authenticated;

create or replace function public.heartbeat_quiz_participant(p_room_id uuid)
returns timestamptz language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_now timestamptz:=clock_timestamp();
begin
  update public.quiz_participants
  set last_seen_at=v_now
  where room_id=p_room_id and user_id=v_uid;
  if not found then raise exception 'Participante inválido'; end if;
  return v_now;
end $$;
revoke all on function public.heartbeat_quiz_participant(uuid) from public, anon;
grant execute on function public.heartbeat_quiz_participant(uuid) to authenticated;

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
  insert into public.quiz_rooms(code,title,created_by,status,planned_rounds,game_status,phase)
  values(v_code,coalesce(nullif(trim(p_title),''),'Quiz ao vivo'),v_uid,'live',v_rounds,'lobby','lobby')
  returning * into v_room;

  insert into public.quiz_realtime_memberships(user_id,room_id,role)
  values(v_uid,v_room.id,'admin') on conflict do nothing;
  perform private.audit_event(v_room.id,v_uid,'room_created','room',v_room.id,jsonb_build_object('planned_rounds',v_rounds,'title',v_room.title));
  perform private.publish_room_event(v_room.id,'room_created','{}'::jsonb);
  select * into v_room from public.quiz_rooms where id=v_room.id;
  return to_jsonb(v_room);
end $$;
revoke all on function public.admin_create_room_v3(text,integer) from public;
grant execute on function public.admin_create_room_v3(text,integer) to authenticated;

create or replace function public.admin_get_latest_room()
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room
  from public.quiz_rooms
  where created_by=v_uid and status<>'finished'
  order by created_at desc limit 1;
  if not found then return null; end if;
  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at)
  values(v_uid,v_room.id,'admin',clock_timestamp())
  on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;
  return to_jsonb(v_room);
end $$;
revoke all on function public.admin_get_latest_room() from public;
grant execute on function public.admin_get_latest_room() to authenticated;

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
  if v_room.phase<>'lobby' then raise exception 'A quantidade de rounds fica bloqueada depois do início'; end if;
  select count(*) into v_selected from public.quiz_room_queue where room_id=p_room_id;
  if v_rounds<v_selected then raise exception 'Remova perguntas antes de reduzir a quantidade de rounds'; end if;
  update public.quiz_rooms set planned_rounds=v_rounds where id=p_room_id;
  perform private.audit_event(p_room_id,v_uid,'planned_rounds_changed','room',p_room_id,jsonb_build_object('planned_rounds',v_rounds));
  perform private.publish_room_event(p_room_id,'room_config_changed','{}'::jsonb);
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
  v_q public.quiz_questions;
  v_key private.quiz_answer_keys;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found or v_room.status='finished' then raise exception 'Sala inválida'; end if;
  if v_room.phase<>'lobby' then raise exception 'As perguntas ficam bloqueadas depois que o quiz começa'; end if;
  select * into v_q from public.quiz_questions where id=p_question_id and active and archived_at is null;
  if not found then raise exception 'Pergunta indisponível ou arquivada'; end if;
  select * into v_key from private.quiz_answer_keys where question_id=p_question_id;
  if not found then raise exception 'Resposta da pergunta não encontrada'; end if;
  if exists(select 1 from public.quiz_room_queue where room_id=p_room_id and question_id=p_question_id) then raise exception 'Esta pergunta já foi escolhida'; end if;
  select count(*) into v_count from public.quiz_room_queue where room_id=p_room_id;
  if v_count>=v_room.planned_rounds then raise exception 'A quantidade de perguntas já atingiu o número de rounds'; end if;
  select coalesce(max(position),0)+1 into v_pos from public.quiz_room_queue where room_id=p_room_id;

  insert into public.quiz_room_queue(
    room_id,question_id,position,prompt_snapshot,question_type_snapshot,options_snapshot,points_snapshot,time_limit_snapshot
  ) values(
    p_room_id,p_question_id,v_pos,v_q.prompt,v_q.question_type,v_q.options,v_q.points,v_q.time_limit_seconds
  ) returning id into v_id;

  insert into private.quiz_queue_answer_keys(queue_id,correct_choice,correct_number)
  values(v_id,v_key.correct_choice,v_key.correct_number);
  perform private.audit_event(p_room_id,v_uid,'question_queued','queue',v_id,jsonb_build_object('question_id',p_question_id,'position',v_pos));
  return v_id;
end $$;
revoke all on function public.admin_queue_question(uuid,uuid) from public;
grant execute on function public.admin_queue_question(uuid,uuid) to authenticated;

create or replace function public.admin_remove_queue_item(p_room_id uuid,p_queue_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_phase text;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select phase into v_phase from public.quiz_rooms where id=p_room_id for update;
  if v_phase<>'lobby' then raise exception 'A lista de rounds está bloqueada'; end if;
  delete from public.quiz_room_queue where id=p_queue_id and room_id=p_room_id and status='queued';
  if not found then raise exception 'Item não pode ser removido'; end if;
  perform private.audit_event(p_room_id,v_uid,'question_removed_from_queue','queue',p_queue_id,'{}'::jsonb);
end $$;
revoke all on function public.admin_remove_queue_item(uuid,uuid) from public;
grant execute on function public.admin_remove_queue_item(uuid,uuid) to authenticated;

create or replace function public.admin_move_queue_item(p_room_id uuid,p_queue_id uuid,p_direction integer)
returns void language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_phase text;
  v_cur public.quiz_room_queue;
  v_other public.quiz_room_queue;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_direction not in (-1,1) then raise exception 'Direção inválida'; end if;
  select phase into v_phase from public.quiz_rooms where id=p_room_id for update;
  if v_phase<>'lobby' then raise exception 'A ordem dos rounds está bloqueada'; end if;
  select * into v_cur from public.quiz_room_queue where id=p_queue_id and room_id=p_room_id and status='queued' for update;
  if not found then raise exception 'Item não encontrado'; end if;
  if p_direction=-1 then
    select * into v_other from public.quiz_room_queue where room_id=p_room_id and status='queued' and position<v_cur.position order by position desc,added_at desc limit 1 for update;
  else
    select * into v_other from public.quiz_room_queue where room_id=p_room_id and status='queued' and position>v_cur.position order by position asc,added_at asc limit 1 for update;
  end if;
  if found then
    update public.quiz_room_queue set position=v_other.position where id=v_cur.id;
    update public.quiz_room_queue set position=v_cur.position where id=v_other.id;
    perform private.audit_event(p_room_id,v_uid,'queue_reordered','queue',p_queue_id,jsonb_build_object('direction',p_direction));
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

  update public.quiz_rooms set game_status='running',phase='question_open',started_at=clock_timestamp() where id=p_room_id;
  select * into v_round from private.open_round_from_queue(p_room_id,1);
  perform private.audit_event(p_room_id,v_uid,'quiz_started','round',v_round.id,jsonb_build_object('round_no',1));
  perform private.publish_room_event(p_room_id,'round_opened',jsonb_build_object('round_no',1));
  return jsonb_build_object('already_applied',false,'phase','question_open','round',to_jsonb(v_round));
end $$;
revoke all on function public.admin_start_quiz(uuid) from public;
grant execute on function public.admin_start_quiz(uuid) to authenticated;

create or replace function public.admin_open_next_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_no integer;
  v_round public.quiz_rounds;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala inválida'; end if;

  if v_room.phase='question_open' then
    select * into v_round from public.quiz_rounds where room_id=p_room_id and status='open' order by round_no desc limit 1;
    return jsonb_build_object('already_applied',true,'phase',v_room.phase,'round',case when v_round.id is null then null else to_jsonb(v_round) end);
  end if;
  if v_room.phase='finished' then
    return jsonb_build_object('already_applied',true,'phase','finished','round',null);
  end if;
  if v_room.phase<>'result' then raise exception 'O próximo round ainda não pode ser aberto'; end if;

  select coalesce(max(round_no),0)+1 into v_no from public.quiz_rounds where room_id=p_room_id;
  if v_no>v_room.planned_rounds then raise exception 'Todos os rounds configurados já foram usados'; end if;
  update public.quiz_rooms set phase='question_open',game_status='running' where id=p_room_id;
  select * into v_round from private.open_round_from_queue(p_room_id,v_no);
  perform private.audit_event(p_room_id,v_uid,'round_opened','round',v_round.id,jsonb_build_object('round_no',v_no));
  perform private.publish_room_event(p_room_id,'round_opened',jsonb_build_object('round_no',v_no));
  return jsonb_build_object('already_applied',false,'phase','question_open','round',to_jsonb(v_round));
end $$;
revoke all on function public.admin_open_next_round(uuid) from public;
grant execute on function public.admin_open_next_round(uuid) to authenticated;

create or replace function public.submit_quiz_answer(p_round_id uuid,p_choice text default null,p_number numeric default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_round public.quiz_rounds;
  v_room public.quiz_rooms;
  v_part public.quiz_participants;
  v_answer public.quiz_answers;
  v_existing public.quiz_answers;
  v_now timestamptz:=clock_timestamp();
  v_ms integer;
  v_choice text;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_round from public.quiz_rounds where id=p_round_id for share;
  if not found then raise exception 'Round não encontrado'; end if;
  select * into v_room from public.quiz_rooms where id=v_round.room_id;
  if v_room.phase<>'question_open' or v_round.status<>'open' then raise exception 'Round encerrado'; end if;
  if v_round.closes_at is null or v_now>v_round.closes_at then raise exception 'Tempo esgotado'; end if;

  select * into v_part from public.quiz_participants where room_id=v_round.room_id and user_id=v_uid;
  if not found then raise exception 'Participante inválido'; end if;

  if v_round.question_type_snapshot='choice' then
    v_choice:=upper(trim(coalesce(p_choice,'')));
    if v_choice='' or not exists(select 1 from jsonb_array_elements(coalesce(v_round.options_snapshot,'[]'::jsonb)) o where o->>'key'=v_choice) then
      raise exception 'Alternativa inválida';
    end if;
    p_number:=null;
  elsif v_round.question_type_snapshot='numeric' then
    if p_number is null or abs(p_number)>1000000000000000::numeric then raise exception 'Informe um número válido'; end if;
    v_choice:=null;
  else
    raise exception 'Tipo de pergunta inválido';
  end if;

  v_ms:=greatest(0,least(2147483647,(extract(epoch from (v_now-v_round.opened_at))*1000)::bigint))::integer;
  insert into public.quiz_answers(round_id,participant_id,choice_value,numeric_value,submitted_at,response_ms)
  values(v_round.id,v_part.id,v_choice,p_number,v_now,v_ms)
  on conflict(round_id,participant_id) do nothing
  returning * into v_answer;

  if v_answer.id is null then
    select * into v_existing from public.quiz_answers where round_id=v_round.id and participant_id=v_part.id;
    return jsonb_build_object('accepted',false,'reason','already_submitted','answer',to_jsonb(v_existing),'server_now',v_now);
  end if;

  update public.quiz_participants set last_seen_at=v_now where id=v_part.id;
  return jsonb_build_object('accepted',true,'answer',to_jsonb(v_answer),'server_now',v_now);
end $$;
revoke all on function public.submit_quiz_answer(uuid,text,numeric) from public, anon;
grant execute on function public.submit_quiz_answer(uuid,text,numeric) to authenticated;

create or replace function public.admin_close_and_score_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_round public.quiz_rounds;
  v_key private.quiz_round_answer_keys;
  v_count integer:=0;
  v_round_count integer:=0;
  v_winner_answer public.quiz_answers;
  v_result text;
  v_rank jsonb;
  v_winners jsonb:='[]'::jsonb;
  v_finished boolean:=false;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala inválida'; end if;

  if v_room.phase in ('result','finished') then
    select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1;
    return jsonb_build_object('already_applied',true,'round_id',v_round.id,'answers',coalesce(v_round.answer_count_snapshot,0),'finished',v_room.phase='finished','result_text',v_round.result_text);
  end if;
  if v_room.phase<>'question_open' then raise exception 'Nenhum round aberto'; end if;

  select * into v_round from public.quiz_rounds where room_id=p_room_id and status='open' order by round_no desc limit 1 for update;
  if not found then raise exception 'Nenhum round aberto'; end if;
  select * into v_key from private.quiz_round_answer_keys where round_id=v_round.id;
  if not found then raise exception 'Resposta do round não encontrada'; end if;

  update public.quiz_answers set awarded_points=0 where round_id=v_round.id;
  if v_round.question_type_snapshot='choice' then
    update public.quiz_answers
    set awarded_points=coalesce(v_round.points_snapshot,0)
    where round_id=v_round.id and choice_value=v_key.correct_choice;

    select coalesce(jsonb_agg(jsonb_build_object('participant_id',x.participant_id,'display_name',x.display_name,'response_ms',x.response_ms,'points',x.awarded_points) order by x.response_ms,x.submitted_at,x.participant_id),'[]'::jsonb)
    into v_winners
    from (
      select a.participant_id,p.display_name,a.response_ms,a.submitted_at,a.awarded_points
      from public.quiz_answers a join public.quiz_participants p on p.id=a.participant_id
      where a.round_id=v_round.id and a.choice_value=v_key.correct_choice
      order by a.response_ms,a.submitted_at,a.participant_id limit 20
    ) x;
    v_result:='Resposta correta: '||v_key.correct_choice||coalesce((select ' — '||(o->>'text') from jsonb_array_elements(coalesce(v_round.options_snapshot,'[]'::jsonb)) o where o->>'key'=v_key.correct_choice limit 1),'');
  else
    select a.* into v_winner_answer
    from public.quiz_answers a
    where a.round_id=v_round.id
    order by abs(a.numeric_value-v_key.correct_number) asc,a.response_ms asc,a.submitted_at asc,a.participant_id asc
    limit 1;
    if v_winner_answer.id is not null then
      update public.quiz_answers set awarded_points=coalesce(v_round.points_snapshot,0) where id=v_winner_answer.id;
      select jsonb_build_array(jsonb_build_object(
        'participant_id',p.id,'display_name',p.display_name,'answer',v_winner_answer.numeric_value,
        'difference',abs(v_winner_answer.numeric_value-v_key.correct_number),'response_ms',v_winner_answer.response_ms,'points',coalesce(v_round.points_snapshot,0)
      )) into v_winners from public.quiz_participants p where p.id=v_winner_answer.participant_id;
    end if;
    v_result:='Valor correto: '||v_key.correct_number::text;
  end if;

  update public.quiz_participants p
  set total_points=(
    select coalesce(sum(a.awarded_points),0)::integer
    from public.quiz_answers a join public.quiz_rounds rr on rr.id=a.round_id
    where a.participant_id=p.id and rr.room_id=p_room_id
  )
  where p.room_id=p_room_id;

  select count(*) into v_count from public.quiz_answers where round_id=v_round.id;
  select coalesce(jsonb_agg(jsonb_build_object('participant_id',x.id,'display_name',x.display_name,'total_points',x.total_points,'joined_at',x.joined_at) order by x.total_points desc,x.joined_at asc,x.id asc),'[]'::jsonb)
  into v_rank
  from (
    select id,display_name,total_points,joined_at
    from public.quiz_participants where room_id=p_room_id
    order by total_points desc,joined_at asc,id asc limit 200
  ) x;

  update public.quiz_rounds
  set status='closed',closed_at=clock_timestamp(),result_text=v_result,
      answer_count_snapshot=v_count,ranking_snapshot=v_rank,winner_snapshot=v_winners,result_locked=true
  where id=v_round.id;

  select count(*) into v_round_count from public.quiz_rounds where room_id=p_room_id;
  if v_round_count>=v_room.planned_rounds then
    update public.quiz_rooms
    set phase='finished',game_status='finished',status='finished',finished_at=clock_timestamp(),final_ranking_snapshot=v_rank
    where id=p_room_id;
    v_finished:=true;
  else
    update public.quiz_rooms set phase='result',game_status='running' where id=p_room_id;
  end if;

  perform private.audit_event(p_room_id,v_uid,'round_closed','round',v_round.id,jsonb_build_object('round_no',v_round.round_no,'answers',v_count,'finished',v_finished));
  perform private.publish_room_event(p_room_id,case when v_finished then 'quiz_finished' else 'round_closed' end,jsonb_build_object('round_no',v_round.round_no));
  return jsonb_build_object('already_applied',false,'round_id',v_round.id,'answers',v_count,'finished',v_finished,'result_text',v_result);
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

  return jsonb_build_object(
    'room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'game_status',v_room.game_status,'phase',v_room.phase,'state_version',v_room.state_version),
    'round',v_round_json,'ranking',v_rank,'server_now',v_now
  );
end $$;
revoke all on function public.get_game_state(uuid) from public, anon;
grant execute on function public.get_game_state(uuid) to authenticated;

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
    'room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'game_status',v_room.game_status,'phase',v_room.phase,'state_version',v_room.state_version,'started_at',v_room.started_at,'finished_at',v_room.finished_at),
    'round',v_round_json,'ranking',v_rank,'participant_count',v_participants,'active_count',v_active,'answer_count',v_answers,
    'used_rounds',v_used,'queued_count',v_queued,'server_now',v_now
  );
end $$;
revoke all on function public.admin_get_room_state(uuid) from public;
grant execute on function public.admin_get_room_state(uuid) to authenticated;

create or replace function public.get_public_display_state(p_code text)
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
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;
  if not exists(select 1 from public.quiz_realtime_memberships where user_id=v_uid and room_id=v_room.id and role in ('display','admin','participant')) then
    raise exception 'Tela não autorizada para esta sala';
  end if;

  select * into v_round from public.quiz_rounds where room_id=v_room.id order by round_no desc limit 1;
  if found then
    v_round_json:=jsonb_build_object(
      'id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,'closed_at',v_round.closed_at,
      'closes_at',v_round.closes_at,'time_limit_seconds',v_round.time_limit_seconds,
      'prompt',v_round.prompt_snapshot,'question_type',v_round.question_type_snapshot,'options',coalesce(v_round.options_snapshot,'[]'::jsonb),'points',v_round.points_snapshot,
      'result_text',case when v_round.status='closed' then v_round.result_text else null end,
      'winner_snapshot',case when v_round.status='closed' then v_round.winner_snapshot else null end
    );
  end if;

  if v_room.phase in ('result','finished') and v_round.id is not null then
    v_rank:=coalesce(v_round.ranking_snapshot,v_room.final_ranking_snapshot,'[]'::jsonb);
  else
    v_rank:='[]'::jsonb;
  end if;
  select count(*) into v_participants from public.quiz_participants where room_id=v_room.id;
  select count(*) into v_active from public.quiz_participants where room_id=v_room.id and last_seen_at>=v_now-interval '90 seconds';
  select count(*) into v_used from public.quiz_rounds where room_id=v_room.id;
  if v_round.id is not null and v_round.status='open' then select count(*) into v_answers from public.quiz_answers where round_id=v_round.id; else v_answers:=coalesce(v_round.answer_count_snapshot,0); end if;

  return jsonb_build_object(
    'room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'game_status',v_room.game_status,'phase',v_room.phase,'state_version',v_room.state_version),
    'round',v_round_json,'ranking',v_rank,'participant_count',v_participants,'active_count',v_active,'answer_count',v_answers,'used_rounds',v_used,'server_now',v_now
  );
end $$;
revoke all on function public.get_public_display_state(text) from public, anon;
grant execute on function public.get_public_display_state(text) to authenticated;

create or replace function public.admin_list_audit(p_room_id uuid,p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_result jsonb;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_result
  from (
    select id,action,entity_type,entity_id,details,created_at
    from public.quiz_audit_log
    where room_id=p_room_id
    order by created_at desc
    limit greatest(1,least(200,coalesce(p_limit,50)))
  ) x;
  return v_result;
end $$;
revoke all on function public.admin_list_audit(uuid,integer) from public;
grant execute on function public.admin_list_audit(uuid,integer) to authenticated;

-- O admin continua recebendo as respostas corretas somente pelas RPCs administrativas existentes.
-- As tabelas públicas continuam sem acesso direto para anon/authenticated.
grant usage on schema public to authenticated;

create or replace function public.admin_list_room_queue(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_result jsonb;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',rq.id,'question_id',rq.question_id,'position',rq.position,'status',rq.status,'round_id',rq.round_id,
    'prompt',rq.prompt_snapshot,'question_type',rq.question_type_snapshot,'points',rq.points_snapshot,
    'time_limit_seconds',rq.time_limit_snapshot,'archived',q.archived_at is not null
  ) order by rq.position,rq.added_at),'[]'::jsonb)
  into v_result
  from public.quiz_room_queue rq
  left join public.quiz_questions q on q.id=rq.question_id
  where rq.room_id=p_room_id;
  return v_result;
end $$;
revoke all on function public.admin_list_room_queue(uuid) from public;
grant execute on function public.admin_list_room_queue(uuid) to authenticated;

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
declare
  v_uid uuid:=auth.uid();
  v_id uuid;
  v_limit integer;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if length(trim(coalesce(p_prompt,'')))<1 then raise exception 'Pergunta obrigatória'; end if;
  if p_type not in ('choice','numeric') then raise exception 'Tipo inválido'; end if;
  v_limit:=greatest(5,least(600,coalesce(p_time_limit,30)));
  if p_type='choice' then
    if jsonb_typeof(p_options)<>'array' or jsonb_array_length(p_options)<>4 or p_correct_choice not in ('A','B','C','D') then raise exception 'Alternativas inválidas'; end if;
    if exists(select 1 from jsonb_array_elements(p_options) o where coalesce(trim(o->>'text'),'')='') then raise exception 'Alternativas vazias não são permitidas'; end if;
    p_correct_number:=null;
  else
    if p_correct_number is null or abs(p_correct_number)>1000000000000000::numeric then raise exception 'Valor correto inválido'; end if;
    p_options:=null;p_correct_choice:=null;
  end if;
  insert into public.quiz_questions(created_by,prompt,question_type,options,points,time_limit_seconds)
  values(v_uid,trim(p_prompt),p_type,p_options,greatest(1,least(100000,coalesce(p_points,1000))),v_limit)
  returning id into v_id;
  insert into private.quiz_answer_keys(question_id,correct_choice,correct_number) values(v_id,p_correct_choice,p_correct_number);
  perform private.audit_event(null,v_uid,'question_created','question',v_id,jsonb_build_object('question_type',p_type,'points',p_points,'time_limit_seconds',v_limit));
  return v_id;
end $$;
revoke all on function public.admin_create_question_v2(text,text,jsonb,text,numeric,integer,integer) from public;
grant execute on function public.admin_create_question_v2(text,text,jsonb,text,numeric,integer,integer) to authenticated;

create or replace function public.admin_set_question_archived(p_question_id uuid,p_archived boolean)
returns void language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  update public.quiz_questions
  set archived_at=case when p_archived then clock_timestamp() else null end
  where id=p_question_id;
  if not found then raise exception 'Pergunta não encontrada'; end if;
  perform private.audit_event(null,v_uid,case when p_archived then 'question_archived' else 'question_restored' end,'question',p_question_id,'{}'::jsonb);
end $$;
revoke all on function public.admin_set_question_archived(uuid,boolean) from public;
grant execute on function public.admin_set_question_archived(uuid,boolean) to authenticated;

-- Bloqueia RPCs antigas que não aplicam o fluxo transacional/snapshot da v1.5.
revoke execute on function public.admin_create_room(text) from authenticated;
revoke execute on function public.admin_create_question(text,text,jsonb,text,numeric,integer) from authenticated;
revoke execute on function public.admin_list_questions() from authenticated;
revoke execute on function public.admin_open_round(uuid,uuid) from authenticated;
revoke usage on schema public from anon;
