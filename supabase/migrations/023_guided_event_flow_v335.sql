-- QuizRounds v3.36 — fluxo guiado, coleções, partidas recentes e insights ampliados

create table if not exists public.quiz_question_collections (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  name text not null,
  question_ids jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.quiz_question_collections enable row level security;
revoke all on public.quiz_question_collections from public, anon, authenticated;

create or replace function public.admin_save_question_collection(p_name text,p_question_ids jsonb)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_id uuid;
  v_count int;
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if length(trim(coalesce(p_name,'')))<1 then raise exception 'Nome da coleção obrigatório'; end if;
  if jsonb_typeof(p_question_ids)<>'array' then raise exception 'Lista de perguntas inválida'; end if;
  v_count:=jsonb_array_length(p_question_ids);
  if v_count<1 or v_count>200 then raise exception 'A coleção deve ter entre 1 e 200 perguntas'; end if;
  if exists(
    select 1
    from jsonb_array_elements_text(p_question_ids) x(id)
    left join public.quiz_questions q on q.id=x.id::uuid and q.created_by=v_uid
    where q.id is null
  ) then raise exception 'A coleção contém pergunta inválida'; end if;
  insert into public.quiz_question_collections(created_by,name,question_ids)
  values(v_uid,left(trim(p_name),80),p_question_ids)
  returning id into v_id;
  return v_id;
end
$$;
revoke all on function public.admin_save_question_collection(text,jsonb) from public, anon;
grant execute on function public.admin_save_question_collection(text,jsonb) to authenticated;

create or replace function public.admin_list_question_collections()
returns jsonb
language sql
security definer
set search_path=''
as $$
  select case when private.is_admin(auth.uid()) then coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'name',c.name,
    'question_count',jsonb_array_length(c.question_ids),
    'created_at',c.created_at,
    'updated_at',c.updated_at
  ) order by c.updated_at desc),'[]'::jsonb) else '[]'::jsonb end
  from public.quiz_question_collections c
  where c.created_by=auth.uid()
$$;
revoke all on function public.admin_list_question_collections() from public, anon;
grant execute on function public.admin_list_question_collections() to authenticated;

create or replace function public.admin_get_question_collection(p_collection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_row public.quiz_question_collections;
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_row from public.quiz_question_collections where id=p_collection_id and created_by=v_uid;
  if not found then raise exception 'Coleção não encontrada'; end if;
  return jsonb_build_object('id',v_row.id,'name',v_row.name,'question_ids',v_row.question_ids,'updated_at',v_row.updated_at);
end
$$;
revoke all on function public.admin_get_question_collection(uuid) from public, anon;
grant execute on function public.admin_get_question_collection(uuid) to authenticated;

create or replace function public.admin_delete_question_collection(p_collection_id uuid)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_count int;
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  delete from public.quiz_question_collections where id=p_collection_id and created_by=v_uid;
  get diagnostics v_count=row_count;
  return v_count>0;
end
$$;
revoke all on function public.admin_delete_question_collection(uuid) from public, anon;
grant execute on function public.admin_delete_question_collection(uuid) to authenticated;

create or replace function public.admin_list_recent_rooms(p_limit integer default 8)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_limit int:=greatest(1,least(20,coalesce(p_limit,8)));
  v_out jsonb;
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  into v_out
  from (
    select r.id,r.code,r.title,r.status,r.game_status,r.phase,r.created_at,r.started_at,r.finished_at,r.planned_rounds,r.is_rehearsal,
      (select count(*)::int from public.quiz_participants p where p.room_id=r.id and not p.kicked) as participant_count,
      (select count(*)::int from public.quiz_room_queue q where q.room_id=r.id and q.status='queued') as queued_count,
      (select count(*)::int from public.quiz_rounds rr where rr.room_id=r.id) as used_rounds
    from public.quiz_rooms r
    where r.created_by=v_uid
    order by r.created_at desc
    limit v_limit
  ) x;
  return v_out;
end
$$;
revoke all on function public.admin_list_recent_rooms(integer) from public, anon;
grant execute on function public.admin_list_recent_rooms(integer) to authenticated;

create or replace function public.admin_question_bank_stats()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_out jsonb;
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  with stats as (
    select
      q.id as question_id,
      count(distinct r.id)::int as play_count,
      count(a.id)::int as answer_count,
      count(a.id) filter (
        where (r.question_type_snapshot='choice' and a.choice_value=k.correct_choice)
           or (r.question_type_snapshot='numeric' and a.awarded_points>0)
      )::int as correct_count,
      case when count(a.id)>0 then round(
        100.0 * (count(a.id) filter (
          where (r.question_type_snapshot='choice' and a.choice_value=k.correct_choice)
             or (r.question_type_snapshot='numeric' and a.awarded_points>0)
        ))::numeric / count(a.id)::numeric,1
      ) else null end as accuracy_pct,
      case when count(a.id)>0 then round(avg(a.response_ms)::numeric,0) else null end as avg_response_ms
    from public.quiz_questions q
    left join public.quiz_rounds r on r.question_id=q.id and r.status='closed' and not coalesce(r.annulled,false)
    left join private.quiz_round_answer_keys k on k.round_id=r.id
    left join public.quiz_answers a on a.round_id=r.id
    where q.created_by=v_uid
    group by q.id
  )
  select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) into v_out from stats s;
  return v_out;
