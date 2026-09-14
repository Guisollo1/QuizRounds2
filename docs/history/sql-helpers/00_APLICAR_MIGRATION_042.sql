-- QuizRounds2 v3.68-r47 — Game Modes Pack / schema 042
-- Requer schema 041 (r46 GameShow Pro).
-- Adiciona mecânicas avançadas de pergunta, respostas JSON seguras, votação pública,
-- fila inteligente por categoria/dificuldade e modo prova sem alterar o motor clássico.

-- -----------------------------------------------------------------------------
-- 1) Catálogo de mecânicas e snapshots
-- -----------------------------------------------------------------------------
alter table public.quiz_questions
  add column if not exists game_type text not null default 'standard',
  add column if not exists game_spec jsonb not null default '{}'::jsonb;

alter table public.quiz_room_queue
  add column if not exists game_type_snapshot text not null default 'standard',
  add column if not exists game_spec_snapshot jsonb not null default '{}'::jsonb;

alter table public.quiz_rounds
  add column if not exists game_type_snapshot text not null default 'standard',
  add column if not exists game_spec_snapshot jsonb not null default '{}'::jsonb;

do $$ begin
  alter table public.quiz_questions add constraint quiz_questions_game_type_check check(game_type in (
    'standard','nearest','precision','ordering','matching','classification','true_false_series',
    'hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','team_mission',
    'bingo','wheel','surprise','crowd_prediction','live_poll','audience_choice','category_choice'
  ));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.quiz_room_queue add constraint quiz_room_queue_game_type_check check(game_type_snapshot in (
    'standard','nearest','precision','ordering','matching','classification','true_false_series',
    'hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','team_mission',
    'bingo','wheel','surprise','crowd_prediction','live_poll','audience_choice','category_choice'
  ));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.quiz_rounds add constraint quiz_rounds_game_type_check check(game_type_snapshot in (
    'standard','nearest','precision','ordering','matching','classification','true_false_series',
    'hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','team_mission',
    'bingo','wheel','surprise','crowd_prediction','live_poll','audience_choice','category_choice'
  ));
exception when duplicate_object then null; end $$;

create or replace function private.capture_game_snapshot_on_queue()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_type text; v_spec jsonb;
begin
  select q.game_type,q.game_spec into v_type,v_spec from public.quiz_questions q where q.id=new.question_id;
  new.game_type_snapshot:=coalesce(v_type,'standard');
  new.game_spec_snapshot:=coalesce(v_spec,'{}'::jsonb);
  return new;
end $$;
revoke all on function private.capture_game_snapshot_on_queue() from public,anon,authenticated;

drop trigger if exists quiz_queue_game_snapshot_trg on public.quiz_room_queue;
create trigger quiz_queue_game_snapshot_trg before insert or update of question_id on public.quiz_room_queue
for each row execute function private.capture_game_snapshot_on_queue();

create or replace function private.capture_game_snapshot_on_round()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_type text; v_spec jsonb;
begin
  select q.game_type,q.game_spec into v_type,v_spec from public.quiz_questions q where q.id=new.question_id;
  new.game_type_snapshot:=coalesce(v_type,'standard');
  new.game_spec_snapshot:=coalesce(v_spec,'{}'::jsonb);
  return new;
end $$;
revoke all on function private.capture_game_snapshot_on_round() from public,anon,authenticated;

drop trigger if exists quiz_round_game_snapshot_trg on public.quiz_rounds;
create trigger quiz_round_game_snapshot_trg before insert or update of question_id on public.quiz_rounds
for each row execute function private.capture_game_snapshot_on_round();

-- Atualiza snapshots já enfileirados ainda não usados.
update public.quiz_room_queue rq set
  game_type_snapshot=q.game_type,
  game_spec_snapshot=q.game_spec
from public.quiz_questions q
where q.id=rq.question_id and rq.status='queued';



-- A fila e o round preservam o snapshot da mecânica, mesmo se a pergunta for editada depois.
create or replace function public.admin_list_room_queue(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb; begin
  perform private.require_admin_capability('view');
  if not exists(select 1 from public.quiz_rooms r where r.id=p_room_id and r.created_by=auth.uid()) then raise exception 'Sala inválida'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',rq.id,'question_id',rq.question_id,'position',rq.position,'status',rq.status,'round_id',rq.round_id,'prompt',rq.prompt_snapshot,
    'question_type',rq.question_type_snapshot,'options',rq.options_snapshot,'points',rq.points_snapshot,'time_limit_seconds',rq.time_limit_snapshot,
    'category',rq.category_snapshot,'difficulty',rq.difficulty_snapshot,'score_enabled',rq.score_enabled_snapshot,'speed_bonus_pct',rq.speed_bonus_pct_snapshot,
    'is_tiebreaker',rq.is_tiebreaker_snapshot,'presenter_notes',rq.presenter_notes_snapshot,
    'media_type',rq.media_type_snapshot,'media_url',rq.media_url_snapshot,'media_caption',rq.media_caption_snapshot,
    'special_type',rq.special_type_snapshot,'tags',rq.tags_snapshot,'source_label',rq.source_label_snapshot,
    'game_type',rq.game_type_snapshot,'game_spec',rq.game_spec_snapshot
  ) order by rq.position,rq.added_at),'[]'::jsonb) into v_result from public.quiz_room_queue rq where rq.room_id=p_room_id;
  return v_result;
end $$;

create or replace function public.admin_open_prepared_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb; v_round uuid;
begin
  perform private.require_admin_capability('present');
  perform private.require_live_control(p_room_id);
  v:=public.admin_open_prepared_round_r28_impl(p_room_id);
  begin v_round:=(v->'round'->>'id')::uuid; exception when others then v_round:=null; end;
  if v_round is not null then
    perform private.capture_round_eligibility(v_round);
    update public.quiz_rounds r set
      media_type_snapshot=q.media_type_snapshot,media_url_snapshot=q.media_url_snapshot,media_caption_snapshot=q.media_caption_snapshot,
      special_type_snapshot=q.special_type_snapshot,tags_snapshot=q.tags_snapshot,source_label_snapshot=q.source_label_snapshot,
      game_type_snapshot=q.game_type_snapshot,game_spec_snapshot=q.game_spec_snapshot
    from public.quiz_room_queue q where q.round_id=r.id and r.id=v_round;
  end if;
  return v;
end $$;

