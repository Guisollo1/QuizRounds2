-- QuizRounds v3.11 — edição completa de perguntas existentes.
-- A alteração afeta o banco para futuras seleções; filas/rounds já preparados usam snapshots e permanecem intactos.

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
as $$
declare
  v_uid uuid := auth.uid();
  v_question public.quiz_questions;
  v_limit integer;
begin
  if not private.is_admin(v_uid) then
    raise exception 'Acesso negado';
  end if;

  select * into v_question
  from public.quiz_questions
  where id = p_question_id
    and created_by = v_uid
    and active
  for update;

  if not found then
    raise exception 'Pergunta não encontrada';
  end if;

  p_prompt := trim(coalesce(p_prompt,''));
  if length(p_prompt) < 1 or length(p_prompt) > 1000 then
    raise exception 'Pergunta deve ter entre 1 e 1000 caracteres';
  end if;

  if p_type not in ('choice','numeric') then
    raise exception 'Tipo inválido';
  end if;

  v_limit := greatest(5,least(600,coalesce(p_time_limit,30)));

  if p_type='choice' then
    if jsonb_typeof(p_options) <> 'array'
       or jsonb_array_length(p_options) <> 4
       or upper(coalesce(p_correct_choice,'')) not in ('A','B','C','D') then
      raise exception 'Alternativas inválidas';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(p_options) x
      where length(trim(coalesce(x->>'text',''))) < 1
    ) then
      raise exception 'Preencha as quatro alternativas';
    end if;
    p_correct_choice := upper(p_correct_choice);
    p_correct_number := null;
  else
    if p_correct_number is null then
      raise exception 'Valor correto obrigatório';
    end if;
    p_options := null;
    p_correct_choice := null;
  end if;

  if coalesce(p_difficulty,'') not in ('facil','medio','dificil','final') then
    p_difficulty := 'medio';
  end if;

  update public.quiz_questions
  set prompt = p_prompt,
      question_type = p_type,
      options = p_options,
      points = greatest(1,least(100000,coalesce(p_points,10))),
      time_limit_seconds = v_limit,
      category = left(coalesce(nullif(trim(p_category),''),'Geral'),60),
      difficulty = p_difficulty,
      score_enabled = coalesce(p_score_enabled,true),
      speed_bonus_pct = greatest(0,least(100,coalesce(p_speed_bonus_pct,0))),
      is_tiebreaker = coalesce(p_is_tiebreaker,false),
      presenter_notes = left(coalesce(p_presenter_notes,''),2000)
  where id = p_question_id;

  insert into private.quiz_answer_keys(question_id,correct_choice,correct_number)
  values(p_question_id,p_correct_choice,p_correct_number)
  on conflict(question_id) do update
    set correct_choice=excluded.correct_choice,
        correct_number=excluded.correct_number;

  return p_question_id;
end
$$;

revoke execute on function public.admin_update_question_v3(uuid,text,text,jsonb,text,numeric,integer,integer,text,text,boolean,integer,boolean,text) from anon;
revoke execute on function public.admin_update_question_v3(uuid,text,text,jsonb,text,numeric,integer,integer,text,text,boolean,integer,boolean,text) from public;
grant execute on function public.admin_update_question_v3(uuid,text,text,jsonb,text,numeric,integer,integer,text,text,boolean,integer,boolean,text) to authenticated;
