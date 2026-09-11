-- QuizRounds v3.36 — apresentação final em etapas + destaques avançados

create or replace function private.quiz_event_insights(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_out jsonb;
begin
  with closed_rounds as (
    select r.*,k.correct_choice,k.correct_number
    from public.quiz_rounds r
    join private.quiz_round_answer_keys k on k.round_id=r.id
    where r.room_id=p_room_id
      and r.status='closed'
      and not coalesce(r.annulled,false)
  ), choice_counts as (
    select
      r.id as round_id,
      greatest(1,jsonb_array_length(coalesce(r.options_snapshot,'[]'::jsonb)))::int as option_count,
      a.choice_value,
      count(*)::int as choice_count
    from closed_rounds r
    join public.quiz_answers a on a.round_id=r.id
    where r.question_type_snapshot='choice' and a.choice_value is not null
    group by r.id,r.options_snapshot,a.choice_value
  ), choice_balance as (
    select
      c.round_id,
      max(c.option_count)::int as option_count,
      case
        when sum(c.choice_count)>0 and max(c.option_count)>1 then round(
          greatest(0,least(100,
            100.0 * (
              1 - (
                (max(c.choice_count)::numeric / sum(c.choice_count)::numeric) - (1.0 / max(c.option_count)::numeric)
              ) / (1 - (1.0 / max(c.option_count)::numeric))
            )
          )),1
        )
        else null
      end as balance_pct
    from choice_counts c
    group by c.round_id
  ), stats as (
    select
      r.id as round_id,
      r.question_id,
      r.round_no,
      coalesce(r.prompt_snapshot,'Pergunta') as prompt,
      r.question_type_snapshot as question_type,
      count(a.id)::int as answer_count,
      count(a.id) filter (
        where (r.question_type_snapshot='choice' and a.choice_value=r.correct_choice)
           or (r.question_type_snapshot='numeric' and a.awarded_points>0)
      )::int as correct_count,
      (count(a.id)-count(a.id) filter (
        where (r.question_type_snapshot='choice' and a.choice_value=r.correct_choice)
           or (r.question_type_snapshot='numeric' and a.awarded_points>0)
      ))::int as wrong_count,
      case when count(a.id)>0 then round(
        100.0*(count(a.id) filter (
          where (r.question_type_snapshot='choice' and a.choice_value=r.correct_choice)
             or (r.question_type_snapshot='numeric' and a.awarded_points>0)
        ))::numeric/count(a.id)::numeric,1
      ) else 0::numeric end as accuracy_pct,
      case when count(a.id)>0 then round(avg(a.response_ms)::numeric,0) else null end as avg_response_ms,
      min(a.response_ms)::int as fastest_response_ms,
      max(a.response_ms)::int as slowest_response_ms,
      coalesce(sum(a.response_ms),0)::bigint as response_ms_total,
      cb.option_count,
      cb.balance_pct
    from closed_rounds r
    left join public.quiz_answers a on a.round_id=r.id
    left join choice_balance cb on cb.round_id=r.id
    group by r.id,r.question_id,r.round_no,r.prompt_snapshot,r.question_type_snapshot,r.correct_choice,r.correct_number,cb.option_count,cb.balance_pct
  ), summary as (
    select
      (select count(*)::int from public.quiz_participants p where p.room_id=p_room_id and not p.kicked) as participant_count,
      coalesce(sum(s.answer_count),0)::int as answer_count,
      coalesce(sum(s.correct_count),0)::int as correct_count,
      (coalesce(sum(s.answer_count),0)-coalesce(sum(s.correct_count),0))::int as wrong_count,
      case when coalesce(sum(s.answer_count),0)>0 then round(100.0*sum(s.correct_count)::numeric/sum(s.answer_count)::numeric,1) else 0::numeric end as accuracy_pct,
      case when coalesce(sum(s.answer_count),0)>0 then round(sum(s.response_ms_total)::numeric/sum(s.answer_count)::numeric,0) else null end as avg_response_ms,
      count(*)::int as rounds_count
    from stats s
  ), participant_stats as (
    select
      p.id as participant_id,
      p.display_name,
      p.avatar_key,
      p.total_points,
      p.best_streak,
      count(a.id) filter (where r.id is not null)::int as answer_count,
      count(a.id) filter (
        where r.id is not null and (
          (r.question_type_snapshot='choice' and a.choice_value=r.correct_choice)
          or (r.question_type_snapshot='numeric' and a.awarded_points>0)
        )
      )::int as correct_count,
      case when count(a.id) filter (where r.id is not null)>0 then round(
        100.0*(count(a.id) filter (
          where r.id is not null and (
            (r.question_type_snapshot='choice' and a.choice_value=r.correct_choice)
            or (r.question_type_snapshot='numeric' and a.awarded_points>0)
          )
        ))::numeric/(count(a.id) filter (where r.id is not null))::numeric,1
      ) else 0::numeric end as accuracy_pct,
      round((avg(a.response_ms) filter (
        where (r.question_type_snapshot='choice' and a.choice_value=r.correct_choice)
           or (r.question_type_snapshot='numeric' and a.awarded_points>0)
      ))::numeric,0) as avg_correct_response_ms
    from public.quiz_participants p
    left join public.quiz_answers a on a.participant_id=p.id
    left join closed_rounds r on r.id=a.round_id
    where p.room_id=p_room_id and not p.kicked
    group by p.id,p.display_name,p.avatar_key,p.total_points,p.best_streak
  ), fastest_correct as (
    select
      p.id as participant_id,
      p.display_name,
      p.avatar_key,
      r.round_no,
      coalesce(r.prompt_snapshot,'Pergunta') as prompt,
      a.response_ms
    from closed_rounds r
    join public.quiz_answers a on a.round_id=r.id
    join public.quiz_participants p on p.id=a.participant_id
    where not p.kicked
      and (
        (r.question_type_snapshot='choice' and a.choice_value=r.correct_choice)
        or (r.question_type_snapshot='numeric' and a.awarded_points>0)
      )
    order by a.response_ms asc,a.submitted_at asc,a.id asc
    limit 1
  ), mover_rows as (
    select
      r.round_no,
      (m.value->>'participant_id')::uuid as participant_id,
      coalesce(m.value->>'display_name','Jogador') as display_name,
      coalesce((m.value->>'change')::int,0) as change
    from public.quiz_rounds r
    cross join lateral jsonb_array_elements(coalesce(r.ranking_movers_snapshot,'[]'::jsonb)) m(value)
    where r.room_id=p_room_id
      and r.status='closed'
      and not coalesce(r.annulled,false)
      and coalesce((m.value->>'change')::int,0)>0
  )
  select jsonb_build_object(
    'rounds',coalesce((select jsonb_agg((to_jsonb(s)-'response_ms_total') order by s.round_no) from stats s),'[]'::jsonb),
    'summary',(select to_jsonb(x) from summary x),
    'most_correct',(select to_jsonb(s)-'response_ms_total' from stats s where s.answer_count>0 order by s.accuracy_pct desc,s.correct_count desc,s.answer_count desc,s.round_no asc limit 1),
    'most_wrong',(select to_jsonb(s)-'response_ms_total' from stats s where s.answer_count>0 order by s.accuracy_pct asc,s.wrong_count desc,s.answer_count desc,s.round_no asc limit 1),
    'fastest',(select to_jsonb(s)-'response_ms_total' from stats s where s.avg_response_ms is not null order by s.avg_response_ms asc,s.round_no asc limit 1),
    'slowest',(select to_jsonb(s)-'response_ms_total' from stats s where s.avg_response_ms is not null order by s.avg_response_ms desc,s.round_no asc limit 1),
    'most_balanced',(select to_jsonb(s)-'response_ms_total' from stats s where s.question_type='choice' and s.answer_count>0 and s.balance_pct is not null order by s.balance_pct desc,s.answer_count desc,s.round_no asc limit 1),
    'best_accuracy',(
      select to_jsonb(ps)
      from participant_stats ps,(select rounds_count from summary) sm
      where ps.answer_count>=greatest(1,ceil(sm.rounds_count*0.5)::int)
      order by ps.accuracy_pct desc,ps.answer_count desc,ps.correct_count desc,ps.avg_correct_response_ms asc nulls last,ps.total_points desc
      limit 1
    ),
    'best_streak',(
      select jsonb_build_object('participant_id',p.id,'display_name',p.display_name,'avatar_key',p.avatar_key,'best_streak',p.best_streak,'total_points',p.total_points)
      from public.quiz_participants p
      where p.room_id=p_room_id and not p.kicked and p.best_streak>0
      order by p.best_streak desc,p.total_points desc,p.joined_at asc
      limit 1
    ),
    'fastest_correct',(select to_jsonb(fc) from fastest_correct fc),
    'biggest_climb',(
      select jsonb_build_object('participant_id',m.participant_id,'display_name',m.display_name,'avatar_key',p.avatar_key,'change',m.change,'round_no',m.round_no)
      from mover_rows m
      left join public.quiz_participants p on p.id=m.participant_id
      order by m.change desc,m.round_no desc
      limit 1
    )
  ) into v_out;

  return coalesce(v_out,jsonb_build_object(
    'rounds','[]'::jsonb,
    'summary',jsonb_build_object('participant_count',0,'answer_count',0,'correct_count',0,'wrong_count',0,'accuracy_pct',0,'avg_response_ms',null,'rounds_count',0),
    'most_correct',null,'most_wrong',null,'fastest',null,'slowest',null,'most_balanced',null,
    'best_accuracy',null,'best_streak',null,'fastest_correct',null,'biggest_climb',null
  ));
end
$$;
revoke all on function private.quiz_event_insights(uuid) from public,anon,authenticated;

create or replace function public.admin_set_reveal_stage(p_room_id uuid,p_stage text)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_round_count integer; v_rank jsonb; v_expected text;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_stage not in ('answer','distribution','ranking','final') then raise exception 'Etapa inválida'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id and created_by=v_uid for update;
  if not found then raise exception 'Sala inválida'; end if;
  if v_room.phase not in ('result','finished') then raise exception 'Revelação disponível somente após encerrar o round'; end if;

  v_expected:=case coalesce(v_room.reveal_stage,'hidden')
    when 'hidden' then 'answer'
    when 'answer' then 'distribution'
    when 'distribution' then 'ranking'
    when 'ranking' then 'final'
    else null
  end;
  if p_stage<>v_expected then
    raise exception 'Sequência inválida: a próxima etapa é %',coalesce(v_expected,'nenhuma');
  end if;

  if p_stage='final' then
    select count(*) into v_round_count from public.quiz_rounds where room_id=p_room_id;
    if v_round_count<v_room.planned_rounds then raise exception 'Ainda existem rounds a apresentar'; end if;
    if exists(select 1 from public.quiz_rounds where room_id=p_room_id and status='open') then raise exception 'Encerre a pergunta antes do resultado final'; end if;
    v_rank:=private.generate_ranking(p_room_id);
    update public.quiz_rooms
       set phase='finished',
           game_status='finished',
           status='finished',
           finished_at=clock_timestamp(),
           reveal_stage='final',
           final_ranking_snapshot=v_rank,
           settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{final_show_stage}',to_jsonb('ranking'::text),true)
     where id=p_room_id;
    perform private.audit_event(p_room_id,v_uid,'quiz_final_revealed','room',p_room_id,jsonb_build_object('rounds',v_round_count,'final_show_stage','ranking'));
    perform private.publish_room_event(p_room_id,'quiz_finished',jsonb_build_object('rounds',v_round_count,'final_show_stage','ranking'));
    return;
  end if;

  update public.quiz_rooms set reveal_stage=p_stage where id=p_room_id;
  perform private.publish_room_event(p_room_id,'reveal_changed',jsonb_build_object('stage',p_stage));
end
$function$;
revoke all on function public.admin_set_reveal_stage(uuid,text) from public,anon;
grant execute on function public.admin_set_reveal_stage(uuid,text) to authenticated;

create or replace function public.admin_set_final_show_stage(p_room_id uuid,p_stage text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_stage not in ('ranking','stats','highlights','champion') then raise exception 'Etapa final inválida'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id and created_by=v_uid for update;
  if not found then raise exception 'Sala inválida'; end if;
  if v_room.phase<>'finished' then raise exception 'A apresentação final só está disponível após encerrar o quiz'; end if;

  update public.quiz_rooms
     set settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{final_show_stage}',to_jsonb(p_stage),true)
   where id=p_room_id
   returning * into v_room;

  perform private.audit_event(p_room_id,v_uid,'final_show_stage_changed','room',p_room_id,jsonb_build_object('stage',p_stage));
  perform private.publish_room_event(p_room_id,'final_show_changed',jsonb_build_object('stage',p_stage));
  return jsonb_build_object('stage',p_stage,'state_version',v_room.state_version);
end
$$;
revoke all on function public.admin_set_final_show_stage(uuid,text) from public,anon;
grant execute on function public.admin_set_final_show_stage(uuid,text) to authenticated;