create or replace function public.admin_duplicate_question(p_question_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_new uuid;
begin
  perform private.require_admin_capability('edit');
  v_new:=public.admin_duplicate_question_r28_impl(p_question_id);
  update public.quiz_questions dst set
    media_type=src.media_type,media_url=src.media_url,media_caption=src.media_caption,special_type=src.special_type,
    tags=src.tags,source_label=src.source_label,starred=false,game_type=src.game_type,game_spec=src.game_spec
  from public.quiz_questions src where dst.id=v_new and src.id=p_question_id;
  return v_new;
end $$;

revoke all on function public.admin_list_room_queue(uuid),public.admin_open_prepared_round(uuid),public.admin_duplicate_question(uuid) from public,anon;
grant execute on function public.admin_list_room_queue(uuid),public.admin_open_prepared_round(uuid),public.admin_duplicate_question(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 2) Respostas avançadas JSON + espelho no motor clássico
-- -----------------------------------------------------------------------------
create table if not exists public.quiz_game_answers(
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.quiz_rounds(id) on delete cascade,
  participant_id uuid not null references public.quiz_participants(id) on delete cascade,
  response jsonb not null default '{}'::jsonb,
  response_ms integer not null default 0,
  awarded_points integer not null default 0,
  submitted_at timestamptz not null default now(),
  unique(round_id,participant_id)
);
create index if not exists quiz_game_answers_round_idx on public.quiz_game_answers(round_id,submitted_at);
alter table public.quiz_game_answers enable row level security;
revoke all on public.quiz_game_answers from anon,authenticated;

create table if not exists public.quiz_room_votes(
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.quiz_rooms(id) on delete cascade,
  participant_id uuid not null references public.quiz_participants(id) on delete cascade,
  vote_type text not null default 'audience_choice',
  cycle integer not null default 1,
  value text not null,
  submitted_at timestamptz not null default now(),
  unique(room_id,participant_id,vote_type,cycle)
);
create index if not exists quiz_room_votes_room_idx on public.quiz_room_votes(room_id,vote_type,cycle,submitted_at);
alter table public.quiz_room_votes enable row level security;
revoke all on public.quiz_room_votes from anon,authenticated;

create or replace function public.admin_update_question_game(p_question_id uuid,p_game_type text,p_game_spec jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_type text:=lower(trim(coalesce(p_game_type,'standard'))); v_spec jsonb:=coalesce(p_game_spec,'{}'::jsonb); v_q public.quiz_questions;
begin
  perform private.require_admin_capability('edit');
  if v_type not in (
    'standard','nearest','precision','ordering','matching','classification','true_false_series',
    'hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','team_mission',
    'bingo','wheel','surprise','crowd_prediction','live_poll','audience_choice','category_choice'
  ) then raise exception 'Tipo de game inválido'; end if;
  if jsonb_typeof(v_spec)<>'object' then raise exception 'Configuração do game deve ser um objeto JSON'; end if;
  if length(v_spec::text)>65000 then raise exception 'Configuração do game excede 65 KB'; end if;
  update public.quiz_questions set game_type=v_type,game_spec=v_spec
  where id=p_question_id and created_by=v_uid and active returning * into v_q;
  if not found then raise exception 'Pergunta não encontrada'; end if;
  update public.quiz_room_queue set game_type_snapshot=v_type,game_spec_snapshot=v_spec
  where question_id=p_question_id and status='queued';
  return jsonb_build_object('id',v_q.id,'game_type',v_q.game_type,'game_spec',v_q.game_spec);
end $$;
revoke all on function public.admin_update_question_game(uuid,text,jsonb) from public,anon;
grant execute on function public.admin_update_question_game(uuid,text,jsonb) to authenticated;

-- Banco profissional agora inclui a mecânica r47.
create or replace function public.admin_list_question_bank(p_scope text default 'active')
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_result jsonb;v_scope text:=lower(coalesce(p_scope,'active')); begin
  perform private.require_admin_capability('view');
  if v_scope not in ('active','archived','all') then v_scope:='active'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'prompt',q.prompt,'question_type',q.question_type,'options',q.options,'points',q.points,'time_limit_seconds',q.time_limit_seconds,
    'correct_choice',k.correct_choice,'correct_number',k.correct_number,'archived',q.archived_at is not null,'archived_at',q.archived_at,'created_at',q.created_at,
    'category',q.category,'difficulty',q.difficulty,'score_enabled',q.score_enabled,'speed_bonus_pct',q.speed_bonus_pct,'is_tiebreaker',q.is_tiebreaker,
    'presenter_notes',q.presenter_notes,'use_count',q.use_count,'last_used_at',q.last_used_at,
    'media_type',q.media_type,'media_url',q.media_url,'media_caption',q.media_caption,'special_type',q.special_type,'tags',q.tags,'source_label',q.source_label,'starred',q.starred,
    'game_type',q.game_type,'game_spec',q.game_spec
  ) order by q.starred desc,q.created_at desc),'[]'::jsonb) into v_result
  from public.quiz_questions q join private.quiz_answer_keys k on k.question_id=q.id
  where q.active and q.created_by=v_uid and (v_scope='all' or (v_scope='active' and q.archived_at is null) or (v_scope='archived' and q.archived_at is not null));
  return v_result;
end $$;
revoke all on function public.admin_list_question_bank(text) from public,anon;
grant execute on function public.admin_list_question_bank(text) to authenticated;

