-- QuizRounds v3.32 — desempenho das perguntas e resumo final do evento

create or replace function private.quiz_event_insights(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_out jsonb;
begin
  with stats as (
    select
      r.id as round_id,
      r.round_no,
      coalesce(r.prompt_snapshot, 'Pergunta') as prompt,
      r.question_type_snapshot as question_type,
      count(a.id)::int as answer_count,
      count(a.id) filter (
        where (r.question_type_snapshot='choice' and a.choice_value=k.correct_choice)
           or (r.question_type_snapshot='numeric' and a.numeric_value=k.correct_number)
      )::int as correct_count,
      (count(a.id) - count(a.id) filter (
        where (r.question_type_snapshot='choice' and a.choice_value=k.correct_choice)
           or (r.question_type_snapshot='numeric' and a.numeric_value=k.correct_number)
      ))::int as wrong_count,
      case when count(a.id)>0 then round(
        100.0 * (count(a.id) filter (
          where (r.question_type_snapshot='choice' and a.choice_value=k.correct_choice)
             or (r.question_type_snapshot='numeric' and a.numeric_value=k.correct_number)
        ))::numeric / count(a.id)::numeric,
        1
      ) else 0::numeric end as accuracy_pct
    from public.quiz_rounds r
    join private.quiz_round_answer_keys k on k.round_id=r.id
    left join public.quiz_answers a on a.round_id=r.id
    where r.room_id=p_room_id
      and r.status='closed'
      and not coalesce(r.annulled,false)
    group by r.id,r.round_no,r.prompt_snapshot,r.question_type_snapshot,k.correct_choice,k.correct_number
  )
  select jsonb_build_object(
    'rounds', coalesce((select jsonb_agg(to_jsonb(s) order by s.round_no) from stats s),'[]'::jsonb),
    'most_correct', (select to_jsonb(s) from stats s where s.answer_count>0 order by s.correct_count desc,s.accuracy_pct desc,s.answer_count desc,s.round_no asc limit 1),
    'most_wrong', (select to_jsonb(s) from stats s where s.answer_count>0 order by s.wrong_count desc,s.accuracy_pct asc,s.answer_count desc,s.round_no asc limit 1)
  ) into v_out;
  return coalesce(v_out,jsonb_build_object('rounds','[]'::jsonb,'most_correct',null,'most_wrong',null));
end
$$;

revoke all on function private.quiz_event_insights(uuid) from public, anon, authenticated;

create or replace function public.admin_get_event_insights(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid:=auth.uid();
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if not exists(select 1 from public.quiz_rooms r where r.id=p_room_id and r.created_by=v_uid) then
    raise exception 'Sala inválida';
  end if;
  return private.quiz_event_insights(p_room_id);
end
$$;

revoke all on function public.admin_get_event_insights(uuid) from public, anon;
grant execute on function public.admin_get_event_insights(uuid) to authenticated;

create or replace function public.get_public_event_insights(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code));
  if not found then raise exception 'Sala não encontrada'; end if;
  if not private.is_admin(v_uid)
     and not exists(
       select 1 from public.quiz_realtime_memberships m
       where m.user_id=v_uid and m.room_id=v_room.id
     ) then
    raise exception 'Acesso não autorizado';
  end if;
  if v_room.phase<>'finished' then
    return jsonb_build_object('rounds','[]'::jsonb,'most_correct',null,'most_wrong',null);
  end if;
  return private.quiz_event_insights(v_room.id);
end
$$;

revoke all on function public.get_public_event_insights(text) from public, anon;
grant execute on function public.get_public_event_insights(text) to authenticated;
