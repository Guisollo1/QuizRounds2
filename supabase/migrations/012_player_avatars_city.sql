-- QuizRounds v3.15 — avatares de jogador + cidade animada do telão.
-- Preserva o fluxo antigo: join_quiz_room(text,text) continua disponível.

alter table public.quiz_participants
  add column if not exists avatar_key text not null default 'robot';

create or replace function private.normalize_avatar_key(p_key text)
returns text
language sql
immutable
security definer
set search_path=''
as $$
  select case lower(coalesce(trim(p_key),''))
    when 'fox' then 'fox'
    when 'robot' then 'robot'
    when 'cat' then 'cat'
    when 'astro' then 'astro'
    when 'ninja' then 'ninja'
    when 'panda' then 'panda'
    when 'alien' then 'alien'
    when 'lion' then 'lion'
    when 'frog' then 'frog'
    when 'unicorn' then 'unicorn'
    when 'shark' then 'shark'
    when 'owl' then 'owl'
    else 'robot'
  end
$$;
revoke all on function private.normalize_avatar_key(text) from public;

-- Nova entrada com avatar. Reutiliza todas as validações e regras da função estável.
create or replace function public.join_quiz_room_v2(p_code text,p_name text,p_avatar_key text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_result jsonb;
  v_room_id uuid;
  v_part jsonb;
  v_avatar text:=private.normalize_avatar_key(p_avatar_key);
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  v_result:=public.join_quiz_room(p_code,p_name);
  v_room_id:=(v_result->'room'->>'id')::uuid;

  update public.quiz_participants
  set avatar_key=v_avatar,
      last_seen_at=clock_timestamp()
  where room_id=v_room_id and user_id=v_uid
  returning to_jsonb(public.quiz_participants.*) into v_part;

  if v_part is null then raise exception 'Participante não encontrado após entrada'; end if;
  perform private.notify_room(v_room_id);
  return jsonb_set(v_result,'{participant}',v_part,true);
end
$$;
revoke all on function public.join_quiz_room_v2(text,text,text) from public,anon;
grant execute on function public.join_quiz_room_v2(text,text,text) to authenticated;

create or replace function public.player_set_avatar(p_room_id uuid,p_avatar_key text)
returns text
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_avatar text:=private.normalize_avatar_key(p_avatar_key);
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  update public.quiz_participants
  set avatar_key=v_avatar,last_seen_at=clock_timestamp()
  where room_id=p_room_id and user_id=v_uid and not kicked;
  if not found then raise exception 'Participante não pertence à sala'; end if;
  perform private.notify_room(p_room_id);
  return v_avatar;
end
$$;
revoke all on function public.player_set_avatar(uuid,text) from public,anon;
grant execute on function public.player_set_avatar(uuid,text) to authenticated;

-- Ranking passa a transportar o avatar sem alterar sua ordenação.
create or replace function private.generate_ranking(p_room_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'participant_id',x.id,'display_name',x.display_name,'avatar_key',x.avatar_key,'total_points',x.total_points,
    'tiebreak_points',x.tiebreak_points,'current_streak',x.current_streak,'best_streak',x.best_streak,
    'joined_at',x.joined_at,'ready',x.ready,'connected',x.last_seen_at>=clock_timestamp()-interval '90 seconds'
  ) order by x.total_points desc,x.tiebreak_points desc,x.joined_at asc,x.id asc),'[]'::jsonb)
  from (
    select * from public.quiz_participants
    where room_id=p_room_id and not kicked
    order by total_points desc,tiebreak_points desc,joined_at asc,id asc limit 500
  ) x
$$;
revoke all on function private.generate_ranking(uuid) from public;

-- ADM recebe o avatar junto da telemetria já existente.
create or replace function public.admin_list_participants(p_room_id uuid)
returns jsonb
language sql
security definer
set search_path=''
as $$
  select case when private.is_admin(auth.uid()) then coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'user_id',p.user_id,'display_name',p.display_name,'avatar_key',p.avatar_key,'total_points',p.total_points,'ready',p.ready,'kicked',p.kicked,'last_seen_at',p.last_seen_at,
    'current_streak',p.current_streak,'best_streak',p.best_streak,
    'answer_count',(select count(*) from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id where r.room_id=p_room_id and a.participant_id=p.id),
    'missed_count',greatest(0,(select count(*) from public.quiz_rounds r where r.room_id=p_room_id and r.status='closed')-(select count(*) from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id where r.room_id=p_room_id and a.participant_id=p.id)
  )) order by p.total_points desc,p.joined_at),'[]'::jsonb) else '[]'::jsonb end
  from public.quiz_participants p where p.room_id=p_room_id
$$;
revoke all on function public.admin_list_participants(uuid) from public,anon;
grant execute on function public.admin_list_participants(uuid) to authenticated;

-- Roster dedicado ao telão: mantém o estado principal enxuto e evita alterar a RPC estável.
create or replace function public.get_public_avatar_roster(p_code text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_now timestamptz:=clock_timestamp();
  v_rows jsonb;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room
  from public.quiz_rooms
  where code=upper(trim(p_code))
  order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;

  if not exists(
    select 1 from public.quiz_realtime_memberships
    where user_id=v_uid and room_id=v_room.id and role in ('display','admin','participant')
  ) then raise exception 'Tela não autorizada'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'participant_id',p.id,
    'display_name',p.display_name,
    'avatar_key',p.avatar_key,
    'total_points',p.total_points,
    'connected',p.last_seen_at>=v_now-interval '90 seconds',
    'joined_at',p.joined_at
  ) order by p.joined_at,p.id),'[]'::jsonb)
  into v_rows
  from public.quiz_participants p
  where p.room_id=v_room.id and not p.kicked;

  return v_rows;
end
$$;
revoke all on function public.get_public_avatar_roster(text) from public,anon;
grant execute on function public.get_public_avatar_roster(text) to authenticated;
