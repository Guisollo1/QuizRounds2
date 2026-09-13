-- QuizRounds v3.36 — precisão dos insights finais
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
      max(a.response_ms)::int as slowest_response_ms,
      coalesce(sum(a.response_ms),0)::bigint as response_ms_total
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
      case when coalesce(sum(s.answer_count),0)>0 then round(sum(s.response_ms_total)::numeric/sum(s.answer_count)::numeric,0) else null end as avg_response_ms,
      count(*)::int as rounds_count
    from stats s
  )
  select jsonb_build_object(
    'rounds',coalesce((select jsonb_agg((to_jsonb(s)-'response_ms_total') order by s.round_no) from stats s),'[]'::jsonb),
    'summary',(select to_jsonb(x) from summary x),
    'most_correct',(select to_jsonb(s)-'response_ms_total' from stats s where s.answer_count>0 order by s.accuracy_pct desc,s.correct_count desc,s.answer_count desc,s.round_no asc limit 1),
    'most_wrong',(select to_jsonb(s)-'response_ms_total' from stats s where s.answer_count>0 order by s.accuracy_pct asc,s.wrong_count desc,s.answer_count desc,s.round_no asc limit 1),
    'fastest',(select to_jsonb(s)-'response_ms_total' from stats s where s.avg_response_ms is not null order by s.avg_response_ms asc,s.round_no asc limit 1),
    'slowest',(select to_jsonb(s)-'response_ms_total' from stats s where s.avg_response_ms is not null order by s.avg_response_ms desc,s.round_no asc limit 1)
  ) into v_out;
  return coalesce(v_out,jsonb_build_object('rounds','[]'::jsonb,'summary',jsonb_build_object('participant_count',0,'answer_count',0,'correct_count',0,'accuracy_pct',0,'avg_response_ms',null,'rounds_count',0),'most_correct',null,'most_wrong',null,'fastest',null,'slowest',null));
end
$$;
revoke all on function private.quiz_event_insights(uuid) from public, anon, authenticated;
