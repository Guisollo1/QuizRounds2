-- QuizRounds v3.30
-- Compatibilidade de múltipla escolha com 4 ou 5 alternativas: A-D obrigatórias, E opcional.
-- Mantém perguntas antigas com quatro alternativas sem migração de dados.

create or replace function public.admin_create_question_v2(
  p_prompt text,
  p_type text,
  p_options jsonb,
  p_correct_choice text,
  p_correct_number numeric,
  p_points integer,
  p_time_limit integer
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_id uuid;
  v_limit integer;
  v_len integer;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if length(trim(coalesce(p_prompt,'')))<1 then raise exception 'Pergunta obrigatória'; end if;
  if p_type not in ('choice','numeric') then raise exception 'Tipo inválido'; end if;
  v_limit:=greatest(5,least(600,coalesce(p_time_limit,30)));

  if p_type='choice' then
    if jsonb_typeof(p_options)<>'array' then raise exception 'Alternativas inválidas'; end if;
    v_len:=jsonb_array_length(p_options);
    if v_len not in (4,5) then raise exception 'Use quatro ou cinco alternativas'; end if;
    if exists(
      select 1 from jsonb_array_elements(p_options) o
      where upper(trim(coalesce(o->>'key',''))) not in ('A','B','C','D','E')
         or coalesce(trim(o->>'text'),'')=''
         or length(o->>'text')>500
    ) then raise exception 'Alternativas inválidas'; end if;
    if (select count(distinct upper(trim(o->>'key'))) from jsonb_array_elements(p_options)o)<>v_len then raise exception 'Chaves de alternativas repetidas'; end if;
    if (select count(distinct lower(trim(o->>'text'))) from jsonb_array_elements(p_options)o)<>v_len then raise exception 'Alternativas repetidas'; end if;
    if exists(
      select 1 from unnest(array['A','B','C','D']) req
      where not exists(select 1 from jsonb_array_elements(p_options)o where upper(trim(o->>'key'))=req)
    ) then raise exception 'As alternativas A, B, C e D são obrigatórias'; end if;
    if v_len=5 and not exists(select 1 from jsonb_array_elements(p_options)o where upper(trim(o->>'key'))='E') then raise exception 'A quinta alternativa deve usar a chave E'; end if;

    p_options:=(select jsonb_agg(jsonb_build_object('key',upper(trim(o->>'key')),'text',trim(o->>'text')) order by upper(trim(o->>'key'))) from jsonb_array_elements(p_options)o);
    p_correct_choice:=upper(trim(coalesce(p_correct_choice,'')));
    if not exists(select 1 from jsonb_array_elements(p_options)o where o->>'key'=p_correct_choice) then raise exception 'Resposta correta inválida'; end if;
    p_correct_number:=null;
  else
    if p_correct_number is null or abs(p_correct_number)>1000000000000000::numeric then raise exception 'Valor correto inválido'; end if;
    p_options:=null;p_correct_choice:=null;
  end if;

  insert into public.quiz_questions(created_by,prompt,question_type,options,points,time_limit_seconds)
  values(v_uid,trim(p_prompt),p_type,p_options,greatest(1,least(100000,coalesce(p_points,1000))),v_limit)
  returning id into v_id;
  insert into private.quiz_answer_keys(question_id,correct_choice,correct_number) values(v_id,p_correct_choice,p_correct_number);
  perform private.audit_event(null,v_uid,'question_created','question',v_id,jsonb_build_object('question_type',p_type,'points',p_points,'time_limit_seconds',v_limit,'choice_count',coalesce(v_len,0)));
  return v_id;
end
$function$;

create or replace function public.admin_update_question_v3(
  p_question_id uuid,
  p_prompt text,
  p_type text,
  p_options jsonb,
  p_correct_choice text,
  p_correct_number numeric,
  p_points integer,
  p_time_limit integer,
  p_category text,
  p_difficulty text,
  p_score_enabled boolean,
  p_speed_bonus_pct integer,
  p_is_tiebreaker boolean,
  p_presenter_notes text
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_uid uuid := auth.uid();
  v_question public.quiz_questions;
  v_limit integer;
  v_len integer;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_question from public.quiz_questions where id=p_question_id and created_by=v_uid and active for update;
  if not found then raise exception 'Pergunta não encontrada'; end if;

  p_prompt:=trim(coalesce(p_prompt,''));
  if length(p_prompt)<1 or length(p_prompt)>1000 then raise exception 'Pergunta deve ter entre 1 e 1000 caracteres'; end if;
  if p_type not in ('choice','numeric') then raise exception 'Tipo inválido'; end if;
  v_limit:=greatest(5,least(600,coalesce(p_time_limit,30)));

  if p_type='choice' then
    if jsonb_typeof(p_options)<>'array' then raise exception 'Alternativas inválidas'; end if;
    v_len:=jsonb_array_length(p_options);
    if v_len not in (4,5) then raise exception 'Use quatro ou cinco alternativas'; end if;
    if exists(
      select 1 from jsonb_array_elements(p_options) x
      where upper(trim(coalesce(x->>'key',''))) not in ('A','B','C','D','E')
         or length(trim(coalesce(x->>'text','')))<1
         or length(x->>'text')>500
    ) then raise exception 'Alternativas inválidas'; end if;
    if (select count(distinct upper(trim(x->>'key'))) from jsonb_array_elements(p_options)x)<>v_len then raise exception 'Chaves de alternativas repetidas'; end if;
    if (select count(distinct lower(trim(x->>'text'))) from jsonb_array_elements(p_options)x)<>v_len then raise exception 'Alternativas repetidas'; end if;
    if exists(
      select 1 from unnest(array['A','B','C','D']) req
      where not exists(select 1 from jsonb_array_elements(p_options)x where upper(trim(x->>'key'))=req)
    ) then raise exception 'As alternativas A, B, C e D são obrigatórias'; end if;
    if v_len=5 and not exists(select 1 from jsonb_array_elements(p_options)x where upper(trim(x->>'key'))='E') then raise exception 'A quinta alternativa deve usar a chave E'; end if;

    p_options:=(select jsonb_agg(jsonb_build_object('key',upper(trim(x->>'key')),'text',trim(x->>'text')) order by upper(trim(x->>'key'))) from jsonb_array_elements(p_options)x);
    p_correct_choice:=upper(trim(coalesce(p_correct_choice,'')));
    if not exists(select 1 from jsonb_array_elements(p_options)x where x->>'key'=p_correct_choice) then raise exception 'Resposta correta inválida'; end if;
    p_correct_number:=null;
  else
    if p_correct_number is null then raise exception 'Valor correto obrigatório'; end if;
    p_options:=null;p_correct_choice:=null;
  end if;

  if coalesce(p_difficulty,'') not in ('facil','medio','dificil','final') then p_difficulty:='medio'; end if;

  update public.quiz_questions
  set prompt=p_prompt,question_type=p_type,options=p_options,
      points=greatest(1,least(100000,coalesce(p_points,10))),time_limit_seconds=v_limit,
      category=left(coalesce(nullif(trim(p_category),''),'Geral'),60),difficulty=p_difficulty,
      score_enabled=coalesce(p_score_enabled,true),speed_bonus_pct=greatest(0,least(100,coalesce(p_speed_bonus_pct,0))),
      is_tiebreaker=coalesce(p_is_tiebreaker,false),presenter_notes=left(coalesce(p_presenter_notes,''),2000)
  where id=p_question_id;

  insert into private.quiz_answer_keys(question_id,correct_choice,correct_number)
  values(p_question_id,p_correct_choice,p_correct_number)
  on conflict(question_id) do update set correct_choice=excluded.correct_choice,correct_number=excluded.correct_number;
  return p_question_id;
end
$function$;

create or replace function public.admin_import_questions_v2(p_questions jsonb,p_mode text default 'append'::text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_mode text:=lower(trim(coalesce(p_mode,'append')));
  v_item jsonb;v_index integer:=0;v_id uuid;v_prompt text;v_type text;v_options jsonb;v_correct_choice text;v_correct_number numeric;
  v_points integer;v_time integer;v_category text;v_difficulty text;v_score boolean;v_speed integer;v_tie boolean;v_notes text;v_archived boolean;
  v_count integer:=0;v_replaced integer:=0;v_ids jsonb:='[]'::jsonb;v_now timestamptz:=clock_timestamp();v_len integer;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if v_mode not in ('append','replace') then raise exception 'Modo de importação inválido'; end if;
  if p_questions is null or jsonb_typeof(p_questions)<>'array' or jsonb_array_length(p_questions)<1 then raise exception 'Lista de perguntas inválida'; end if;
  if jsonb_array_length(p_questions)>500 then raise exception 'Limite de 500 perguntas por importação'; end if;

  for v_item in select value from jsonb_array_elements(p_questions) loop
    v_index:=v_index+1;v_prompt:=trim(coalesce(v_item->>'prompt',''));v_type:=lower(trim(coalesce(v_item->>'question_type','')));v_options:=v_item->'options';
    v_correct_choice:=upper(trim(coalesce(v_item->>'correct_choice','')));v_correct_number:=case when jsonb_typeof(v_item->'correct_number')='number' then (v_item->>'correct_number')::numeric else null end;
    v_points:=coalesce((v_item->>'points')::integer,10);v_time:=coalesce((v_item->>'time_limit_seconds')::integer,30);v_difficulty:=lower(coalesce(v_item->>'difficulty','medio'));
    if length(v_prompt)<1 or length(v_prompt)>1000 then raise exception 'Pergunta % possui texto inválido',v_index; end if;
    if v_type not in ('choice','numeric') then raise exception 'Pergunta % possui tipo inválido',v_index; end if;
    if v_points<1 or v_points>100000 then raise exception 'Pergunta % possui pontuação inválida',v_index; end if;
    if v_time<5 or v_time>600 then raise exception 'Pergunta % possui tempo inválido',v_index; end if;
    if v_difficulty not in ('facil','medio','dificil','final') then raise exception 'Pergunta % possui dificuldade inválida',v_index; end if;
    if v_type='choice' then
      if jsonb_typeof(v_options)<>'array' then raise exception 'Pergunta % possui alternativas inválidas',v_index; end if;
      v_len:=jsonb_array_length(v_options);if v_len not in (4,5) then raise exception 'Pergunta % precisa de quatro ou cinco alternativas',v_index; end if;
      if exists(select 1 from jsonb_array_elements(v_options)o where upper(trim(coalesce(o->>'key',''))) not in ('A','B','C','D','E') or coalesce(trim(o->>'text'),'')='' or length(o->>'text')>500) then raise exception 'Pergunta % possui alternativa inválida',v_index; end if;
      if (select count(distinct upper(trim(o->>'key'))) from jsonb_array_elements(v_options)o)<>v_len then raise exception 'Pergunta % possui chaves repetidas',v_index; end if;
      if exists(select 1 from unnest(array['A','B','C','D']) req where not exists(select 1 from jsonb_array_elements(v_options)o where upper(trim(o->>'key'))=req)) then raise exception 'Pergunta % precisa das alternativas A, B, C e D',v_index; end if;
      if v_len=5 and not exists(select 1 from jsonb_array_elements(v_options)o where upper(trim(o->>'key'))='E') then raise exception 'Pergunta % deve usar E como quinta alternativa',v_index; end if;
      if not exists(select 1 from jsonb_array_elements(v_options)o where upper(trim(o->>'key'))=v_correct_choice) then raise exception 'Pergunta % possui gabarito inválido',v_index; end if;
      if (select count(distinct lower(trim(o->>'text'))) from jsonb_array_elements(v_options)o)<>v_len then raise exception 'Pergunta % possui alternativas repetidas',v_index; end if;
    else
      if v_correct_number is null or abs(v_correct_number)>1000000000000000::numeric then raise exception 'Pergunta % possui resposta numérica inválida',v_index; end if;
    end if;
  end loop;

  if v_mode='replace' then
    update public.quiz_questions set active=false,archived_at=coalesce(archived_at,v_now) where created_by=v_uid and active=true;
    get diagnostics v_replaced=row_count;
  end if;

  v_index:=0;
  for v_item in select value from jsonb_array_elements(p_questions) loop
    v_index:=v_index+1;v_prompt:=trim(v_item->>'prompt');v_type:=lower(trim(v_item->>'question_type'));v_options:=v_item->'options';
    v_correct_choice:=upper(trim(coalesce(v_item->>'correct_choice','')));v_correct_number:=case when jsonb_typeof(v_item->'correct_number')='number' then (v_item->>'correct_number')::numeric else null end;
    v_points:=coalesce((v_item->>'points')::integer,10);v_time:=coalesce((v_item->>'time_limit_seconds')::integer,30);v_category:=left(coalesce(nullif(trim(v_item->>'category'),''),'Geral'),60);
    v_difficulty:=lower(coalesce(v_item->>'difficulty','medio'));v_score:=coalesce((v_item->>'score_enabled')::boolean,true);v_speed:=greatest(0,least(100,coalesce((v_item->>'speed_bonus_pct')::integer,0)));
    v_tie:=coalesce((v_item->>'is_tiebreaker')::boolean,false);v_notes:=left(coalesce(v_item->>'presenter_notes',''),2000);v_archived:=coalesce((v_item->>'archived')::boolean,false);
    if v_type='numeric' then v_options:=null;v_correct_choice:=null; else
      v_correct_number:=null;
      v_options:=(select jsonb_agg(jsonb_build_object('key',upper(trim(o->>'key')),'text',trim(o->>'text')) order by upper(trim(o->>'key'))) from jsonb_array_elements(v_options)o);
    end if;
    insert into public.quiz_questions(created_by,prompt,question_type,options,points,time_limit_seconds,category,difficulty,score_enabled,speed_bonus_pct,is_tiebreaker,presenter_notes,active,archived_at)
    values(v_uid,v_prompt,v_type,v_options,v_points,v_time,v_category,v_difficulty,v_score,v_speed,v_tie,v_notes,true,case when v_archived then v_now else null end) returning id into v_id;
    insert into private.quiz_answer_keys(question_id,correct_choice,correct_number) values(v_id,v_correct_choice,v_correct_number);
    v_count:=v_count+1;v_ids:=v_ids||jsonb_build_array(v_id);
  end loop;

  perform private.audit_event(null,v_uid,case when v_mode='replace' then 'question_bank_replaced' else 'questions_bulk_imported' end,'question',null,jsonb_build_object('mode',v_mode,'imported',v_count,'replaced',v_replaced));
  return jsonb_build_object('mode',v_mode,'imported',v_count,'replaced',v_replaced,'ids',v_ids);
end
$function$;

create or replace function public.admin_regrade_round(p_room_id uuid,p_correct_choice text default null,p_correct_number numeric default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_uid uuid:=auth.uid();v_room public.quiz_rooms;v_round public.quiz_rounds;v_key private.quiz_round_answer_keys;v_rank jsonb;v_prev jsonb;v_dist jsonb;v_winners jsonb;v_limit_ms numeric;v_choice text;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;if not found then raise exception 'Sala inválida'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id and status='closed' order by round_no desc limit 1 for update;if not found then raise exception 'Nenhum round encerrado'; end if;
  if v_round.question_type_snapshot='choice' then
    v_choice:=upper(trim(coalesce(p_correct_choice,'')));
    if not exists(select 1 from jsonb_array_elements(coalesce(v_round.options_snapshot,'[]'::jsonb))o where upper(trim(o->>'key'))=v_choice) then raise exception 'Alternativa inválida'; end if;
    update private.quiz_round_answer_keys set correct_choice=v_choice,correct_number=null where round_id=v_round.id;
  else
    if p_correct_number is null then raise exception 'Valor obrigatório'; end if;
    update private.quiz_round_answer_keys set correct_choice=null,correct_number=p_correct_number where round_id=v_round.id;
  end if;
  select * into v_key from private.quiz_round_answer_keys where round_id=v_round.id;
  update public.quiz_answers set awarded_points=0 where round_id=v_round.id;
  v_limit_ms:=greatest(1,coalesce(v_round.time_limit_seconds,30)*1000);
  if not v_round.annulled and v_round.score_enabled_snapshot then
    if v_round.question_type_snapshot='choice' then
      update public.quiz_answers a set awarded_points=coalesce(v_round.points_snapshot,0)+case when coalesce((v_room.settings->>'speed_bonus_enabled')::boolean,true) and coalesce(v_round.speed_bonus_pct_snapshot,0)>0 then round(coalesce(v_round.points_snapshot,0)*(v_round.speed_bonus_pct_snapshot/100.0)*greatest(0,1-(a.response_ms/v_limit_ms)))::int else 0 end where a.round_id=v_round.id and a.choice_value=v_key.correct_choice;
      select coalesce(jsonb_agg(jsonb_build_object('key',x.k,'count',x.c) order by x.k),'[]'::jsonb) into v_dist from (select choice_value k,count(*) c from public.quiz_answers where round_id=v_round.id group by choice_value)x;
    else
      with ranked as(select id,row_number() over(order by abs(numeric_value-v_key.correct_number),response_ms,submitted_at,participant_id) rn from public.quiz_answers where round_id=v_round.id)
      update public.quiz_answers a set awarded_points=coalesce(v_round.points_snapshot,0) from ranked r where a.id=r.id and r.rn=1;
      select coalesce(jsonb_agg(jsonb_build_object('participant_id',a.participant_id,'value',a.numeric_value,'difference',abs(a.numeric_value-v_key.correct_number),'response_ms',a.response_ms) order by abs(a.numeric_value-v_key.correct_number),a.response_ms),'[]'::jsonb) into v_dist from public.quiz_answers a where a.round_id=v_round.id;
    end if;
  end if;
  perform private.recalculate_aux_scores(p_room_id);
  if coalesce((v_room.settings->>'streak_enabled')::boolean,true) and coalesce((v_room.settings->>'streak_bonus')::int,0)>0 then
    update public.quiz_answers a set awarded_points=a.awarded_points+coalesce((v_room.settings->>'streak_bonus')::int,0)*greatest(p.current_streak-1,0) from public.quiz_participants p where a.round_id=v_round.id and a.participant_id=p.id and a.awarded_points>0;
  end if;
  perform private.recalculate_room_totals(p_room_id);perform private.recalculate_aux_scores(p_room_id);v_rank:=private.generate_ranking(p_room_id);
  select coalesce(ranking_snapshot,'[]'::jsonb) into v_prev from public.quiz_rounds where room_id=p_room_id and round_no<v_round.round_no order by round_no desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('participant_id',x.participant_id,'display_name',x.display_name,'response_ms',x.response_ms,'points',x.awarded_points) order by x.awarded_points desc,x.response_ms),'[]'::jsonb) into v_winners from (select a.participant_id,p.display_name,a.response_ms,a.awarded_points from public.quiz_answers a join public.quiz_participants p on p.id=a.participant_id where a.round_id=v_round.id and a.awarded_points>0 order by a.awarded_points desc,a.response_ms limit 20)x;
  perform set_config('quiz.allow_round_reset','on',true);
  update public.quiz_rounds set ranking_snapshot=v_rank,previous_ranking_snapshot=coalesce(v_prev,'[]'::jsonb),ranking_movers_snapshot=private.ranking_movers(coalesce(v_prev,'[]'::jsonb),v_rank),winner_snapshot=v_winners,distribution_snapshot=coalesce(v_dist,distribution_snapshot),result_text=case when question_type_snapshot='choice' then 'Resposta correta: '||v_key.correct_choice||coalesce((select ' — '||(o->>'text') from jsonb_array_elements(coalesce(options_snapshot,'[]'::jsonb))o where o->>'key'=v_key.correct_choice limit 1),'') else 'Valor correto: '||v_key.correct_number::text end where id=v_round.id;
  update public.quiz_rooms set final_ranking_snapshot=case when phase='finished' then v_rank else final_ranking_snapshot end where id=p_room_id;
  perform set_config('quiz.allow_round_reset','off',true);
  perform private.audit_event(p_room_id,v_uid,'round_regraded','round',v_round.id,jsonb_build_object('correct_choice',v_choice,'correct_number',p_correct_number));perform private.notify_room(p_room_id);
  return jsonb_build_object('regraded',true,'round_no',v_round.round_no);
exception when others then perform set_config('quiz.allow_round_reset','off',true);raise;end
$function$;