create or replace function public.submit_quiz_game_answer(p_round_id uuid,p_response jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_round public.quiz_rounds; v_part public.quiz_participants; v_ms integer; v_type text; v_numeric numeric; v_choice text; v_expected integer; v_size integer;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  if jsonb_typeof(coalesce(p_response,'{}'::jsonb))<>'object' then raise exception 'Resposta inválida'; end if;
  if length(coalesce(p_response,'{}'::jsonb)::text)>12000 then raise exception 'Resposta excede o limite'; end if;
  select * into v_round from public.quiz_rounds where id=p_round_id for update;
  if not found then raise exception 'Round não encontrado'; end if;
  select * into v_room from public.quiz_rooms where id=v_round.room_id;
  if not found or v_room.phase<>'question_open' or v_round.status<>'open' then raise exception 'Round não está aceitando respostas'; end if;
  if v_round.closes_at is not null and clock_timestamp()>v_round.closes_at then raise exception 'Tempo esgotado'; end if;
  v_type:=coalesce(v_round.game_type_snapshot,'standard');
  if v_type='standard' then raise exception 'Use a resposta normal para este round'; end if;
  select * into v_part from public.quiz_participants where room_id=v_round.room_id and user_id=v_uid and not kicked;
  if not found then raise exception 'Participante não pertence à sala'; end if;
  if exists(select 1 from public.quiz_round_eligibility e where e.round_id=v_round.id)
     and not exists(select 1 from public.quiz_round_eligibility e where e.round_id=v_round.id and e.participant_id=v_part.id) then
    raise exception 'Você entrou após o início deste round e não pode respondê-lo';
  end if;

  -- Valida a forma da resposta antes de persistir/espelhar no motor clássico.
  if v_type in ('nearest','precision') then
    begin v_numeric:=(p_response->>'value')::numeric; exception when others then v_numeric:=null; end;
    if v_numeric is null then raise exception 'Informe um valor numérico válido'; end if;
  elsif v_type='ordering' then
    if coalesce(jsonb_typeof(p_response->'order'),'')<>'array' then raise exception 'Ordem inválida'; end if;
    v_expected:=coalesce(jsonb_array_length(v_round.game_spec_snapshot->'items'),0);
    if v_expected>0 and jsonb_array_length(p_response->'order')<>v_expected then raise exception 'Ordene todos os itens'; end if;
  elsif v_type='matching' then
    if coalesce(jsonb_typeof(p_response->'matches'),'')<>'object' then raise exception 'Relacionamentos inválidos'; end if;
  elsif v_type='classification' then
    if coalesce(jsonb_typeof(p_response->'classes'),'')<>'object' then raise exception 'Classificação inválida'; end if;
  elsif v_type='true_false_series' then
    if coalesce(jsonb_typeof(p_response->'values'),'')<>'array' then raise exception 'Série V/F inválida'; end if;
    v_expected:=coalesce(jsonb_array_length(v_round.game_spec_snapshot->'statements'),0);
    if v_expected>0 and jsonb_array_length(p_response->'values')<>v_expected then raise exception 'Responda todas as afirmações'; end if;
  elsif v_type='team_mission' then
    if coalesce(jsonb_typeof(p_response->'choices'),'')<>'array' then raise exception 'Seleção da missão inválida'; end if;
  elsif v_type='bingo' then
    if coalesce(jsonb_typeof(p_response->'cells'),'')<>'array' then raise exception 'Cartela inválida'; end if;
    begin v_size:=greatest(1,least(5,coalesce((v_round.game_spec_snapshot->>'size')::integer,3))); exception when others then v_size:=3; end;
    if jsonb_array_length(p_response->'cells')>v_size then raise exception 'Marque no máximo % casas para formar uma linha',v_size; end if;
  else
    v_choice:=left(trim(coalesce(p_response->>'choice','')),120);
    if v_choice='' then raise exception 'Escolha uma alternativa'; end if;
    if jsonb_typeof(coalesce(v_round.options_snapshot,'[]'::jsonb))='array' and jsonb_array_length(coalesce(v_round.options_snapshot,'[]'::jsonb))>0
       and not exists(select 1 from jsonb_array_elements(v_round.options_snapshot)o where upper(coalesce(o->>'key',''))=upper(v_choice)) then
      raise exception 'Alternativa inválida';
    end if;
  end if;

  v_ms:=greatest(0,least(3600000,round(extract(epoch from(clock_timestamp()-v_round.opened_at))*1000)::integer));
  insert into public.quiz_game_answers(round_id,participant_id,response,response_ms,submitted_at)
  values(v_round.id,v_part.id,p_response,v_ms,clock_timestamp())
  on conflict(round_id,participant_id) do nothing;
  if not found then return jsonb_build_object('accepted',false,'message','Resposta já registrada'); end if;

  if v_type in ('nearest','precision') then
    insert into public.quiz_answers(round_id,participant_id,numeric_value,response_ms,submitted_at)
    values(v_round.id,v_part.id,v_numeric,v_ms,clock_timestamp()) on conflict(round_id,participant_id) do nothing;
  else
    v_choice:=left(coalesce(nullif(p_response->>'choice',''),'__GAME__'),120);
    insert into public.quiz_answers(round_id,participant_id,choice_value,response_ms,submitted_at)
    values(v_round.id,v_part.id,v_choice,v_ms,clock_timestamp()) on conflict(round_id,participant_id) do nothing;
  end if;
  perform private.notify_room(v_round.room_id);
  return jsonb_build_object('accepted',true,'response_ms',v_ms,'game_type',v_type);
end $$;
revoke all on function public.submit_quiz_game_answer(uuid,jsonb) from public,anon;
grant execute on function public.submit_quiz_game_answer(uuid,jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- 3) Cálculo de pontuação das mecânicas avançadas
-- -----------------------------------------------------------------------------
create or replace function private.game_response_fraction(p_type text,p_spec jsonb,p_response jsonb,p_round public.quiz_rounds)
returns numeric language plpgsql stable security definer set search_path='' as $$
declare v_correct jsonb; v_values jsonb; v_key text; v_total integer:=0; v_hits integer:=0; v_choice text; v_correct_choice text; v_value numeric; v_target numeric; v_diff numeric; v_gold numeric; v_silver numeric; v_bronze numeric; v_arr jsonb; v_item jsonb; v_selected jsonb; v_line jsonb; v_ok boolean;
begin
  if p_type='precision' then
    begin v_value:=(p_response->>'value')::numeric; exception when others then return 0; end;
    begin v_target:=coalesce((p_spec->>'target')::numeric,(select k.correct_number from private.quiz_round_answer_keys k where k.round_id=p_round.id)); exception when others then v_target:=null; end;
    if v_target is null then return 0; end if;
    begin v_gold:=greatest(0,(p_spec#>>'{precision,gold}')::numeric); exception when others then v_gold:=1; end;
    begin v_silver:=greatest(v_gold,(p_spec#>>'{precision,silver}')::numeric); exception when others then v_silver:=v_gold*2; end;
    begin v_bronze:=greatest(v_silver,(p_spec#>>'{precision,bronze}')::numeric); exception when others then v_bronze:=v_silver*2; end;
    v_diff:=abs(v_value-v_target);
    if v_diff<=v_gold then return 1; elsif v_diff<=v_silver then return .70; elsif v_diff<=v_bronze then return .40; else return 0; end if;
  elsif p_type='ordering' then
    v_correct:=coalesce(p_spec->'correct_order','[]'::jsonb); v_values:=coalesce(p_response->'order','[]'::jsonb);
    if jsonb_typeof(v_correct)<>'array' or jsonb_array_length(v_correct)=0 then return 0; end if;
    v_total:=jsonb_array_length(v_correct);
    select count(*) into v_hits from jsonb_array_elements_text(v_correct) with ordinality c(val,pos)
      join jsonb_array_elements_text(v_values) with ordinality a(val,pos) on a.pos=c.pos and a.val=c.val;
    return v_hits::numeric/greatest(1,v_total);
  elsif p_type='matching' then
    v_correct:=coalesce(p_spec->'correct_matches','{}'::jsonb); v_values:=coalesce(p_response->'matches','{}'::jsonb);
    if jsonb_typeof(v_correct)<>'object' then return 0; end if;
    for v_key in select jsonb_object_keys(v_correct) loop v_total:=v_total+1; if v_values->>v_key=v_correct->>v_key then v_hits:=v_hits+1; end if; end loop;
    return case when v_total=0 then 0 else v_hits::numeric/v_total end;
  elsif p_type='classification' then
    v_correct:=coalesce(p_spec->'classification_answers','{}'::jsonb); v_values:=coalesce(p_response->'classes','{}'::jsonb);
    if jsonb_typeof(v_correct)<>'object' then return 0; end if;
    for v_key in select jsonb_object_keys(v_correct) loop v_total:=v_total+1; if v_values->>v_key=v_correct->>v_key then v_hits:=v_hits+1; end if; end loop;
    return case when v_total=0 then 0 else v_hits::numeric/v_total end;
  elsif p_type='true_false_series' then
    v_correct:=coalesce(p_spec->'statement_answers','[]'::jsonb); v_values:=coalesce(p_response->'values','[]'::jsonb);
    if jsonb_typeof(v_correct)<>'array' or jsonb_array_length(v_correct)=0 then return 0; end if;
    v_total:=jsonb_array_length(v_correct);
    select count(*) into v_hits from jsonb_array_elements(v_correct) with ordinality c(val,pos)
      join jsonb_array_elements(v_values) with ordinality a(val,pos) on a.pos=c.pos and a.val=c.val;
    return v_hits::numeric/greatest(1,v_total);
  elsif p_type='team_mission' then
    v_correct:=coalesce(p_spec->'correct_choices','[]'::jsonb); v_values:=coalesce(p_response->'choices','[]'::jsonb);
    if jsonb_typeof(v_correct)<>'array' or jsonb_array_length(v_correct)=0 then return 0; end if;
    v_total:=jsonb_array_length(v_correct);
    select count(*) into v_hits from jsonb_array_elements_text(v_correct)c where exists(select 1 from jsonb_array_elements_text(v_values)a where a=c);
    return least(1,v_hits::numeric/greatest(1,v_total));
  elsif p_type='bingo' then
    v_selected:=coalesce(p_response->'cells','[]'::jsonb); v_arr:=coalesce(p_spec->'winning_lines','[]'::jsonb);
    if jsonb_typeof(v_selected)<>'array' or jsonb_typeof(v_arr)<>'array' then return 0; end if;
    for v_line in select value from jsonb_array_elements(v_arr) loop
      v_ok:=true;
      for v_item in select value from jsonb_array_elements(v_line) loop
        if not exists(select 1 from jsonb_array_elements(v_selected)s where s=v_item) then v_ok:=false; exit; end if;
      end loop;
      if v_ok then return 1; end if;
    end loop;
    return 0;
  elsif p_type in ('live_poll','audience_choice','category_choice') then
    return 0;
  else
    v_choice:=coalesce(p_response->>'choice','');
    v_correct_choice:=coalesce(p_spec->>'correct_choice',(select k.correct_choice from private.quiz_round_answer_keys k where k.round_id=p_round.id));
    return case when v_choice<>'' and v_correct_choice<>'' and upper(v_choice)=upper(v_correct_choice) then 1 else 0 end;
  end if;
end $$;
revoke all on function private.game_response_fraction(text,jsonb,jsonb,public.quiz_rounds) from public,anon,authenticated;

create or replace function private.game_distribution(p_round_id uuid,p_type text,p_target numeric default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v jsonb;
begin
  if p_type in ('nearest','precision') then
    select coalesce(jsonb_agg(jsonb_build_object('participant_id',g.participant_id,'value',g.response->'value','difference',case when p_target is null then null else abs((g.response->>'value')::numeric-p_target) end,'response_ms',g.response_ms,'points',g.awarded_points) order by case when p_target is null then g.response_ms else abs((g.response->>'value')::numeric-p_target) end,g.response_ms),'[]'::jsonb)
    into v from public.quiz_game_answers g where g.round_id=p_round_id;
  elsif p_type in ('ordering','matching','classification','true_false_series','team_mission','bingo') then
    select coalesce(jsonb_agg(jsonb_build_object('participant_id',g.participant_id,'score',g.awarded_points,'response_ms',g.response_ms) order by g.awarded_points desc,g.response_ms),'[]'::jsonb)
    into v from public.quiz_game_answers g where g.round_id=p_round_id;
  else
    select coalesce(jsonb_agg(jsonb_build_object('key',x.key,'count',x.c) order by x.c desc,x.key),'[]'::jsonb) into v
    from (select coalesce(nullif(g.response->>'choice',''),nullif(g.response->>'vote',''),'—') key,count(*) c from public.quiz_game_answers g where g.round_id=p_round_id group by 1)x;
  end if;
  return coalesce(v,'[]'::jsonb);
end $$;
revoke all on function private.game_distribution(uuid,text,numeric) from public,anon,authenticated;

create or replace function public.admin_close_and_score_round_r47(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_round public.quiz_rounds; v_type text; v_spec jsonb; v_base jsonb; v_points integer; v_fraction numeric; v_target numeric; v_majority text; v_rank jsonb; v_prev jsonb; v_dist jsonb; v_winners jsonb; v_result text; v_multiplier numeric:=1; v_segments jsonb; v_count integer; v_idx integer; g record;
begin
  perform private.require_admin_capability('present');
  perform private.require_live_control(p_room_id);
  select * into v_round from public.quiz_rounds where room_id=p_room_id and status='open' order by round_no desc limit 1;
  if not found then return public.admin_close_and_score_round(p_room_id); end if;
  v_type:=coalesce(v_round.game_type_snapshot,'standard');
  v_spec:=coalesce(v_round.game_spec_snapshot,'{}'::jsonb);
  v_base:=public.admin_close_and_score_round(p_room_id);
  if v_type='standard' then return v_base; end if;
  select * into v_round from public.quiz_rounds where id=v_round.id for update;
  v_points:=greatest(0,coalesce(v_round.points_snapshot,0));
  update public.quiz_game_answers set awarded_points=0 where round_id=v_round.id;

  if v_type='nearest' then
    begin v_target:=coalesce((v_spec->>'target')::numeric,(select k.correct_number from private.quiz_round_answer_keys k where k.round_id=v_round.id)); exception when others then v_target:=null; end;
    if v_target is not null then
      with ranked as(
        select id,dense_rank() over(order by abs((response->>'value')::numeric-v_target),response_ms) rn
        from public.quiz_game_answers where round_id=v_round.id
      ) update public.quiz_game_answers g set awarded_points=v_points from ranked r where g.id=r.id and r.rn=1;
    end if;
  elsif v_type='crowd_prediction' then
    select coalesce(nullif(response->>'choice',''),nullif(response->>'vote','')) into v_majority
    from public.quiz_game_answers where round_id=v_round.id
    group by 1 order by count(*) desc,min(submitted_at) asc limit 1;
    if v_majority is not null then update public.quiz_game_answers set awarded_points=v_points where round_id=v_round.id and coalesce(response->>'choice',response->>'vote')=v_majority; end if;
  else
    if v_type in ('wheel','surprise') then
      v_segments:=coalesce(case when v_type='wheel' then v_spec->'segments' else v_spec->'boxes' end,'[]'::jsonb);
      if jsonb_typeof(v_segments)='array' then v_count:=jsonb_array_length(v_segments); else v_count:=0; end if;
      if v_count>0 then
        v_idx:=mod(abs(hashtext(v_round.id::text)),v_count);
        begin v_multiplier:=greatest(0,least(5,coalesce((v_segments->v_idx->>'multiplier')::numeric,1))); exception when others then v_multiplier:=1; end;
      end if;
    end if;
    for g in select * from public.quiz_game_answers where round_id=v_round.id for update loop
      v_fraction:=private.game_response_fraction(v_type,v_spec,g.response,v_round);
      update public.quiz_game_answers set awarded_points=round(v_points*greatest(0,least(1,v_fraction))*v_multiplier)::integer where id=g.id;
    end loop;
  end if;

  update public.quiz_answers a set awarded_points=g.awarded_points
  from public.quiz_game_answers g where g.round_id=v_round.id and a.round_id=g.round_id and a.participant_id=g.participant_id;
  perform private.recalculate_room_totals(p_room_id);
  perform private.recalculate_aux_scores(p_room_id);
  v_rank:=private.generate_ranking(p_room_id);
  select coalesce(ranking_snapshot,'[]'::jsonb) into v_prev from public.quiz_rounds where room_id=p_room_id and round_no<v_round.round_no order by round_no desc limit 1;
  begin v_target:=coalesce((v_spec->>'target')::numeric,(select k.correct_number from private.quiz_round_answer_keys k where k.round_id=v_round.id)); exception when others then v_target:=null; end;
  v_dist:=private.game_distribution(v_round.id,v_type,v_target);
  select coalesce(jsonb_agg(jsonb_build_object('participant_id',x.participant_id,'display_name',x.display_name,'response_ms',x.response_ms,'points',x.awarded_points) order by x.awarded_points desc,x.response_ms),'[]'::jsonb)
  into v_winners from (select g.participant_id,p.display_name,g.response_ms,g.awarded_points from public.quiz_game_answers g join public.quiz_participants p on p.id=g.participant_id where g.round_id=v_round.id and g.awarded_points>0 order by g.awarded_points desc,g.response_ms limit 20)x;

  if v_type in ('nearest','precision') then v_result:='Valor alvo: '||coalesce(v_target::text,'—');
  elsif v_type='crowd_prediction' then v_result:='Previsão da sala: '||coalesce(v_majority,'—');
  elsif v_type='live_poll' then v_result:='Enquete encerrada';
  elsif v_type in ('audience_choice','category_choice') then
    select x.key into v_majority from jsonb_to_recordset(v_dist) as x(key text,c integer) order by x.c desc,x.key limit 1;
    v_result:='Escolha do público: '||coalesce(v_majority,'—');
  elsif v_type='ordering' then v_result:='Ordem correta revelada';
  elsif v_type='matching' then v_result:='Relacionamentos corretos revelados';
  elsif v_type='classification' then v_result:='Classificação correta revelada';
  elsif v_type='true_false_series' then v_result:='Gabarito Verdadeiro/Falso revelado';
  elsif v_type='bingo' then v_result:='Bingo encerrado';
  elsif v_type='wheel' then v_result:='Roda da Sorte encerrada';
  elsif v_type='surprise' then v_result:='Caixa Surpresa revelada';
  else v_result:=coalesce(nullif(v_spec->>'reveal_text',''),'Resultado revelado'); end if;

  update public.quiz_rounds set
    ranking_snapshot=v_rank,
    previous_ranking_snapshot=coalesce(v_prev,'[]'::jsonb),
    ranking_movers_snapshot=private.ranking_movers(coalesce(v_prev,'[]'::jsonb),v_rank),
    winner_snapshot=v_winners,
    distribution_snapshot=v_dist,
    result_text=v_result,
    answer_count_snapshot=(select count(*) from public.quiz_game_answers where round_id=v_round.id)
  where id=v_round.id;
  update public.quiz_rooms set final_ranking_snapshot=case when phase='finished' then v_rank else final_ranking_snapshot end where id=p_room_id;
  perform private.notify_room(p_room_id);
  return coalesce(v_base,'{}'::jsonb)||jsonb_build_object('game_type',v_type,'game_scored',true,'result_text',v_result,'answers',(select count(*) from public.quiz_game_answers where round_id=v_round.id));
end $$;
revoke all on function public.admin_close_and_score_round_r47(uuid) from public,anon;
grant execute on function public.admin_close_and_score_round_r47(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 4) Estado seguro do game para jogador/telão (sem gabarito enquanto aberto)
-- -----------------------------------------------------------------------------
create or replace function public.get_round_game_extras_by_code(p_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_round public.quiz_rounds; v_part public.quiz_participants; v_game public.quiz_game_answers; v_public_spec jsonb; v_round_json jsonb; v_reveal boolean; v_event jsonb; v_segments jsonb; v_count integer; v_idx integer;
begin
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if not found then return null; end if;
  select * into v_round from public.quiz_rounds where room_id=v_room.id order by round_no desc limit 1;
  if v_uid is not null then select * into v_part from public.quiz_participants where room_id=v_room.id and user_id=v_uid and not kicked limit 1; end if;
  if v_round.id is not null and v_part.id is not null then select * into v_game from public.quiz_game_answers where round_id=v_round.id and participant_id=v_part.id; end if;
  v_reveal:=v_room.phase='finished' or (v_room.phase='result' and coalesce(v_room.reveal_stage,'hidden') in ('answer','distribution','ranking','final'));
  if v_round.id is not null then
    v_public_spec:=coalesce(v_round.game_spec_snapshot,'{}'::jsonb);
    if not v_reveal then
      v_public_spec:=v_public_spec-'target'-'precision'-'correct_order'-'correct_matches'-'classification_answers'-'statement_answers'-'correct_choices'-'winning_lines'-'correct_choice'-'after_url'-'outcomes'-'reveal_text';
    end if;
    if v_round.game_type_snapshot in ('wheel','surprise') then
      v_segments:=coalesce(case when v_round.game_type_snapshot='wheel' then v_round.game_spec_snapshot->'segments' else v_round.game_spec_snapshot->'boxes' end,'[]'::jsonb);
      if jsonb_typeof(v_segments)='array' then v_count:=jsonb_array_length(v_segments); else v_count:=0; end if;
      if v_count>0 then v_idx:=mod(abs(hashtext(v_round.id::text)),v_count); v_event:=v_segments->v_idx; end if;
    end if;
    v_round_json:=jsonb_build_object(
      'id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,'closes_at',v_round.closes_at,
      'prompt',v_round.prompt_snapshot,'question_type',v_round.question_type_snapshot,'options',coalesce(v_round.options_snapshot,'[]'::jsonb),'points',v_round.points_snapshot,
      'category',v_round.category_snapshot,'difficulty',v_round.difficulty_snapshot,
      'media_type',v_round.media_type_snapshot,'media_url',v_round.media_url_snapshot,'media_caption',v_round.media_caption_snapshot,'special_type',v_round.special_type_snapshot,
      'game_type',coalesce(v_round.game_type_snapshot,'standard'),'game_spec',v_public_spec,'game_event',case when v_reveal then v_event else null end,
      'result_text',case when v_reveal then v_round.result_text else null end,
      'distribution',case when v_reveal and coalesce(v_room.reveal_stage,'hidden') in ('distribution','ranking','final') or v_room.phase='finished' then v_round.distribution_snapshot else null end,
      'movers',case when v_reveal and coalesce(v_room.reveal_stage,'hidden') in ('ranking','final') or v_room.phase='finished' then v_round.ranking_movers_snapshot else null end,
      'response_count',(select count(*) from public.quiz_game_answers g where g.round_id=v_round.id)
    );
  end if;
  return jsonb_build_object(
    'room_id',v_room.id,'code',v_room.code,'title',v_room.title,'phase',v_room.phase,'reveal_stage',v_room.reveal_stage,'settings',v_room.settings,'is_rehearsal',v_room.is_rehearsal,
    'planned_rounds',v_room.planned_rounds,'round',v_round_json,
    'my_response',case when v_game.id is null then null else jsonb_build_object('response',v_game.response,'response_ms',v_game.response_ms,'awarded_points',case when v_reveal then v_game.awarded_points else null end,'submitted_at',v_game.submitted_at) end,
    'server_now',clock_timestamp()
  );
end $$;
revoke all on function public.get_round_game_extras_by_code(text) from public;
grant execute on function public.get_round_game_extras_by_code(text) to anon,authenticated;

-- -----------------------------------------------------------------------------
-- 5) Escolha do público fora do round + automação da fila
-- -----------------------------------------------------------------------------
create or replace function public.admin_set_public_vote(p_room_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_room public.quiz_rooms; v_payload jsonb:=coalesce(p_payload,'{}'::jsonb); v_cycle integer;
begin
  perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id);
  select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found then raise exception 'Sala inválida'; end if;
  if jsonb_typeof(v_payload)<>'object' then raise exception 'Votação inválida'; end if;
  v_cycle:=coalesce((v_room.settings#>>'{pro_public_vote,cycle}')::integer,0)+1;
  v_payload:=v_payload||jsonb_build_object('cycle',v_cycle,'updated_at',clock_timestamp());
  update public.quiz_rooms set settings=jsonb_set(settings,'{pro_public_vote}',v_payload,true) where id=p_room_id returning * into v_room;
  perform private.notify_room(p_room_id);
  return v_room.settings->'pro_public_vote';
end $$;
revoke all on function public.admin_set_public_vote(uuid,jsonb) from public,anon;
grant execute on function public.admin_set_public_vote(uuid,jsonb) to authenticated;

create or replace function public.pro_submit_public_vote(p_code text,p_value text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_part public.quiz_participants; v_vote jsonb; v_cycle integer; v_type text; v_value text:=left(trim(coalesce(p_value,'')),120); v_options jsonb;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) and status<>'finished' order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;
  v_vote:=coalesce(v_room.settings->'pro_public_vote','{}'::jsonb);
  if coalesce((v_vote->>'open')::boolean,false) is not true then raise exception 'Votação fechada'; end if;
  v_cycle:=coalesce((v_vote->>'cycle')::integer,1); v_type:=coalesce(v_vote->>'type','audience_choice'); v_options:=coalesce(v_vote->'options','[]'::jsonb);
  if v_value='' or not exists(select 1 from jsonb_array_elements(v_options)o where coalesce(o->>'value',o->>'label')=v_value) then raise exception 'Opção inválida'; end if;
  select * into v_part from public.quiz_participants where room_id=v_room.id and user_id=v_uid and not kicked; if not found then raise exception 'Participante não encontrado'; end if;
  insert into public.quiz_room_votes(room_id,participant_id,vote_type,cycle,value,submitted_at)
  values(v_room.id,v_part.id,v_type,v_cycle,v_value,clock_timestamp())
  on conflict(room_id,participant_id,vote_type,cycle) do update set value=excluded.value,submitted_at=excluded.submitted_at;
  perform private.notify_room(v_room.id);
  return jsonb_build_object('accepted',true,'value',v_value,'cycle',v_cycle);
end $$;
revoke all on function public.pro_submit_public_vote(text,text) from public;
grant execute on function public.pro_submit_public_vote(text,text) to authenticated;

create or replace function public.pro_public_vote_summary(p_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_part public.quiz_participants; v_vote jsonb; v_cycle integer; v_type text; v_rows jsonb; v_my text;
begin
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1; if not found then return null; end if;
  v_vote:=coalesce(v_room.settings->'pro_public_vote','{}'::jsonb); v_cycle:=coalesce((v_vote->>'cycle')::integer,1); v_type:=coalesce(v_vote->>'type','audience_choice');
  select coalesce(jsonb_agg(jsonb_build_object('value',x.value,'count',x.c) order by x.c desc,x.value),'[]'::jsonb) into v_rows
  from (select value,count(*) c from public.quiz_room_votes where room_id=v_room.id and vote_type=v_type and cycle=v_cycle group by value)x;
  if v_uid is not null then select * into v_part from public.quiz_participants where room_id=v_room.id and user_id=v_uid and not kicked limit 1; end if;
  if v_part.id is not null then select value into v_my from public.quiz_room_votes where room_id=v_room.id and participant_id=v_part.id and vote_type=v_type and cycle=v_cycle; end if;
  return jsonb_build_object('vote',v_vote,'results',v_rows,'my_vote',v_my,'server_now',clock_timestamp());
end $$;
revoke all on function public.pro_public_vote_summary(text) from public;
grant execute on function public.pro_public_vote_summary(text) to anon,authenticated;

create or replace function public.admin_queue_smart_question(p_room_id uuid,p_strategy text,p_value text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_strategy text:=lower(coalesce(p_strategy,'chosen')); v_category text:=nullif(trim(coalesce(p_value,'')),''); v_difficulty text; v_question public.quiz_questions; v_queue uuid; v_accuracy numeric; v_vote jsonb; v_cycle integer; v_type text;
begin
  perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id);
  select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found then raise exception 'Sala inválida'; end if;
  if v_strategy='audience' then
    v_vote:=coalesce(v_room.settings->'pro_public_vote','{}'::jsonb); v_cycle:=coalesce((v_vote->>'cycle')::integer,1); v_type:=coalesce(v_vote->>'type','audience_choice');
    select value into v_category from public.quiz_room_votes where room_id=p_room_id and vote_type=v_type and cycle=v_cycle group by value order by count(*) desc,min(submitted_at) limit 1;
    if v_category is null then raise exception 'Ainda não há votos suficientes'; end if;
  elsif v_strategy='random' then
    select q.category into v_category from public.quiz_questions q where q.created_by=v_uid and q.active and q.archived_at is null group by q.category order by random() limit 1;
  elsif v_strategy='progressive' then
    select avg(case when a.awarded_points>0 then 1.0 else 0.0 end) into v_accuracy
    from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id
    where r.room_id=p_room_id and r.status='closed' and r.round_no>(select greatest(0,coalesce(max(round_no),0)-3) from public.quiz_rounds where room_id=p_room_id);
    v_difficulty:=case when coalesce(v_accuracy,.6)>=.75 then 'dificil' when coalesce(v_accuracy,.6)<=.45 then 'facil' else 'medio' end;
  elsif v_strategy<>'chosen' then raise exception 'Estratégia inválida'; end if;

  select * into v_question from public.quiz_questions q
  where q.created_by=v_uid and q.active and q.archived_at is null
    and (v_category is null or lower(q.category)=lower(v_category))
    and (v_difficulty is null or lower(q.difficulty)=lower(v_difficulty))
    and not exists(select 1 from public.quiz_room_queue rq where rq.room_id=p_room_id and rq.question_id=q.id)
  order by q.starred desc,random() limit 1;
  if not found then
    select * into v_question from public.quiz_questions q
    where q.created_by=v_uid and q.active and q.archived_at is null
      and (v_category is null or lower(q.category)=lower(v_category))
      and (v_difficulty is null or lower(q.difficulty)=lower(v_difficulty))
    order by q.starred desc,random() limit 1;
  end if;
  if not found then raise exception 'Nenhuma pergunta encontrada para esse critério'; end if;
  v_queue:=public.admin_queue_question(p_room_id,v_question.id);
  return jsonb_build_object('queue_id',v_queue,'question_id',v_question.id,'prompt',v_question.prompt,'category',v_question.category,'difficulty',v_question.difficulty,'strategy',v_strategy);
end $$;
revoke all on function public.admin_queue_smart_question(uuid,text,text) from public,anon;
grant execute on function public.admin_queue_smart_question(uuid,text,text) to authenticated;

-- -----------------------------------------------------------------------------
-- 6) Importação Pro r47 com game_type/game_spec
-- -----------------------------------------------------------------------------
create or replace function public.admin_import_questions_pro(p_questions jsonb,p_mode text default 'append')
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); x jsonb; v_id uuid; v_count integer:=0; v_mode text:=lower(coalesce(p_mode,'append')); v_type text; v_opts jsonb; v_correct_choice text; v_correct_number numeric; v_game_type text; v_game_spec jsonb;
begin
  perform private.require_admin_capability('edit');
  perform private.require_active_room_control_if_any();
  if jsonb_typeof(coalesce(p_questions,'[]'::jsonb))<>'array' then raise exception 'Lista inválida'; end if;
  if v_mode not in ('append','replace') then v_mode:='append'; end if;
  if jsonb_array_length(p_questions)>500 then raise exception 'Máximo de 500 perguntas por lote'; end if;
  if v_mode='replace' then update public.quiz_questions set archived_at=clock_timestamp() where created_by=v_uid and active and archived_at is null; end if;
  for x in select value from jsonb_array_elements(p_questions) loop
    v_type:=case when lower(coalesce(x->>'question_type','choice'))='numeric' then 'numeric' else 'choice' end;
    v_opts:=case when v_type='choice' then coalesce(x->'options','[]'::jsonb) else null end;
    v_correct_choice:=case when v_type='choice' then upper(coalesce(x->>'correct_choice','')) else null end;
    begin v_correct_number:=case when v_type='numeric' then (x->>'correct_number')::numeric else null end; exception when others then v_correct_number:=null; end;
    v_id:=public.admin_create_question_v2_r28_impl(coalesce(x->>'prompt',''),v_type,v_opts,v_correct_choice,v_correct_number,coalesce((x->>'points')::integer,100),coalesce((x->>'time_limit_seconds')::integer,30));
    perform public.admin_update_question_metadata_r28_impl(v_id,coalesce(x->>'category','Geral'),coalesce(x->>'difficulty','medio'),coalesce((x->>'score_enabled')::boolean,true),coalesce((x->>'speed_bonus_pct')::integer,0),coalesce((x->>'is_tiebreaker')::boolean,false),coalesce(x->>'presenter_notes',''));
    v_game_type:=lower(coalesce(x->>'game_type','standard')); v_game_spec:=coalesce(x->'game_spec','{}'::jsonb);
    if v_game_type not in ('standard','nearest','precision','ordering','matching','classification','true_false_series','hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','team_mission','bingo','wheel','surprise','crowd_prediction','live_poll','audience_choice','category_choice') then v_game_type:='standard'; end if;
    if jsonb_typeof(v_game_spec)<>'object' then v_game_spec:='{}'::jsonb; end if;
    update public.quiz_questions set
      media_type=case when lower(coalesce(x->>'media_type','none')) in ('none','image','audio','video') then lower(coalesce(x->>'media_type','none')) else 'none' end,
      media_url=case when coalesce(x->>'media_url','') ~ '^https://' then left(x->>'media_url',1000) else null end,
      media_caption=left(coalesce(x->>'media_caption',''),240),
      special_type=case when lower(coalesce(x->>'special_type','normal')) in ('normal','double','lightning','tiebreaker','final','bonus') then lower(coalesce(x->>'special_type','normal')) else 'normal' end,
      tags=case when jsonb_typeof(coalesce(x->'tags','[]'::jsonb))='array' then coalesce(x->'tags','[]'::jsonb) else '[]'::jsonb end,
      source_label=left(coalesce(x->>'source_label',''),120),starred=coalesce((x->>'starred')::boolean,false),
      game_type=v_game_type,game_spec=v_game_spec
    where id=v_id;
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('imported',v_count,'mode',v_mode);
end $$;
revoke all on function public.admin_import_questions_pro(jsonb,text) from public,anon;
grant execute on function public.admin_import_questions_pro(jsonb,text) to authenticated;

-- -----------------------------------------------------------------------------
-- 7) Dashboard + handshake schema 042
-- -----------------------------------------------------------------------------
create or replace function public.admin_event_dashboard(p_room_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_room public.quiz_rooms; v_players jsonb; v_questions jsonb; v_fast jsonb; v_summary jsonb; v_teams jsonb;
begin
  perform private.require_admin_capability('view');
  select * into v_room from public.quiz_rooms where id=p_room_id and created_by=auth.uid(); if not found then raise exception 'Sala não encontrada'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name,'points',p.total_points,'streak',p.best_streak,'team_id',p.team_id) order by p.total_points desc,p.joined_at),'[]'::jsonb) into v_players from public.quiz_participants p where p.room_id=p_room_id and not p.kicked;
  select coalesce(jsonb_agg(jsonb_build_object(
    'round_no',r.round_no,'prompt',r.prompt_snapshot,'category',r.category_snapshot,'difficulty',r.difficulty_snapshot,
    'answers',coalesce(r.answer_count_snapshot,0),'participants',(select count(*) from public.quiz_participants p where p.room_id=p_room_id and not p.kicked),
    'accuracy',case when coalesce(r.answer_count_snapshot,0)>0 then round(100.0*(select count(*) from public.quiz_answers a where a.round_id=r.id and a.awarded_points>0)/greatest(1,coalesce(r.answer_count_snapshot,0)),1) else null end,
    'avg_response_ms',(select round(avg(a.response_ms)) from public.quiz_answers a where a.round_id=r.id),
    'special_type',r.special_type_snapshot,'media_type',r.media_type_snapshot,'game_type',r.game_type_snapshot
  ) order by r.round_no),'[]'::jsonb) into v_questions from public.quiz_rounds r where r.room_id=p_room_id;
  select to_jsonb(x) into v_fast from (select p.display_name name,a.response_ms,r.round_no,r.prompt_snapshot prompt from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id join public.quiz_participants p on p.id=a.participant_id where r.room_id=p_room_id and a.awarded_points>0 order by a.response_ms asc limit 1)x;
  select jsonb_build_object('players',(select count(*) from public.quiz_participants p where p.room_id=p_room_id and not p.kicked),'rounds',(select count(*) from public.quiz_rounds r where r.room_id=p_room_id),'answers',(select count(*) from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id where r.room_id=p_room_id),'avg_response_ms',(select round(avg(a.response_ms)) from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id where r.room_id=p_room_id),'total_points',(select coalesce(sum(p.total_points),0) from public.quiz_participants p where p.room_id=p_room_id and not p.kicked)) into v_summary;
  select coalesce(jsonb_agg(jsonb_build_object('team_id',t.id,'name',t.name,'color',t.color,'icon',t.icon,'points',coalesce(x.points,0),'players',coalesce(x.players,0)) order by coalesce(x.points,0) desc,t.sort_order),'[]'::jsonb) into v_teams from public.quiz_teams t left join lateral(select sum(p.total_points)::bigint points,count(*)::integer players from public.quiz_participants p where p.team_id=t.id and not p.kicked)x on true where t.room_id=p_room_id;
  return jsonb_build_object('room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'phase',v_room.phase,'settings',v_room.settings,'is_rehearsal',v_room.is_rehearsal),'summary',v_summary,'players',v_players,'questions',v_questions,'fastest_correct',v_fast,'teams',v_teams,'generated_at',clock_timestamp());
end $$;
revoke all on function public.admin_event_dashboard(uuid) from public,anon;
grant execute on function public.admin_event_dashboard(uuid) to authenticated;

create or replace function public.get_quiz_backend_meta()
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'schema_version',42,
    'release','3.68-r47',
    'min_frontend_build','3.68-r47',
    'features',jsonb_build_array(
      'secure_display_pairing','controller_backend_guard','round_eligibility_snapshot','display_state_privacy','build_handshake','avatar_catalog_31',
      'gameshow_pro','game_modes','teams','question_media','special_questions','professional_question_bank','csv_json_import','post_event_dashboard','audio_profiles','rehearsal_tools','admin_roles','event_branding',
      'nearest','precision_tiers','ordering','matching','classification','true_false_series','hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','team_mission','knowledge_bingo','wheel','surprise_box','chosen_category','random_category','progressive_difficulty','exam_mode','crowd_prediction','live_poll','audience_choice'
    ),
    'server_now',clock_timestamp()
  );
$$;
revoke all on function public.get_quiz_backend_meta() from public;
grant execute on function public.get_quiz_backend_meta() to anon,authenticated;