end
$$;
revoke all on function public.admin_question_bank_stats() from public, anon;
grant execute on function public.admin_question_bank_stats() to authenticated;

create or replace function private.quiz_event_insights(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_out jsonb;
begin
  with stats as (
    select
      r.id as round_id,
      r.question_id,
      r.round_no,
      coalesce(r.prompt_snapshot,'Pergunta') as prompt,
      r.question_type_snapshot as question_type,
      count(a.id)::int as answer_count,
      count(a.id) filter (
        where (r.question_type_snapshot='choice' and a.choice_value=k.correct_choice)
           or (r.question_type_snapshot='numeric' and a.awarded_points>0)
      )::int as correct_count,
      (count(a.id)-count(a.id) filter (
        where (r.question_type_snapshot='choice' and a.choice_value=k.correct_choice)
           or (r.question_type_snapshot='numeric' and a.awarded_points>0)
      ))::int as wrong_count,
      case when count(a.id)>0 then round(
        100.0*(count(a.id) filter (
          where (r.question_type_snapshot='choice' and a.choice_value=k.correct_choice)
             or (r.question_type_snapshot='numeric' and a.awarded_points>0)
        ))::numeric/count(a.id)::numeric,1
      ) else 0::numeric end as accuracy_pct,
      case when count(a.id)>0 then round(avg(a.response_ms)::numeric,0) else null end as avg_response_ms,
      min(a.response_ms)::int as fastest_response_ms,
      max(a.response_ms)::int as slowest_response_ms
    from public.quiz_rounds r
    join private.quiz_round_answer_keys k on k.round_id=r.id
    left join public.quiz_answers a on a.round_id=r.id
    where r.room_id=p_room_id and r.status='closed' and not coalesce(r.annulled,false)
    group by r.id,r.question_id,r.round_no,r.prompt_snapshot,r.question_type_snapshot,k.correct_choice,k.correct_number
  ), summary as (
    select
      (select count(*)::int from public.quiz_participants p where p.room_id=p_room_id and not p.kicked) as participant_count,
      coalesce(sum(s.answer_count),0)::int as answer_count,
      coalesce(sum(s.correct_count),0)::int as correct_count,
      case when coalesce(sum(s.answer_count),0)>0 then round(100.0*sum(s.correct_count)::numeric/sum(s.answer_count)::numeric,1) else 0::numeric end as accuracy_pct,
      case when count(*) filter (where s.avg_response_ms is not null)>0 then round(avg(s.avg_response_ms)::numeric,0) else null end as avg_response_ms,
      count(*)::int as rounds_count
    from stats s
  )
  select jsonb_build_object(
    'rounds',coalesce((select jsonb_agg(to_jsonb(s) order by s.round_no) from stats s),'[]'::jsonb),
    'summary',(select to_jsonb(x) from summary x),
    'most_correct',(select to_jsonb(s) from stats s where s.answer_count>0 order by s.correct_count desc,s.accuracy_pct desc,s.answer_count desc,s.round_no asc limit 1),
    'most_wrong',(select to_jsonb(s) from stats s where s.answer_count>0 order by s.wrong_count desc,s.accuracy_pct asc,s.answer_count desc,s.round_no asc limit 1),
    'fastest',(select to_jsonb(s) from stats s where s.avg_response_ms is not null order by s.avg_response_ms asc,s.round_no asc limit 1),
    'slowest',(select to_jsonb(s) from stats s where s.avg_response_ms is not null order by s.avg_response_ms desc,s.round_no asc limit 1)
  ) into v_out;
  return coalesce(v_out,jsonb_build_object('rounds','[]'::jsonb,'summary',jsonb_build_object('participant_count',0,'answer_count',0,'correct_count',0,'accuracy_pct',0,'avg_response_ms',null,'rounds_count',0),'most_correct',null,'most_wrong',null,'fastest',null,'slowest',null));
end
$$;
revoke all on function private.quiz_event_insights(uuid) from public, anon, authenticated;

-- Mantém os wrappers existentes apontando para a versão ampliada da função privada.
create or replace function public.admin_get_event_insights(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if not exists(select 1 from public.quiz_rooms r where r.id=p_room_id and r.created_by=v_uid) then raise exception 'Sala inválida'; end if;
  return private.quiz_event_insights(p_room_id);
end
$$;
revoke all on function public.admin_get_event_insights(uuid) from public, anon;
grant execute on function public.admin_get_event_insights(uuid) to authenticated;

create or replace function public.get_public_event_insights(p_code text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code));
  if not found then raise exception 'Sala não encontrada'; end if;
  if not private.is_admin(v_uid) and not exists(select 1 from public.quiz_realtime_memberships m where m.user_id=v_uid and m.room_id=v_room.id) then raise exception 'Acesso não autorizado'; end if;
  if v_room.phase<>'finished' then return jsonb_build_object('rounds','[]'::jsonb,'summary',jsonb_build_object('participant_count',0,'answer_count',0,'correct_count',0,'accuracy_pct',0,'avg_response_ms',null,'rounds_count',0),'most_correct',null,'most_wrong',null,'fastest',null,'slowest',null); end if;
  return private.quiz_event_insights(v_room.id);
end
$$;
revoke all on function public.get_public_event_insights(text) from public, anon;
grant execute on function public.get_public_event_insights(text) to authenticated;
