-- Quiz Rounds v3.1 — importação transacional do banco de perguntas.
-- Modos: append (adicionar) e replace (substituir banco operacional).
-- O modo replace NÃO apaga fisicamente perguntas históricas: marca as anteriores como inativas,
-- preservando FKs, snapshots, auditoria e partidas já executadas.

create or replace function public.admin_import_questions_v2(
  p_questions jsonb,
  p_mode text default 'append'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_mode text:=lower(trim(coalesce(p_mode,'append')));
  v_item jsonb;
  v_index integer:=0;
  v_id uuid;
  v_prompt text;
  v_type text;
  v_options jsonb;
  v_correct_choice text;
  v_correct_number numeric;
  v_points integer;
  v_time integer;
  v_category text;
  v_difficulty text;
  v_score boolean;
  v_speed integer;
  v_tie boolean;
  v_notes text;
  v_archived boolean;
  v_count integer:=0;
  v_replaced integer:=0;
  v_ids jsonb:='[]'::jsonb;
  v_now timestamptz:=clock_timestamp();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if v_mode not in ('append','replace') then raise exception 'Modo de importação inválido'; end if;
  if p_questions is null or jsonb_typeof(p_questions)<>'array' or jsonb_array_length(p_questions)<1 then
    raise exception 'Lista de perguntas inválida';
  end if;
  if jsonb_array_length(p_questions)>500 then raise exception 'Limite de 500 perguntas por importação'; end if;

  -- 1ª passagem: valida TODO o lote antes de tocar no banco atual.
  for v_item in select value from jsonb_array_elements(p_questions) loop
    v_index:=v_index+1;
    v_prompt:=trim(coalesce(v_item->>'prompt',''));
    v_type:=lower(trim(coalesce(v_item->>'question_type','')));
    v_options:=v_item->'options';
    v_correct_choice:=upper(trim(coalesce(v_item->>'correct_choice','')));
    v_correct_number:=case when jsonb_typeof(v_item->'correct_number')='number' then (v_item->>'correct_number')::numeric else null end;
    v_points:=coalesce((v_item->>'points')::integer,10);
    v_time:=coalesce((v_item->>'time_limit_seconds')::integer,30);
    v_difficulty:=lower(coalesce(v_item->>'difficulty','medio'));

    if length(v_prompt)<1 or length(v_prompt)>1000 then raise exception 'Pergunta % possui texto inválido',v_index; end if;
    if v_type not in ('choice','numeric') then raise exception 'Pergunta % possui tipo inválido',v_index; end if;
    if v_points<1 or v_points>100000 then raise exception 'Pergunta % possui pontuação inválida',v_index; end if;
    if v_time<5 or v_time>600 then raise exception 'Pergunta % possui tempo inválido',v_index; end if;
    if v_difficulty not in ('facil','medio','dificil','final') then raise exception 'Pergunta % possui dificuldade inválida',v_index; end if;

    if v_type='choice' then
      if jsonb_typeof(v_options)<>'array' or jsonb_array_length(v_options)<>4 then raise exception 'Pergunta % precisa de quatro alternativas',v_index; end if;
      if v_correct_choice not in ('A','B','C','D') then raise exception 'Pergunta % possui gabarito inválido',v_index; end if;
      if (select count(distinct upper(trim(o->>'key'))) from jsonb_array_elements(v_options)o)<>4 then raise exception 'Pergunta % precisa das chaves A, B, C e D',v_index; end if;
      if exists(select 1 from jsonb_array_elements(v_options)o where upper(trim(coalesce(o->>'key',''))) not in ('A','B','C','D') or coalesce(trim(o->>'text'),'')='' or length(o->>'text')>500) then raise exception 'Pergunta % possui alternativa inválida',v_index; end if;
      if (select count(distinct lower(trim(o->>'text'))) from jsonb_array_elements(v_options)o)<>4 then raise exception 'Pergunta % possui alternativas repetidas',v_index; end if;
    else
      if v_correct_number is null or abs(v_correct_number)>1000000000000000::numeric then raise exception 'Pergunta % possui resposta numérica inválida',v_index; end if;
    end if;
  end loop;

  -- Só depois da validação total o banco operacional anterior é substituído.
  if v_mode='replace' then
    update public.quiz_questions
       set active=false,
           archived_at=coalesce(archived_at,v_now)
     where created_by=v_uid
       and active=true;
    get diagnostics v_replaced=row_count;
  end if;

  -- 2ª passagem: grava o novo lote. Qualquer erro ainda faz rollback da transação inteira.
  v_index:=0;
  for v_item in select value from jsonb_array_elements(p_questions) loop
    v_index:=v_index+1;
    v_prompt:=trim(v_item->>'prompt');
    v_type:=lower(trim(v_item->>'question_type'));
    v_options:=v_item->'options';
    v_correct_choice:=upper(trim(coalesce(v_item->>'correct_choice','')));
    v_correct_number:=case when jsonb_typeof(v_item->'correct_number')='number' then (v_item->>'correct_number')::numeric else null end;
    v_points:=coalesce((v_item->>'points')::integer,10);
    v_time:=coalesce((v_item->>'time_limit_seconds')::integer,30);
    v_category:=left(coalesce(nullif(trim(v_item->>'category'),''),'Geral'),60);
    v_difficulty:=lower(coalesce(v_item->>'difficulty','medio'));
    v_score:=coalesce((v_item->>'score_enabled')::boolean,true);
    v_speed:=greatest(0,least(100,coalesce((v_item->>'speed_bonus_pct')::integer,0)));
    v_tie:=coalesce((v_item->>'is_tiebreaker')::boolean,false);
    v_notes:=left(coalesce(v_item->>'presenter_notes',''),2000);
    v_archived:=coalesce((v_item->>'archived')::boolean,false);

    if v_type='numeric' then v_options:=null;v_correct_choice:=null; else v_correct_number:=null; end if;

    insert into public.quiz_questions(
      created_by,prompt,question_type,options,points,time_limit_seconds,
      category,difficulty,score_enabled,speed_bonus_pct,is_tiebreaker,presenter_notes,active,archived_at
    ) values(
      v_uid,v_prompt,v_type,v_options,v_points,v_time,
      v_category,v_difficulty,v_score,v_speed,v_tie,v_notes,true,case when v_archived then v_now else null end
    ) returning id into v_id;

    insert into private.quiz_answer_keys(question_id,correct_choice,correct_number)
    values(v_id,v_correct_choice,v_correct_number);

    v_count:=v_count+1;
    v_ids:=v_ids||jsonb_build_array(v_id);
  end loop;

  perform private.audit_event(
    null,v_uid,
    case when v_mode='replace' then 'question_bank_replaced' else 'questions_bulk_imported' end,
    'question',null,
    jsonb_build_object('mode',v_mode,'imported',v_count,'replaced',v_replaced)
  );

  return jsonb_build_object('mode',v_mode,'imported',v_count,'replaced',v_replaced,'ids',v_ids);
end $$;

revoke all on function public.admin_import_questions_v2(jsonb,text) from public;
grant execute on function public.admin_import_questions_v2(jsonb,text) to authenticated;
