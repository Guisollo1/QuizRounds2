-- Quiz Rounds v1.6: importação em lote de perguntas pelo Painel ADM.
-- Mantém respostas corretas no schema private e só permite execução por administradores autenticados.

create or replace function public.admin_import_questions(p_questions jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_item jsonb;
  v_id uuid;
  v_prompt text;
  v_type text;
  v_options jsonb;
  v_correct_choice text;
  v_correct_number numeric;
  v_points integer;
  v_time integer;
  v_count integer:=0;
  v_ids jsonb:='[]'::jsonb;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_questions is null or jsonb_typeof(p_questions)<>'array' then raise exception 'Lista de perguntas inválida'; end if;
  if jsonb_array_length(p_questions)<1 then raise exception 'Nenhuma pergunta para importar'; end if;
  if jsonb_array_length(p_questions)>500 then raise exception 'Limite de 500 perguntas por importação'; end if;

  for v_item in select value from jsonb_array_elements(p_questions)
  loop
    v_prompt:=trim(coalesce(v_item->>'prompt',''));
    v_type:=lower(trim(coalesce(v_item->>'question_type','')));
    v_options:=v_item->'options';
    v_correct_choice:=upper(trim(coalesce(v_item->>'correct_choice','')));
    v_correct_number:=case when jsonb_typeof(v_item->'correct_number')='number' then (v_item->>'correct_number')::numeric else null end;
    v_points:=coalesce((v_item->>'points')::integer,10);
    v_time:=coalesce((v_item->>'time_limit_seconds')::integer,30);

    if length(v_prompt)<1 or length(v_prompt)>1000 then raise exception 'Pergunta % possui texto inválido',v_count+1; end if;
    if v_type not in ('choice','numeric') then raise exception 'Pergunta % possui tipo inválido',v_count+1; end if;
    if v_points<1 or v_points>100000 then raise exception 'Pergunta % possui pontuação inválida',v_count+1; end if;
    if v_time<5 or v_time>600 then raise exception 'Pergunta % possui tempo inválido',v_count+1; end if;

    if v_type='choice' then
      if jsonb_typeof(v_options)<>'array' or jsonb_array_length(v_options)<>4 then raise exception 'Pergunta % precisa de quatro alternativas',v_count+1; end if;
      if v_correct_choice not in ('A','B','C','D') then raise exception 'Pergunta % possui resposta correta inválida',v_count+1; end if;
      if exists(select 1 from jsonb_array_elements(v_options) o where upper(trim(coalesce(o->>'key',''))) not in ('A','B','C','D')) then raise exception 'Pergunta % possui chave de alternativa inválida',v_count+1; end if;
      if (select count(distinct upper(trim(o->>'key'))) from jsonb_array_elements(v_options) o)<>4 then raise exception 'Pergunta % precisa conter exatamente as chaves A, B, C e D',v_count+1; end if;
      if exists(select 1 from jsonb_array_elements(v_options) o where coalesce(trim(o->>'text'),'')='' or length(o->>'text')>500) then raise exception 'Pergunta % possui alternativa inválida',v_count+1; end if;
      if (select count(distinct lower(trim(o->>'text'))) from jsonb_array_elements(v_options) o)<>4 then raise exception 'Pergunta % possui alternativas repetidas',v_count+1; end if;
      v_correct_number:=null;
    else
      if v_correct_number is null or abs(v_correct_number)>1000000000000000::numeric then raise exception 'Pergunta % possui valor numérico correto inválido',v_count+1; end if;
      v_options:=null;v_correct_choice:=null;
    end if;

    insert into public.quiz_questions(created_by,prompt,question_type,options,points,time_limit_seconds)
    values(v_uid,v_prompt,v_type,v_options,v_points,v_time)
    returning id into v_id;

    insert into private.quiz_answer_keys(question_id,correct_choice,correct_number)
    values(v_id,v_correct_choice,v_correct_number);

    v_count:=v_count+1;
    v_ids:=v_ids||jsonb_build_array(v_id);
  end loop;

  perform private.audit_event(null,v_uid,'questions_bulk_imported','question',null,jsonb_build_object('count',v_count));
  return jsonb_build_object('imported',v_count,'ids',v_ids);
end $$;

revoke all on function public.admin_import_questions(jsonb) from public;
grant execute on function public.admin_import_questions(jsonb) to authenticated;

-- Canal privado de progresso somente para Admin/Display.
-- Jogadores continuam no tópico quiz:<room_id> e não recebem um broadcast a cada resposta.
drop policy if exists quiz_realtime_read on realtime.messages;
create policy quiz_realtime_read
on realtime.messages for select to authenticated
using (
  realtime.messages.extension in ('broadcast','presence')
  and exists (
    select 1
    from public.quiz_realtime_memberships m
    where m.user_id=(select auth.uid())
      and (
        (
          ('quiz:'||m.room_id::text)=(select realtime.topic())
          and (realtime.messages.extension='broadcast' or m.role in ('participant','admin','display'))
        )
        or
        (
          ('quiz-admin:'||m.room_id::text)=(select realtime.topic())
          and realtime.messages.extension='broadcast'
          and m.role in ('admin','display')
        )
      )
  )
);

create or replace function private.broadcast_quiz_answer_progress()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_room_id uuid;
begin
  select r.room_id into v_room_id from public.quiz_rounds r where r.id=new.round_id;
  if v_room_id is null then return new; end if;
  begin
    perform realtime.send(
      jsonb_build_object('room_id',v_room_id,'round_id',new.round_id,'at',clock_timestamp()),
      'response_progress',
      'quiz-admin:'||v_room_id::text,
      true
    );
  exception when others then
    null;
  end;
  return new;
end $$;
revoke all on function private.broadcast_quiz_answer_progress() from public;

drop trigger if exists quiz_answers_broadcast_progress on public.quiz_answers;
create trigger quiz_answers_broadcast_progress
after insert on public.quiz_answers
for each row execute function private.broadcast_quiz_answer_progress();
