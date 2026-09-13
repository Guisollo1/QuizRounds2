-- Quiz Rounds v3.0 — pacote game-show completo
-- Recursos: pré-round 3-2-1, pausa, classificação, streak/velocidade, entrada tardia,
-- participantes, anulação/reclassificação, histórico, templates, temas, apresentação por etapas.

alter table public.quiz_questions
  add column if not exists category text not null default 'Geral',
  add column if not exists difficulty text not null default 'medio',
  add column if not exists score_enabled boolean not null default true,
  add column if not exists speed_bonus_pct integer not null default 0,
  add column if not exists is_tiebreaker boolean not null default false,
  add column if not exists presenter_notes text not null default '',
  add column if not exists use_count integer not null default 0,
  add column if not exists last_used_at timestamptz;

do $$ begin
  alter table public.quiz_questions add constraint quiz_questions_difficulty_check check (difficulty in ('facil','medio','dificil','final'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.quiz_questions add constraint quiz_questions_speed_bonus_check check (speed_bonus_pct between 0 and 100);
exception when duplicate_object then null; end $$;

alter table public.quiz_rooms
  add column if not exists settings jsonb not null default jsonb_build_object(
    'classification_enabled',false,'qualify_top',5,'late_join_policy','allow_zero','late_join_until_round',999,
    'auto_close_all_answered',false,'streak_enabled',true,'streak_bonus',0,'speed_bonus_enabled',true,
    'avoid_recent_games',0,'banned_words',jsonb_build_array(),'sound_enabled',true,'result_reveal','staged',
    'theme','violet','allow_duplicate_names',false
  ),
  add column if not exists game_generation integer not null default 1,
  add column if not exists prepared_queue_id uuid,
  add column if not exists prepared_until timestamptz,
  add column if not exists reveal_stage text not null default 'hidden',
  add column if not exists paused_phase text,
  add column if not exists is_rehearsal boolean not null default false,
  add column if not exists theme_preset text not null default 'violet',
  add column if not exists logo_url text;

do $$ begin
  alter table public.quiz_rooms add constraint quiz_rooms_reveal_stage_check check (reveal_stage in ('hidden','answer','distribution','ranking','final'));
exception when duplicate_object then null; end $$;

alter table public.quiz_rooms drop constraint if exists quiz_rooms_phase_check;
alter table public.quiz_rooms add constraint quiz_rooms_phase_check check (phase in ('lobby','preparing','question_open','paused','result','finished'));

alter table public.quiz_participants
  add column if not exists ready boolean not null default false,
  add column if not exists kicked boolean not null default false,
  add column if not exists current_streak integer not null default 0,
  add column if not exists best_streak integer not null default 0,
  add column if not exists tiebreak_points integer not null default 0;

alter table public.quiz_room_queue
  add column if not exists category_snapshot text,
  add column if not exists difficulty_snapshot text,
  add column if not exists score_enabled_snapshot boolean,
  add column if not exists speed_bonus_pct_snapshot integer,
  add column if not exists is_tiebreaker_snapshot boolean,
  add column if not exists presenter_notes_snapshot text;

alter table public.quiz_rounds
  add column if not exists category_snapshot text,
  add column if not exists difficulty_snapshot text,
  add column if not exists score_enabled_snapshot boolean not null default true,
  add column if not exists speed_bonus_pct_snapshot integer not null default 0,
  add column if not exists is_tiebreaker_snapshot boolean not null default false,
  add column if not exists annulled boolean not null default false,
  add column if not exists distribution_snapshot jsonb,
  add column if not exists previous_ranking_snapshot jsonb,
  add column if not exists ranking_movers_snapshot jsonb,
  add column if not exists presenter_notes_snapshot text,
  add column if not exists prepared_at timestamptz;

create table if not exists public.quiz_room_bans (
  room_id uuid not null references public.quiz_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text,
  created_at timestamptz not null default now(),
  primary key(room_id,user_id)
);
alter table public.quiz_room_bans enable row level security;
revoke all on public.quiz_room_bans from anon, authenticated;

create table if not exists public.quiz_event_templates (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  name text not null check(length(name) between 1 and 80),
  room_title text not null,
  settings jsonb not null default '{}'::jsonb,
  question_ids jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.quiz_event_templates enable row level security;
revoke all on public.quiz_event_templates from anon, authenticated;

create index if not exists quiz_questions_category_idx on public.quiz_questions(created_by,archived_at,category,difficulty,last_used_at);
create index if not exists quiz_participants_room_ready_idx on public.quiz_participants(room_id,kicked,ready,last_seen_at desc);
create index if not exists quiz_room_bans_room_idx on public.quiz_room_bans(room_id,user_id);

-- Sincroniza snapshots extras das filas existentes.
update public.quiz_room_queue q
set category_snapshot=coalesce(q.category_snapshot,qq.category),
    difficulty_snapshot=coalesce(q.difficulty_snapshot,qq.difficulty),
    score_enabled_snapshot=coalesce(q.score_enabled_snapshot,qq.score_enabled),
    speed_bonus_pct_snapshot=coalesce(q.speed_bonus_pct_snapshot,qq.speed_bonus_pct),
    is_tiebreaker_snapshot=coalesce(q.is_tiebreaker_snapshot,qq.is_tiebreaker),
    presenter_notes_snapshot=coalesce(q.presenter_notes_snapshot,qq.presenter_notes)
from public.quiz_questions qq where qq.id=q.question_id;

create or replace function private.room_setting(p_room public.quiz_rooms,p_key text,p_default jsonb)
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(p_room.settings->p_key,p_default)
$$;
revoke all on function private.room_setting(public.quiz_rooms,text,jsonb) from public;

create or replace function private.generate_ranking(p_room_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'participant_id',x.id,'display_name',x.display_name,'total_points',x.total_points,
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

create or replace function private.ranking_movers(p_previous jsonb,p_current jsonb)
returns jsonb language sql stable security definer set search_path='' as $$
  with prev as (
    select value->>'participant_id' id, ordinality::int pos from jsonb_array_elements(coalesce(p_previous,'[]'::jsonb)) with ordinality
  ), cur as (
    select value->>'participant_id' id,value->>'display_name' display_name,ordinality::int pos from jsonb_array_elements(coalesce(p_current,'[]'::jsonb)) with ordinality
  )
  select coalesce(jsonb_agg(jsonb_build_object('participant_id',cur.id,'display_name',cur.display_name,'position',cur.pos,'change',coalesce(prev.pos,cur.pos)-cur.pos) order by abs(coalesce(prev.pos,cur.pos)-cur.pos) desc,cur.pos),'[]'::jsonb)
  from cur left join prev on prev.id=cur.id
$$;
revoke all on function private.ranking_movers(jsonb,jsonb) from public;

create or replace function private.open_round_from_queue(p_room_id uuid,p_round_no integer)
returns public.quiz_rounds language plpgsql security definer set search_path='' as $$
declare
  v_item public.quiz_room_queue; v_key private.quiz_queue_answer_keys; v_round public.quiz_rounds; v_now timestamptz:=clock_timestamp(); v_room public.quiz_rooms;
begin
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if v_room.prepared_queue_id is not null then
    select * into v_item from public.quiz_room_queue where id=v_room.prepared_queue_id and room_id=p_room_id and status='queued' for update;
  else
    select * into v_item from public.quiz_room_queue where room_id=p_room_id and status='queued' order by position,added_at limit 1 for update skip locked;
  end if;
  if not found then raise exception 'A fila de rounds está vazia'; end if;
  select * into v_key from private.quiz_queue_answer_keys where queue_id=v_item.id;
  if not found then raise exception 'Snapshot da resposta não encontrado'; end if;
  insert into public.quiz_rounds(
    room_id,question_id,round_no,status,opened_at,time_limit_seconds,closes_at,prompt_snapshot,question_type_snapshot,options_snapshot,points_snapshot,result_locked,
    category_snapshot,difficulty_snapshot,score_enabled_snapshot,speed_bonus_pct_snapshot,is_tiebreaker_snapshot,presenter_notes_snapshot,prepared_at
  ) values(
    p_room_id,v_item.question_id,p_round_no,'open',v_now,coalesce(v_item.time_limit_snapshot,30),v_now+make_interval(secs=>coalesce(v_item.time_limit_snapshot,30)),
    v_item.prompt_snapshot,v_item.question_type_snapshot,v_item.options_snapshot,v_item.points_snapshot,false,
    coalesce(v_item.category_snapshot,'Geral'),coalesce(v_item.difficulty_snapshot,'medio'),coalesce(v_item.score_enabled_snapshot,true),coalesce(v_item.speed_bonus_pct_snapshot,0),coalesce(v_item.is_tiebreaker_snapshot,false),coalesce(v_item.presenter_notes_snapshot,''),v_room.prepared_until
  ) returning * into v_round;
  insert into private.quiz_round_answer_keys(round_id,correct_choice,correct_number) values(v_round.id,v_key.correct_choice,v_key.correct_number);
  update public.quiz_room_queue set status='used',round_id=v_round.id,used_at=v_now where id=v_item.id;
  update public.quiz_questions set use_count=use_count+1,last_used_at=v_now where id=v_item.question_id;
  update public.quiz_rooms set prepared_queue_id=null,prepared_until=null where id=p_room_id;
  return v_round;
end $$;
revoke all on function private.open_round_from_queue(uuid,integer) from public;

create or replace function public.admin_update_question_metadata(
  p_question_id uuid,p_category text,p_difficulty text,p_score_enabled boolean,p_speed_bonus_pct integer,p_is_tiebreaker boolean,p_presenter_notes text
) returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  update public.quiz_questions set category=left(coalesce(nullif(trim(p_category),''),'Geral'),60),difficulty=case when p_difficulty in ('facil','medio','dificil','final') then p_difficulty else 'medio' end,
    score_enabled=coalesce(p_score_enabled,true),speed_bonus_pct=greatest(0,least(100,coalesce(p_speed_bonus_pct,0))),is_tiebreaker=coalesce(p_is_tiebreaker,false),presenter_notes=left(coalesce(p_presenter_notes,''),2000)
  where id=p_question_id and created_by=v_uid;
end $$;
revoke all on function public.admin_update_question_metadata(uuid,text,text,boolean,integer,boolean,text) from public;
grant execute on function public.admin_update_question_metadata(uuid,text,text,boolean,integer,boolean,text) to authenticated;

create or replace function public.admin_duplicate_question(p_question_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_q public.quiz_questions; v_k private.quiz_answer_keys; v_id uuid; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_q from public.quiz_questions where id=p_question_id and created_by=v_uid; if not found then raise exception 'Pergunta não encontrada'; end if;
  select * into v_k from private.quiz_answer_keys where question_id=v_q.id;
  insert into public.quiz_questions(created_by,prompt,question_type,options,points,time_limit_seconds,category,difficulty,score_enabled,speed_bonus_pct,is_tiebreaker,presenter_notes)
  values(v_uid,v_q.prompt||' (cópia)',v_q.question_type,v_q.options,v_q.points,v_q.time_limit_seconds,v_q.category,v_q.difficulty,v_q.score_enabled,v_q.speed_bonus_pct,v_q.is_tiebreaker,v_q.presenter_notes) returning id into v_id;
  insert into private.quiz_answer_keys(question_id,correct_choice,correct_number) values(v_id,v_k.correct_choice,v_k.correct_number);
  return v_id;
end $$;
revoke all on function public.admin_duplicate_question(uuid) from public;
grant execute on function public.admin_duplicate_question(uuid) to authenticated;

create or replace function public.admin_update_room_settings(p_room_id uuid,p_patch jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found or v_room.created_by<>v_uid then raise exception 'Sala inválida'; end if;
  update public.quiz_rooms set
    settings=coalesce(settings,'{}'::jsonb)||coalesce(p_patch,'{}'::jsonb),
    theme_preset=coalesce(p_patch->>'theme',theme_preset),
    logo_url=case when p_patch ? 'logo_url' then nullif(left(p_patch->>'logo_url',500),'') else logo_url end,
    is_rehearsal=case when p_patch ? 'is_rehearsal' then coalesce((p_patch->>'is_rehearsal')::boolean,false) else is_rehearsal end
  where id=p_room_id returning * into v_room;
  perform private.audit_event(p_room_id,v_uid,'settings_updated','room',p_room_id,coalesce(p_patch,'{}'::jsonb)); perform private.notify_room(p_room_id);
  return to_jsonb(v_room);
end $$;
revoke all on function public.admin_update_room_settings(uuid,jsonb) from public;
grant execute on function public.admin_update_room_settings(uuid,jsonb) to authenticated;

create or replace function public.player_set_ready(p_room_id uuid,p_ready boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); begin
  update public.quiz_participants set ready=coalesce(p_ready,true),last_seen_at=clock_timestamp() where room_id=p_room_id and user_id=v_uid and not kicked;
end $$;
revoke all on function public.player_set_ready(uuid,boolean) from public,anon;
grant execute on function public.player_set_ready(uuid,boolean) to authenticated;

create or replace function public.join_quiz_room(p_code text,p_name text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_room public.quiz_rooms; v_part public.quiz_participants; v_uid uuid:=auth.uid(); v_name text:=trim(p_name); v_rounds integer:=0; v_policy text; v_allow_dupes boolean; v_bad text; begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  if length(v_name)<1 or length(v_name)>32 then raise exception 'Nome inválido'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) and status<>'finished' order by created_at desc limit 1; if not found then raise exception 'Sala não encontrada ou encerrada'; end if;
  if exists(select 1 from public.quiz_room_bans where room_id=v_room.id and user_id=v_uid) then raise exception 'Este dispositivo foi removido desta sala'; end if;
  select count(*) into v_rounds from public.quiz_rounds where room_id=v_room.id;
  v_policy:=coalesce(v_room.settings->>'late_join_policy','allow_zero');
  if not exists(select 1 from public.quiz_participants where room_id=v_room.id and user_id=v_uid) then
    if v_policy='deny' and v_rounds>0 then raise exception 'Entrada tardia não permitida'; end if;
    if v_policy='until_round' and v_rounds>coalesce((v_room.settings->>'late_join_until_round')::int,1) then raise exception 'Período de entrada encerrado'; end if;
  end if;
  for v_bad in select jsonb_array_elements_text(coalesce(v_room.settings->'banned_words','[]'::jsonb)) loop
    if position(lower(v_bad) in lower(v_name))>0 then raise exception 'Nome não permitido'; end if;
  end loop;
  v_allow_dupes:=coalesce((v_room.settings->>'allow_duplicate_names')::boolean,false);
  if not v_allow_dupes and exists(select 1 from public.quiz_participants where room_id=v_room.id and lower(display_name)=lower(v_name) and user_id<>v_uid and not kicked) then
    raise exception 'Esse nome já está em uso';
  end if;
  insert into public.quiz_participants(room_id,user_id,display_name,last_join_at,last_seen_at,ready,kicked) values(v_room.id,v_uid,v_name,clock_timestamp(),clock_timestamp(),true,false)
  on conflict(room_id,user_id) do update set display_name=excluded.display_name,last_join_at=excluded.last_join_at,last_seen_at=excluded.last_seen_at,ready=true,kicked=false returning * into v_part;
  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at) values(v_uid,v_room.id,'participant',clock_timestamp()) on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;
  perform private.notify_room(v_room.id);
  return jsonb_build_object('room',to_jsonb(v_room),'participant',to_jsonb(v_part),'missed_before_join',greatest(0,v_rounds));
end $$;
revoke all on function public.join_quiz_room(text,text) from public,anon;
grant execute on function public.join_quiz_room(text,text) to authenticated;

create or replace function public.admin_prepare_next_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_item public.quiz_room_queue; v_used int; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found then raise exception 'Sala inválida'; end if;
  if v_room.phase not in ('lobby','result') then raise exception 'Prepare apenas no lobby ou após um resultado'; end if;
  select * into v_item from public.quiz_room_queue where room_id=p_room_id and status='queued' order by position,added_at limit 1; if not found then raise exception 'Sem pergunta na fila'; end if;
  select count(*) into v_used from public.quiz_rounds where room_id=p_room_id;
  update public.quiz_rooms set phase='preparing',prepared_queue_id=v_item.id,prepared_until=clock_timestamp()+interval '3 seconds',reveal_stage='hidden',status='live',game_status='running' where id=p_room_id;
  perform private.audit_event(p_room_id,v_uid,'round_prepared','queue',v_item.id,jsonb_build_object('next_round',v_used+1)); perform private.publish_room_event(p_room_id,'round_prepared',jsonb_build_object('next_round',v_used+1,'seconds',3));
  return jsonb_build_object('prepared',true,'next_round',v_used+1,'opens_after',3);
end $$;
revoke all on function public.admin_prepare_next_round(uuid) from public;
grant execute on function public.admin_prepare_next_round(uuid) to authenticated;

create or replace function public.admin_open_prepared_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_round public.quiz_rounds; v_no int; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found then raise exception 'Sala inválida'; end if;
  if v_room.phase='question_open' then select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1; return jsonb_build_object('already_applied',true,'round',to_jsonb(v_round)); end if;
  if v_room.phase<>'preparing' or v_room.prepared_queue_id is null then raise exception 'Nenhum round preparado'; end if;
  if v_room.prepared_until is not null and clock_timestamp()<v_room.prepared_until then raise exception 'Contagem regressiva ainda em andamento'; end if;
  select count(*)+1 into v_no from public.quiz_rounds where room_id=p_room_id;
  select * into v_round from private.open_round_from_queue(p_room_id,v_no);
  update public.quiz_rooms set phase='question_open',reveal_stage='hidden',started_at=coalesce(started_at,clock_timestamp()) where id=p_room_id;
  perform private.audit_event(p_room_id,v_uid,'round_opened','round',v_round.id,jsonb_build_object('round_no',v_no)); perform private.publish_room_event(p_room_id,'round_opened',jsonb_build_object('round_no',v_no));
  return jsonb_build_object('opened',true,'round',to_jsonb(v_round));
end $$;
revoke all on function public.admin_open_prepared_round(uuid) from public;
grant execute on function public.admin_open_prepared_round(uuid) to authenticated;

create or replace function public.admin_start_quiz(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_count int; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found then raise exception 'Sala inválida'; end if;
  if v_room.phase<>'lobby' then return jsonb_build_object('already_applied',true,'phase',v_room.phase); end if;
  if exists(select 1 from public.quiz_rounds where room_id=p_room_id) then raise exception 'Esta sala já possui rounds iniciados'; end if;
  select count(*) into v_count from public.quiz_room_queue where room_id=p_room_id and status='queued'; if v_count<>v_room.planned_rounds then raise exception 'Escolha exatamente a quantidade configurada de perguntas'; end if;
  if v_room.randomize_queue then perform private.shuffle_room_queue(p_room_id); end if;
  update public.quiz_rooms set status='live',game_status='running',started_at=clock_timestamp(),finished_at=null,final_ranking_snapshot=null,reveal_stage='hidden' where id=p_room_id;
  return public.admin_prepare_next_round(p_room_id);
end $$;
revoke all on function public.admin_start_quiz(uuid) from public;
grant execute on function public.admin_start_quiz(uuid) to authenticated;

create or replace function public.admin_pause_quiz(p_room_id uuid,p_pause boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found then raise exception 'Sala inválida'; end if;
  if p_pause then
    if v_room.phase='question_open' then raise exception 'Pause entre rounds; não pause uma pergunta aberta'; end if;
    if v_room.phase in ('finished','paused') then return to_jsonb(v_room); end if;
    update public.quiz_rooms set paused_phase=v_room.phase,phase='paused' where id=p_room_id returning * into v_room;
  else
    if v_room.phase<>'paused' then return to_jsonb(v_room); end if;
    update public.quiz_rooms set phase=coalesce(nullif(v_room.paused_phase,''),'result'),paused_phase=null where id=p_room_id returning * into v_room;
  end if;
  perform private.audit_event(p_room_id,v_uid,case when p_pause then 'quiz_paused' else 'quiz_resumed' end,'room',p_room_id,'{}'::jsonb); perform private.notify_room(p_room_id); return to_jsonb(v_room);
end $$;
revoke all on function public.admin_pause_quiz(uuid,boolean) from public;
grant execute on function public.admin_pause_quiz(uuid,boolean) to authenticated;

create or replace function public.admin_extend_round(p_room_id uuid,p_seconds integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_round public.quiz_rounds; v_s int:=greatest(1,least(60,coalesce(p_seconds,5))); begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select r.* into v_round from public.quiz_rounds r join public.quiz_rooms rm on rm.id=r.room_id where r.room_id=p_room_id and r.status='open' and rm.phase='question_open' order by r.round_no desc limit 1 for update;
  if not found then raise exception 'Nenhum round aberto'; end if;
  if clock_timestamp()>v_round.closes_at then raise exception 'O prazo já terminou'; end if;
  update public.quiz_rounds set closes_at=closes_at+make_interval(secs=>v_s),time_limit_seconds=time_limit_seconds+v_s where id=v_round.id returning * into v_round;
  perform private.audit_event(p_room_id,v_uid,'round_extended','round',v_round.id,jsonb_build_object('seconds',v_s)); perform private.publish_room_event(p_room_id,'round_extended',jsonb_build_object('seconds',v_s)); return to_jsonb(v_round);
end $$;
revoke all on function public.admin_extend_round(uuid,integer) from public;
grant execute on function public.admin_extend_round(uuid,integer) to authenticated;

create or replace function public.admin_set_reveal_stage(p_room_id uuid,p_stage text)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_stage not in ('hidden','answer','distribution','ranking','final') then raise exception 'Etapa inválida'; end if;
  update public.quiz_rooms set reveal_stage=p_stage where id=p_room_id; perform private.publish_room_event(p_room_id,'reveal_changed',jsonb_build_object('stage',p_stage));
end $$;
revoke all on function public.admin_set_reveal_stage(uuid,text) from public;
grant execute on function public.admin_set_reveal_stage(uuid,text) to authenticated;

create or replace function private.recalculate_room_totals(p_room_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  update public.quiz_participants p set total_points=coalesce((select sum(a.awarded_points)::int from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id where a.participant_id=p.id and r.room_id=p_room_id and not r.annulled),0) where p.room_id=p_room_id;
end $$;
revoke all on function private.recalculate_room_totals(uuid) from public;

create or replace function public.admin_close_and_score_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_round public.quiz_rounds; v_key private.quiz_round_answer_keys; v_count int:=0; v_round_count int:=0; v_result text; v_rank jsonb; v_prev jsonb; v_movers jsonb; v_winners jsonb:='[]'::jsonb; v_finished boolean:=false; v_limit_ms numeric; v_dist jsonb;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found then raise exception 'Sala inválida'; end if;
  if v_room.phase in ('result','finished') then select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1; return jsonb_build_object('already_applied',true,'round_id',v_round.id,'finished',v_room.phase='finished'); end if;
  if v_room.phase<>'question_open' then raise exception 'Nenhum round aberto'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id and status='open' order by round_no desc limit 1 for update; if not found then raise exception 'Nenhum round aberto'; end if;
  select * into v_key from private.quiz_round_answer_keys where round_id=v_round.id; if not found then raise exception 'Gabarito ausente'; end if;
  select coalesce(ranking_snapshot,'[]'::jsonb) into v_prev from public.quiz_rounds where room_id=p_room_id and status='closed' and round_no<v_round.round_no order by round_no desc limit 1; v_prev:=coalesce(v_prev,'[]'::jsonb);
  update public.quiz_answers set awarded_points=0 where round_id=v_round.id;
  v_limit_ms:=greatest(1,coalesce(v_round.time_limit_seconds,30)*1000);
  if coalesce(v_round.score_enabled_snapshot,true) then
    if v_round.question_type_snapshot='choice' then
      update public.quiz_answers a set awarded_points=(
        coalesce(v_round.points_snapshot,0) + case when coalesce((v_room.settings->>'speed_bonus_enabled')::boolean,true) and coalesce(v_round.speed_bonus_pct_snapshot,0)>0 and a.choice_value=v_key.correct_choice then
          round(coalesce(v_round.points_snapshot,0)*(v_round.speed_bonus_pct_snapshot/100.0)*greatest(0,1-(a.response_ms/v_limit_ms)))::int else 0 end
      ) where a.round_id=v_round.id and a.choice_value=v_key.correct_choice;
      v_result:='Resposta correta: '||v_key.correct_choice||coalesce((select ' — '||(o->>'text') from jsonb_array_elements(coalesce(v_round.options_snapshot,'[]'::jsonb)) o where o->>'key'=v_key.correct_choice limit 1),'');
      select coalesce(jsonb_agg(jsonb_build_object('key',x.k,'count',x.c) order by x.k),'[]'::jsonb) into v_dist from (select choice_value k,count(*) c from public.quiz_answers where round_id=v_round.id group by choice_value)x;
    else
      with ranked as (
        select a.id,row_number() over(order by abs(a.numeric_value-v_key.correct_number),a.response_ms,a.submitted_at,a.participant_id) rn from public.quiz_answers a where a.round_id=v_round.id
      ) update public.quiz_answers a set awarded_points=coalesce(v_round.points_snapshot,0) from ranked r where a.id=r.id and r.rn=1;
      v_result:='Valor correto: '||v_key.correct_number::text;
      select coalesce(jsonb_agg(jsonb_build_object('participant_id',a.participant_id,'value',a.numeric_value,'difference',abs(a.numeric_value-v_key.correct_number),'response_ms',a.response_ms) order by abs(a.numeric_value-v_key.correct_number),a.response_ms),'[]'::jsonb) into v_dist from public.quiz_answers a where a.round_id=v_round.id;
    end if;
  else
    v_result:=case when v_round.question_type_snapshot='choice' then 'Resposta correta: '||v_key.correct_choice else 'Valor correto: '||v_key.correct_number::text end||' • Round sem pontuação';
  end if;

  -- streaks: acerto pontuado aumenta sequência; erro/ausência zera.
  update public.quiz_participants p set current_streak=case when exists(select 1 from public.quiz_answers a where a.round_id=v_round.id and a.participant_id=p.id and a.awarded_points>0) then p.current_streak+1 else 0 end where p.room_id=p_room_id and not p.kicked;
  update public.quiz_participants set best_streak=greatest(best_streak,current_streak) where room_id=p_room_id;
  if coalesce((v_room.settings->>'streak_enabled')::boolean,true) and coalesce((v_room.settings->>'streak_bonus')::int,0)>0 then
    update public.quiz_answers a set awarded_points=a.awarded_points+coalesce((v_room.settings->>'streak_bonus')::int,0)*greatest(p.current_streak-1,0)
    from public.quiz_participants p where a.round_id=v_round.id and a.participant_id=p.id and a.awarded_points>0;
  end if;
  if v_round.is_tiebreaker_snapshot then
    update public.quiz_participants p set tiebreak_points=tiebreak_points+coalesce((select a.awarded_points from public.quiz_answers a where a.round_id=v_round.id and a.participant_id=p.id),0) where p.room_id=p_room_id;
  end if;
  perform private.recalculate_room_totals(p_room_id);
  select count(*) into v_count from public.quiz_answers where round_id=v_round.id;
  v_rank:=private.generate_ranking(p_room_id); v_movers:=private.ranking_movers(v_prev,v_rank);
  select coalesce(jsonb_agg(jsonb_build_object('participant_id',x.participant_id,'display_name',x.display_name,'response_ms',x.response_ms,'points',x.awarded_points) order by x.awarded_points desc,x.response_ms),'[]'::jsonb) into v_winners from (select a.participant_id,p.display_name,a.response_ms,a.awarded_points from public.quiz_answers a join public.quiz_participants p on p.id=a.participant_id where a.round_id=v_round.id and a.awarded_points>0 order by a.awarded_points desc,a.response_ms limit 20)x;
  perform set_config('quiz.allow_round_reset','on',true);
  update public.quiz_rounds set status='closed',closed_at=clock_timestamp(),result_text=v_result,answer_count_snapshot=v_count,ranking_snapshot=v_rank,previous_ranking_snapshot=v_prev,ranking_movers_snapshot=v_movers,winner_snapshot=v_winners,distribution_snapshot=coalesce(v_dist,'[]'::jsonb),result_locked=true where id=v_round.id;
  perform set_config('quiz.allow_round_reset','off',true);
  select count(*) into v_round_count from public.quiz_rounds where room_id=p_room_id;
  if v_round_count>=v_room.planned_rounds then update public.quiz_rooms set phase='finished',game_status='finished',status='finished',finished_at=clock_timestamp(),final_ranking_snapshot=v_rank,reveal_stage='answer' where id=p_room_id; v_finished:=true; else update public.quiz_rooms set phase='result',game_status='running',reveal_stage='answer' where id=p_room_id; end if;
  perform private.audit_event(p_room_id,v_uid,'round_closed','round',v_round.id,jsonb_build_object('round_no',v_round.round_no,'answers',v_count,'finished',v_finished)); perform private.publish_room_event(p_room_id,case when v_finished then 'quiz_finished' else 'round_closed' end,jsonb_build_object('round_no',v_round.round_no));
  return jsonb_build_object('already_applied',false,'round_id',v_round.id,'answers',v_count,'finished',v_finished,'result_text',v_result);
exception when others then perform set_config('quiz.allow_round_reset','off',true); raise; end $$;
revoke all on function public.admin_close_and_score_round(uuid) from public;
grant execute on function public.admin_close_and_score_round(uuid) to authenticated;

create or replace function public.admin_annul_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_round public.quiz_rounds; v_rank jsonb; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id and status='closed' order by round_no desc limit 1 for update; if not found then raise exception 'Nenhum round encerrado'; end if;
  perform set_config('quiz.allow_round_reset','on',true); update public.quiz_answers set awarded_points=0 where round_id=v_round.id; update public.quiz_rounds set annulled=true,result_text=coalesce(result_text,'')||' • PERGUNTA ANULADA' where id=v_round.id; perform private.recalculate_room_totals(p_room_id); v_rank:=private.generate_ranking(p_room_id); update public.quiz_rounds set ranking_snapshot=v_rank where id=v_round.id; update public.quiz_rooms set final_ranking_snapshot=case when phase='finished' then v_rank else final_ranking_snapshot end where id=p_room_id; perform set_config('quiz.allow_round_reset','off',true);
  perform private.audit_event(p_room_id,v_uid,'round_annulled','round',v_round.id,'{}'::jsonb); perform private.notify_room(p_room_id); return jsonb_build_object('annulled',true,'round_no',v_round.round_no);
exception when others then perform set_config('quiz.allow_round_reset','off',true); raise; end $$;
revoke all on function public.admin_annul_round(uuid) from public;
grant execute on function public.admin_annul_round(uuid) to authenticated;

create or replace function public.admin_regrade_round(p_room_id uuid,p_correct_choice text default null,p_correct_number numeric default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_round public.quiz_rounds; v_key private.quiz_round_answer_keys; v_rank jsonb; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id and status='closed' order by round_no desc limit 1 for update; if not found then raise exception 'Nenhum round encerrado'; end if;
  if v_round.question_type_snapshot='choice' then if upper(coalesce(p_correct_choice,'')) not in ('A','B','C','D') then raise exception 'Alternativa inválida'; end if; update private.quiz_round_answer_keys set correct_choice=upper(p_correct_choice),correct_number=null where round_id=v_round.id; else if p_correct_number is null then raise exception 'Valor obrigatório'; end if; update private.quiz_round_answer_keys set correct_choice=null,correct_number=p_correct_number where round_id=v_round.id; end if;
  -- regrade simples e determinístico; bônus de velocidade é recalculado para escolha.
  select * into v_key from private.quiz_round_answer_keys where round_id=v_round.id; update public.quiz_answers set awarded_points=0 where round_id=v_round.id;
  if not v_round.annulled and v_round.score_enabled_snapshot then
    if v_round.question_type_snapshot='choice' then update public.quiz_answers a set awarded_points=coalesce(v_round.points_snapshot,0) where a.round_id=v_round.id and a.choice_value=v_key.correct_choice;
    else with ranked as(select id,row_number() over(order by abs(numeric_value-v_key.correct_number),response_ms,submitted_at,participant_id) rn from public.quiz_answers where round_id=v_round.id) update public.quiz_answers a set awarded_points=coalesce(v_round.points_snapshot,0) from ranked r where a.id=r.id and r.rn=1; end if;
  end if;
  perform private.recalculate_room_totals(p_room_id); v_rank:=private.generate_ranking(p_room_id); perform set_config('quiz.allow_round_reset','on',true); update public.quiz_rounds set ranking_snapshot=v_rank,result_text=case when question_type_snapshot='choice' then 'Resposta correta: '||v_key.correct_choice else 'Valor correto: '||v_key.correct_number::text end where id=v_round.id; update public.quiz_rooms set final_ranking_snapshot=case when phase='finished' then v_rank else final_ranking_snapshot end where id=p_room_id; perform set_config('quiz.allow_round_reset','off',true); perform private.audit_event(p_room_id,v_uid,'round_regraded','round',v_round.id,'{}'::jsonb); perform private.notify_room(p_room_id); return jsonb_build_object('regraded',true,'round_no',v_round.round_no);
exception when others then perform set_config('quiz.allow_round_reset','off',true); raise; end $$;
revoke all on function public.admin_regrade_round(uuid,text,numeric) from public;
grant execute on function public.admin_regrade_round(uuid,text,numeric) to authenticated;

create or replace function public.admin_list_participants(p_room_id uuid)
returns jsonb language sql security definer set search_path='' as $$
  select case when private.is_admin(auth.uid()) then coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'user_id',p.user_id,'display_name',p.display_name,'total_points',p.total_points,'ready',p.ready,'kicked',p.kicked,'last_seen_at',p.last_seen_at,
    'current_streak',p.current_streak,'best_streak',p.best_streak,
    'answer_count',(select count(*) from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id where r.room_id=p_room_id and a.participant_id=p.id),
    'missed_count',greatest(0,(select count(*) from public.quiz_rounds r where r.room_id=p_room_id and r.status='closed')-(select count(*) from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id where r.room_id=p_room_id and a.participant_id=p.id)
  )) order by p.total_points desc,p.joined_at),'[]'::jsonb) else '[]'::jsonb end from public.quiz_participants p where p.room_id=p_room_id
$$;
revoke all on function public.admin_list_participants(uuid) from public;
grant execute on function public.admin_list_participants(uuid) to authenticated;

create or replace function public.admin_kick_participant(p_room_id uuid,p_participant_id uuid,p_block boolean default true)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_p public.quiz_participants; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if; select * into v_p from public.quiz_participants where id=p_participant_id and room_id=p_room_id; if not found then raise exception 'Participante inválido'; end if;
  update public.quiz_participants set kicked=true,ready=false where id=v_p.id; if coalesce(p_block,true) then insert into public.quiz_room_bans(room_id,user_id,reason) values(p_room_id,v_p.user_id,'Removido pelo administrador') on conflict(room_id,user_id) do nothing; end if; delete from public.quiz_realtime_memberships where room_id=p_room_id and user_id=v_p.user_id and role='participant'; perform private.audit_event(p_room_id,v_uid,'participant_kicked','participant',v_p.id,jsonb_build_object('blocked',p_block)); perform private.notify_room(p_room_id);
end $$;
revoke all on function public.admin_kick_participant(uuid,uuid,boolean) from public;
grant execute on function public.admin_kick_participant(uuid,uuid,boolean) to authenticated;

create or replace function public.admin_get_round_history(p_room_id uuid)
returns jsonb language sql security definer set search_path='' as $$
  select case when private.is_admin(auth.uid()) then coalesce(jsonb_agg(to_jsonb(x) order by x.round_no,x.display_name),'[]'::jsonb) else '[]'::jsonb end
  from (
    select r.round_no,r.id round_id,r.prompt_snapshot prompt,r.category_snapshot category,r.difficulty_snapshot difficulty,r.annulled,p.id participant_id,p.display_name,a.choice_value,a.numeric_value,a.response_ms,a.awarded_points,
      (select j.ordinality::int from jsonb_array_elements(coalesce(r.ranking_snapshot,'[]'::jsonb)) with ordinality as j(value,ordinality) where j.value->>'participant_id'=p.id::text limit 1) as current_position
    from public.quiz_rounds r cross join public.quiz_participants p left join public.quiz_answers a on a.round_id=r.id and a.participant_id=p.id where r.room_id=p_room_id and p.room_id=p_room_id
  ) x
$$;
revoke all on function public.admin_get_round_history(uuid) from public;
grant execute on function public.admin_get_round_history(uuid) to authenticated;

create or replace function public.admin_save_template(p_room_id uuid,p_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_id uuid; v_qids jsonb; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if; select * into v_room from public.quiz_rooms where id=p_room_id and created_by=v_uid; if not found then raise exception 'Sala inválida'; end if;
  select coalesce(jsonb_agg(question_id order by position),'[]'::jsonb) into v_qids from public.quiz_room_queue where room_id=p_room_id;
  insert into public.quiz_event_templates(created_by,name,room_title,settings,question_ids) values(v_uid,left(trim(p_name),80),v_room.title,v_room.settings,v_qids) returning id into v_id; return v_id;
end $$;
revoke all on function public.admin_save_template(uuid,text) from public;
grant execute on function public.admin_save_template(uuid,text) to authenticated;

create or replace function public.admin_list_templates()
returns jsonb language sql security definer set search_path='' as $$
  select case when private.is_admin(auth.uid()) then coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'room_title',room_title,'settings',settings,'question_count',jsonb_array_length(question_ids),'created_at',created_at) order by updated_at desc),'[]'::jsonb) else '[]'::jsonb end from public.quiz_event_templates where created_by=auth.uid()
$$;
revoke all on function public.admin_list_templates() from public;
grant execute on function public.admin_list_templates() to authenticated;

-- Estado do jogador com classificação, streak, geração e revelação controlada.
create or replace function public.get_game_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_part public.quiz_participants; v_room public.quiz_rooms; v_round public.quiz_rounds; v_my public.quiz_answers; v_round_json jsonb; v_rank jsonb; v_now timestamptz:=clock_timestamp(); v_pos int; v_missed int:=0; begin
  select * into v_part from public.quiz_participants where room_id=p_room_id and user_id=v_uid; if not found or v_part.kicked then raise exception 'Participante não pertence à sala'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id; if not found then raise exception 'Sala não encontrada'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1;
  if found then select * into v_my from public.quiz_answers where round_id=v_round.id and participant_id=v_part.id; v_round_json:=jsonb_build_object('id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,'closes_at',v_round.closes_at,'time_limit_seconds',v_round.time_limit_seconds,'accepting_responses',(v_room.phase='question_open' and v_round.status='open' and v_now<=v_round.closes_at),'prompt',v_round.prompt_snapshot,'question_type',v_round.question_type_snapshot,'options',coalesce(v_round.options_snapshot,'[]'::jsonb),'points',v_round.points_snapshot,'category',v_round.category_snapshot,'difficulty',v_round.difficulty_snapshot,'score_enabled',v_round.score_enabled_snapshot,'is_tiebreaker',v_round.is_tiebreaker_snapshot,'my_answer',case when v_my.id is null then null else to_jsonb(v_my) end,'result_text',case when v_round.status='closed' and v_room.reveal_stage in ('answer','distribution','ranking','final') then v_round.result_text else null end,'distribution',case when v_room.reveal_stage in ('distribution','ranking','final') then v_round.distribution_snapshot else null end,'movers',case when v_room.reveal_stage in ('ranking','final') then v_round.ranking_movers_snapshot else null end); else v_round_json:=null; end if;
  if v_room.reveal_stage in ('ranking','final') or v_room.phase='finished' then v_rank:=coalesce(case when v_round.id is not null then v_round.ranking_snapshot end,v_room.final_ranking_snapshot,'[]'::jsonb); else v_rank:='[]'::jsonb; end if;
  select ordinality::int into v_pos from jsonb_array_elements(coalesce(case when v_round.id is not null then v_round.ranking_snapshot end,v_room.final_ranking_snapshot,'[]'::jsonb)) with ordinality where value->>'participant_id'=v_part.id::text limit 1;
  select count(*) into v_missed from public.quiz_rounds r where r.room_id=p_room_id and r.status='closed' and not exists(select 1 from public.quiz_answers a where a.round_id=r.id and a.participant_id=v_part.id);
  return jsonb_build_object('room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'phase',v_room.phase,'state_version',v_room.state_version,'generation',v_room.game_generation,'settings',v_room.settings,'theme',v_room.theme_preset,'logo_url',v_room.logo_url,'prepared_until',v_room.prepared_until,'reveal_stage',v_room.reveal_stage),'round',v_round_json,'ranking',v_rank,'participant',jsonb_build_object('id',v_part.id,'display_name',v_part.display_name,'total_points',v_part.total_points,'current_streak',v_part.current_streak,'best_streak',v_part.best_streak,'position',v_pos,'ready',v_part.ready,'missed_rounds',v_missed),'server_now',v_now);
end $$;
revoke all on function public.get_game_state(uuid) from public,anon;
grant execute on function public.get_game_state(uuid) to authenticated;

create or replace function public.admin_get_room_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_round public.quiz_rounds; v_item public.quiz_room_queue; v_key private.quiz_round_answer_keys; v_round_json jsonb; v_rank jsonb; v_now timestamptz:=clock_timestamp(); v_participants int:=0;v_active int:=0;v_ready int:=0;v_answers int:=0;v_used int:=0;v_queued int:=0; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if; select * into v_room from public.quiz_rooms where id=p_room_id; if not found then raise exception 'Sala não encontrada'; end if;
  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at) values(v_uid,p_room_id,'admin',v_now) on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;
  select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1;
  if found then select * into v_key from private.quiz_round_answer_keys where round_id=v_round.id; v_round_json:=jsonb_build_object('id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,'closed_at',v_round.closed_at,'result_text',v_round.result_text,'time_limit_seconds',v_round.time_limit_seconds,'closes_at',v_round.closes_at,'accepting_responses',(v_room.phase='question_open' and v_round.status='open' and v_now<=v_round.closes_at),'prompt',v_round.prompt_snapshot,'question_type',v_round.question_type_snapshot,'options',coalesce(v_round.options_snapshot,'[]'::jsonb),'points',v_round.points_snapshot,'category',v_round.category_snapshot,'difficulty',v_round.difficulty_snapshot,'score_enabled',v_round.score_enabled_snapshot,'speed_bonus_pct',v_round.speed_bonus_pct_snapshot,'is_tiebreaker',v_round.is_tiebreaker_snapshot,'presenter_notes',coalesce(v_round.presenter_notes_snapshot,''),'annulled',v_round.annulled,'answer_count_snapshot',v_round.answer_count_snapshot,'winner_snapshot',v_round.winner_snapshot,'distribution',v_round.distribution_snapshot,'movers',v_round.ranking_movers_snapshot,'correct_choice',v_key.correct_choice,'correct_number',v_key.correct_number); end if;
  if v_room.prepared_queue_id is not null then select * into v_item from public.quiz_room_queue where id=v_room.prepared_queue_id; end if;
  v_rank:=private.generate_ranking(p_room_id); select count(*) into v_participants from public.quiz_participants where room_id=p_room_id and not kicked; select count(*) into v_active from public.quiz_participants where room_id=p_room_id and not kicked and last_seen_at>=v_now-interval '90 seconds'; select count(*) into v_ready from public.quiz_participants where room_id=p_room_id and not kicked and ready; select count(*) into v_used from public.quiz_rounds where room_id=p_room_id; select count(*) into v_queued from public.quiz_room_queue where room_id=p_room_id and status='queued'; if v_round.id is not null and v_round.status='open' then select count(*) into v_answers from public.quiz_answers where round_id=v_round.id; else v_answers:=coalesce(v_round.answer_count_snapshot,0); end if;
  return jsonb_build_object('room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'phase',v_room.phase,'state_version',v_room.state_version,'generation',v_room.game_generation,'started_at',v_room.started_at,'finished_at',v_room.finished_at,'randomize_queue',v_room.randomize_queue,'settings',v_room.settings,'theme',v_room.theme_preset,'logo_url',v_room.logo_url,'prepared_until',v_room.prepared_until,'reveal_stage',v_room.reveal_stage,'is_rehearsal',v_room.is_rehearsal),'round',v_round_json,'prepared',case when v_item.id is null then null else jsonb_build_object('queue_id',v_item.id,'prompt',v_item.prompt_snapshot,'question_type',v_item.question_type_snapshot,'options',v_item.options_snapshot,'points',v_item.points_snapshot,'category',v_item.category_snapshot,'difficulty',v_item.difficulty_snapshot,'presenter_notes',v_item.presenter_notes_snapshot) end,'ranking',v_rank,'participant_count',v_participants,'active_count',v_active,'ready_count',v_ready,'answer_count',v_answers,'used_rounds',v_used,'queued_count',v_queued,'server_now',v_now);
end $$;
revoke all on function public.admin_get_room_state(uuid) from public;
grant execute on function public.admin_get_room_state(uuid) to authenticated;

create or replace function public.get_public_display_state(p_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_room public.quiz_rooms;v_round public.quiz_rounds;v_round_json jsonb;v_rank jsonb;v_now timestamptz:=clock_timestamp();v_participants int:=0;v_active int:=0;v_answers int:=0;v_used int:=0; begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if; select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1; if not found then raise exception 'Sala não encontrada'; end if; if not exists(select 1 from public.quiz_realtime_memberships where user_id=v_uid and room_id=v_room.id and role in ('display','admin','participant')) then raise exception 'Tela não autorizada'; end if;
  select * into v_round from public.quiz_rounds where room_id=v_room.id order by round_no desc limit 1; if found then v_round_json:=jsonb_build_object('id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,'closed_at',v_round.closed_at,'closes_at',v_round.closes_at,'time_limit_seconds',v_round.time_limit_seconds,'prompt',v_round.prompt_snapshot,'question_type',v_round.question_type_snapshot,'options',coalesce(v_round.options_snapshot,'[]'::jsonb),'points',v_round.points_snapshot,'category',v_round.category_snapshot,'difficulty',v_round.difficulty_snapshot,'result_text',case when v_room.reveal_stage in ('answer','distribution','ranking','final') then v_round.result_text end,'winner_snapshot',case when v_room.reveal_stage in ('answer','distribution','ranking','final') then v_round.winner_snapshot end,'distribution',case when v_room.reveal_stage in ('distribution','ranking','final') then v_round.distribution_snapshot end,'movers',case when v_room.reveal_stage in ('ranking','final') then v_round.ranking_movers_snapshot end); end if;
  v_rank:=case when v_room.reveal_stage in ('ranking','final') or v_room.phase='finished' then private.generate_ranking(v_room.id) else '[]'::jsonb end; select count(*) into v_participants from public.quiz_participants where room_id=v_room.id and not kicked; select count(*) into v_active from public.quiz_participants where room_id=v_room.id and not kicked and last_seen_at>=v_now-interval '90 seconds'; select count(*) into v_used from public.quiz_rounds where room_id=v_room.id; if v_round.id is not null and v_round.status='open' then select count(*) into v_answers from public.quiz_answers where round_id=v_round.id; else v_answers:=coalesce(v_round.answer_count_snapshot,0); end if;
  return jsonb_build_object('room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'phase',v_room.phase,'state_version',v_room.state_version,'generation',v_room.game_generation,'settings',v_room.settings,'theme',v_room.theme_preset,'logo_url',v_room.logo_url,'prepared_until',v_room.prepared_until,'reveal_stage',v_room.reveal_stage),'round',v_round_json,'ranking',v_rank,'participant_count',v_participants,'active_count',v_active,'answer_count',v_answers,'used_rounds',v_used,'server_now',v_now);
end $$;
revoke all on function public.get_public_display_state(text) from public,anon;
grant execute on function public.get_public_display_state(text) to authenticated;

-- Reinício incrementa a geração para invalidar estados antigos dos navegadores.
create or replace function public.admin_restart_quiz(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_room public.quiz_rooms;v_count int; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if; select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found then raise exception 'Sala não encontrada'; end if; select count(*) into v_count from public.quiz_room_queue where room_id=p_room_id; if v_count<>v_room.planned_rounds then raise exception 'Fila incompleta'; end if; if not exists(select 1 from public.quiz_rounds where room_id=p_room_id) then raise exception 'A partida ainda não foi iniciada'; end if;
  perform set_config('quiz.allow_round_reset','on',true); delete from public.quiz_rounds where room_id=p_room_id; perform set_config('quiz.allow_round_reset','off',true); update public.quiz_room_queue set status='queued',round_id=null,used_at=null where room_id=p_room_id; update public.quiz_participants set total_points=0,tiebreak_points=0,current_streak=0,best_streak=0 where room_id=p_room_id; if v_room.randomize_queue then perform private.shuffle_room_queue(p_room_id); end if; update public.quiz_rooms set status='live',game_status='running',phase='lobby',started_at=null,finished_at=null,final_ranking_snapshot=null,prepared_queue_id=null,prepared_until=null,reveal_stage='hidden',game_generation=game_generation+1 where id=p_room_id; perform private.audit_event(p_room_id,v_uid,'quiz_restarted','room',p_room_id,jsonb_build_object('generation',v_room.game_generation+1)); perform private.notify_room(p_room_id); return jsonb_build_object('restarted',true,'phase','lobby','generation',v_room.game_generation+1);
exception when others then perform set_config('quiz.allow_round_reset','off',true); raise; end $$;
revoke all on function public.admin_restart_quiz(uuid) from public;
grant execute on function public.admin_restart_quiz(uuid) to authenticated;

create or replace function public.admin_list_question_bank(p_scope text default 'active')
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_result jsonb;v_scope text:=lower(coalesce(p_scope,'active')); begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if; if v_scope not in ('active','archived','all') then v_scope:='active'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.prompt,'question_type',q.question_type,'options',q.options,'points',q.points,'time_limit_seconds',q.time_limit_seconds,'correct_choice',k.correct_choice,'correct_number',k.correct_number,'archived',q.archived_at is not null,'archived_at',q.archived_at,'created_at',q.created_at,'category',q.category,'difficulty',q.difficulty,'score_enabled',q.score_enabled,'speed_bonus_pct',q.speed_bonus_pct,'is_tiebreaker',q.is_tiebreaker,'presenter_notes',q.presenter_notes,'use_count',q.use_count,'last_used_at',q.last_used_at) order by q.created_at desc),'[]'::jsonb) into v_result from public.quiz_questions q join private.quiz_answer_keys k on k.question_id=q.id where q.active and q.created_by=v_uid and (v_scope='all' or (v_scope='active' and q.archived_at is null) or (v_scope='archived' and q.archived_at is not null)); return v_result;
end $$;
revoke all on function public.admin_list_question_bank(text) from public;
grant execute on function public.admin_list_question_bank(text) to authenticated;

create or replace function public.admin_queue_question(p_room_id uuid,p_question_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_id uuid;v_pos int;v_q public.quiz_questions;v_k private.quiz_answer_keys; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if; if not exists(select 1 from public.quiz_rooms where id=p_room_id and created_by=v_uid and phase='lobby') then raise exception 'Fila bloqueada'; end if;
  select * into v_q from public.quiz_questions where id=p_question_id and active and archived_at is null; if not found then raise exception 'Pergunta inválida'; end if; select * into v_k from private.quiz_answer_keys where question_id=p_question_id;
  select coalesce(max(position),0)+1 into v_pos from public.quiz_room_queue where room_id=p_room_id;
  insert into public.quiz_room_queue(room_id,question_id,position,prompt_snapshot,question_type_snapshot,options_snapshot,points_snapshot,time_limit_snapshot,category_snapshot,difficulty_snapshot,score_enabled_snapshot,speed_bonus_pct_snapshot,is_tiebreaker_snapshot,presenter_notes_snapshot)
  values(p_room_id,p_question_id,v_pos,v_q.prompt,v_q.question_type,v_q.options,v_q.points,v_q.time_limit_seconds,v_q.category,v_q.difficulty,v_q.score_enabled,v_q.speed_bonus_pct,v_q.is_tiebreaker,v_q.presenter_notes) returning id into v_id;
  insert into private.quiz_queue_answer_keys(queue_id,correct_choice,correct_number) values(v_id,v_k.correct_choice,v_k.correct_number) on conflict(queue_id) do update set correct_choice=excluded.correct_choice,correct_number=excluded.correct_number;
  return v_id;
end $$;
revoke all on function public.admin_queue_question(uuid,uuid) from public;
grant execute on function public.admin_queue_question(uuid,uuid) to authenticated;

create or replace function public.admin_list_room_queue(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_result jsonb; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',rq.id,'question_id',rq.question_id,'position',rq.position,'status',rq.status,'round_id',rq.round_id,'prompt',rq.prompt_snapshot,'question_type',rq.question_type_snapshot,'options',rq.options_snapshot,'points',rq.points_snapshot,'time_limit_seconds',rq.time_limit_snapshot,'category',rq.category_snapshot,'difficulty',rq.difficulty_snapshot,'score_enabled',rq.score_enabled_snapshot,'speed_bonus_pct',rq.speed_bonus_pct_snapshot,'is_tiebreaker',rq.is_tiebreaker_snapshot,'presenter_notes',rq.presenter_notes_snapshot) order by rq.position,rq.added_at),'[]'::jsonb) into v_result from public.quiz_room_queue rq where rq.room_id=p_room_id; return v_result;
end $$;
revoke all on function public.admin_list_room_queue(uuid) from public;
grant execute on function public.admin_list_room_queue(uuid) to authenticated;

-- Reutilização de eventos e filtro de perguntas recentes.
create or replace function public.admin_recent_question_ids(p_room_id uuid,p_games integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_games integer:=greatest(0,least(50,coalesce(p_games,0))); v_result jsonb; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if not exists(select 1 from public.quiz_rooms where id=p_room_id and created_by=v_uid) then raise exception 'Sala inválida'; end if;
  if v_games=0 then return '[]'::jsonb; end if;
  with recent_rooms as (
    select id from public.quiz_rooms where created_by=v_uid and id<>p_room_id
    order by coalesce(started_at,created_at) desc limit v_games
  )
  select coalesce(jsonb_agg(distinct rq.question_id),'[]'::jsonb) into v_result
  from public.quiz_room_queue rq where rq.room_id in(select id from recent_rooms);
  return v_result;
end $$;
revoke all on function public.admin_recent_question_ids(uuid,integer) from public;
grant execute on function public.admin_recent_question_ids(uuid,integer) to authenticated;

create or replace function public.admin_create_from_template(p_template_id uuid,p_title text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_tpl public.quiz_event_templates; v_created jsonb; v_room_id uuid; v_q text; v_room public.quiz_rooms; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_tpl from public.quiz_event_templates where id=p_template_id and created_by=v_uid;
  if not found then raise exception 'Modelo não encontrado'; end if;
  if jsonb_array_length(v_tpl.question_ids)<1 then raise exception 'Modelo sem perguntas'; end if;
  v_created:=public.admin_create_room_v3(coalesce(nullif(trim(p_title),''),v_tpl.room_title),jsonb_array_length(v_tpl.question_ids));
  v_room_id:=(v_created->>'id')::uuid;
  update public.quiz_rooms set settings=v_tpl.settings,theme_preset=coalesce(v_tpl.settings->>'theme','violet'),is_rehearsal=false where id=v_room_id;
  for v_q in select value from jsonb_array_elements_text(v_tpl.question_ids) loop
    if exists(select 1 from public.quiz_questions where id=v_q::uuid and created_by=v_uid and active and archived_at is null) then
      perform public.admin_queue_question(v_room_id,v_q::uuid);
    end if;
  end loop;
  select * into v_room from public.quiz_rooms where id=v_room_id;
  perform private.audit_event(v_room_id,v_uid,'room_created_from_template','room',v_room_id,jsonb_build_object('template_id',p_template_id));
  return to_jsonb(v_room);
end $$;
revoke all on function public.admin_create_from_template(uuid,text) from public;
grant execute on function public.admin_create_from_template(uuid,text) to authenticated;

create or replace function public.admin_duplicate_room(p_room_id uuid,p_title text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_source public.quiz_rooms; v_created jsonb; v_new_id uuid; v_q uuid; v_room public.quiz_rooms; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_source from public.quiz_rooms where id=p_room_id and created_by=v_uid;
  if not found then raise exception 'Sala inválida'; end if;
  v_created:=public.admin_create_room_v3(coalesce(nullif(trim(p_title),''),v_source.title||' — cópia'),v_source.planned_rounds);
  v_new_id:=(v_created->>'id')::uuid;
  update public.quiz_rooms set settings=v_source.settings,theme_preset=v_source.theme_preset,logo_url=v_source.logo_url,randomize_queue=v_source.randomize_queue,is_rehearsal=v_source.is_rehearsal where id=v_new_id;
  for v_q in select question_id from public.quiz_room_queue where room_id=p_room_id order by position loop
    if exists(select 1 from public.quiz_questions where id=v_q and created_by=v_uid and active and archived_at is null) then
      perform public.admin_queue_question(v_new_id,v_q);
    end if;
  end loop;
  select * into v_room from public.quiz_rooms where id=v_new_id;
  perform private.audit_event(v_new_id,v_uid,'room_duplicated','room',v_new_id,jsonb_build_object('source_room_id',p_room_id));
  return to_jsonb(v_room);
end $$;
revoke all on function public.admin_duplicate_room(uuid,text) from public;
grant execute on function public.admin_duplicate_room(uuid,text) to authenticated;

-- Importação TXT/colar texto v3.0 com metadados de competição.
create or replace function public.admin_import_questions(p_questions jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid(); v_item jsonb; v_id uuid; v_prompt text; v_type text; v_options jsonb;
  v_correct_choice text; v_correct_number numeric; v_points integer; v_time integer; v_count integer:=0; v_ids jsonb:='[]'::jsonb;
  v_category text; v_difficulty text; v_score boolean; v_speed integer; v_tie boolean; v_notes text;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_questions is null or jsonb_typeof(p_questions)<>'array' or jsonb_array_length(p_questions)<1 then raise exception 'Lista de perguntas inválida'; end if;
  if jsonb_array_length(p_questions)>500 then raise exception 'Limite de 500 perguntas por importação'; end if;
  for v_item in select value from jsonb_array_elements(p_questions) loop
    v_prompt:=trim(coalesce(v_item->>'prompt','')); v_type:=lower(trim(coalesce(v_item->>'question_type',''))); v_options:=v_item->'options';
    v_correct_choice:=upper(trim(coalesce(v_item->>'correct_choice',''))); v_correct_number:=case when jsonb_typeof(v_item->'correct_number')='number' then (v_item->>'correct_number')::numeric else null end;
    v_points:=coalesce((v_item->>'points')::integer,10); v_time:=coalesce((v_item->>'time_limit_seconds')::integer,30);
    v_category:=left(coalesce(nullif(trim(v_item->>'category'),''),'Geral'),60); v_difficulty:=lower(coalesce(v_item->>'difficulty','medio')); if v_difficulty not in ('facil','medio','dificil','final') then v_difficulty:='medio'; end if;
    v_score:=coalesce((v_item->>'score_enabled')::boolean,true); v_speed:=greatest(0,least(100,coalesce((v_item->>'speed_bonus_pct')::integer,0))); v_tie:=coalesce((v_item->>'is_tiebreaker')::boolean,false); v_notes:=left(coalesce(v_item->>'presenter_notes',''),2000);
    if length(v_prompt)<1 or length(v_prompt)>1000 then raise exception 'Pergunta % possui texto inválido',v_count+1; end if;
    if v_type not in ('choice','numeric') then raise exception 'Pergunta % possui tipo inválido',v_count+1; end if;
    if v_points<1 or v_points>100000 or v_time<5 or v_time>600 then raise exception 'Pergunta % possui pontos/tempo inválidos',v_count+1; end if;
    if v_type='choice' then
      if jsonb_typeof(v_options)<>'array' or jsonb_array_length(v_options)<>4 or v_correct_choice not in ('A','B','C','D') then raise exception 'Pergunta % possui alternativas/gabarito inválidos',v_count+1; end if;
      if (select count(distinct upper(trim(o->>'key'))) from jsonb_array_elements(v_options)o)<>4 or exists(select 1 from jsonb_array_elements(v_options)o where coalesce(trim(o->>'text'),'')='' or length(o->>'text')>500) then raise exception 'Pergunta % possui alternativas inválidas',v_count+1; end if;
      v_correct_number:=null;
    else
      if v_correct_number is null or abs(v_correct_number)>1000000000000000::numeric then raise exception 'Pergunta % possui valor correto inválido',v_count+1; end if; v_options:=null; v_correct_choice:=null;
    end if;
    insert into public.quiz_questions(created_by,prompt,question_type,options,points,time_limit_seconds,category,difficulty,score_enabled,speed_bonus_pct,is_tiebreaker,presenter_notes)
    values(v_uid,v_prompt,v_type,v_options,v_points,v_time,v_category,v_difficulty,v_score,v_speed,v_tie,v_notes) returning id into v_id;
    insert into private.quiz_answer_keys(question_id,correct_choice,correct_number) values(v_id,v_correct_choice,v_correct_number);
    v_count:=v_count+1; v_ids:=v_ids||jsonb_build_array(v_id);
  end loop;
  perform private.audit_event(null,v_uid,'questions_bulk_imported','question',null,jsonb_build_object('count',v_count));
  return jsonb_build_object('imported',v_count,'ids',v_ids);
end $$;
revoke all on function public.admin_import_questions(jsonb) from public;
grant execute on function public.admin_import_questions(jsonb) to authenticated;

-- Recalcula desempate e sequências depois de anulação/reclassificação do último round.
create or replace function private.recalculate_aux_scores(p_room_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_p record; v_r record; v_cur integer; v_best integer; begin
  update public.quiz_participants p set tiebreak_points=coalesce((
    select sum(a.awarded_points)::int from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id
    where a.participant_id=p.id and r.room_id=p_room_id and r.is_tiebreaker_snapshot and not r.annulled
  ),0) where p.room_id=p_room_id;
  for v_p in select id from public.quiz_participants where room_id=p_room_id loop
    v_cur:=0; v_best:=0;
    for v_r in
      select r.round_no,exists(select 1 from public.quiz_answers a where a.round_id=r.id and a.participant_id=v_p.id and a.awarded_points>0) hit
      from public.quiz_rounds r where r.room_id=p_room_id and r.status='closed' and not r.annulled and r.score_enabled_snapshot order by r.round_no
    loop
      if v_r.hit then v_cur:=v_cur+1; v_best:=greatest(v_best,v_cur); else v_cur:=0; end if;
    end loop;
    update public.quiz_participants set current_streak=v_cur,best_streak=v_best where id=v_p.id;
  end loop;
end $$;
revoke all on function private.recalculate_aux_scores(uuid) from public;

create or replace function public.admin_annul_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_round public.quiz_rounds; v_rank jsonb; v_prev jsonb; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id and status='closed' order by round_no desc limit 1 for update; if not found then raise exception 'Nenhum round encerrado'; end if;
  perform set_config('quiz.allow_round_reset','on',true);
  update public.quiz_answers set awarded_points=0 where round_id=v_round.id;
  update public.quiz_rounds set annulled=true,result_text=regexp_replace(coalesce(result_text,''),' • PERGUNTA ANULADA$','')||' • PERGUNTA ANULADA' where id=v_round.id;
  perform private.recalculate_room_totals(p_room_id); perform private.recalculate_aux_scores(p_room_id); v_rank:=private.generate_ranking(p_room_id);
  select coalesce(ranking_snapshot,'[]'::jsonb) into v_prev from public.quiz_rounds where room_id=p_room_id and round_no<v_round.round_no order by round_no desc limit 1;
  update public.quiz_rounds set ranking_snapshot=v_rank,ranking_movers_snapshot=private.ranking_movers(coalesce(v_prev,'[]'::jsonb),v_rank) where id=v_round.id;
  update public.quiz_rooms set final_ranking_snapshot=case when phase='finished' then v_rank else final_ranking_snapshot end where id=p_room_id;
  perform set_config('quiz.allow_round_reset','off',true);
  perform private.audit_event(p_room_id,v_uid,'round_annulled','round',v_round.id,'{}'::jsonb); perform private.notify_room(p_room_id);
  return jsonb_build_object('annulled',true,'round_no',v_round.round_no);
exception when others then perform set_config('quiz.allow_round_reset','off',true); raise; end $$;
revoke all on function public.admin_annul_round(uuid) from public;
grant execute on function public.admin_annul_round(uuid) to authenticated;

create or replace function public.admin_regrade_round(p_room_id uuid,p_correct_choice text default null,p_correct_number numeric default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_round public.quiz_rounds; v_key private.quiz_round_answer_keys; v_rank jsonb; v_prev jsonb; v_dist jsonb; v_winners jsonb; v_limit_ms numeric;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found then raise exception 'Sala inválida'; end if;
  select * into v_round from public.quiz_rounds where room_id=p_room_id and status='closed' order by round_no desc limit 1 for update; if not found then raise exception 'Nenhum round encerrado'; end if;
  if v_round.question_type_snapshot='choice' then
    if upper(coalesce(p_correct_choice,'')) not in ('A','B','C','D') then raise exception 'Alternativa inválida'; end if;
    update private.quiz_round_answer_keys set correct_choice=upper(p_correct_choice),correct_number=null where round_id=v_round.id;
  else
    if p_correct_number is null then raise exception 'Valor obrigatório'; end if;
    update private.quiz_round_answer_keys set correct_choice=null,correct_number=p_correct_number where round_id=v_round.id;
  end if;
  select * into v_key from private.quiz_round_answer_keys where round_id=v_round.id;
  update public.quiz_answers set awarded_points=0 where round_id=v_round.id;
  v_limit_ms:=greatest(1,coalesce(v_round.time_limit_seconds,30)*1000);
  if not v_round.annulled and v_round.score_enabled_snapshot then
    if v_round.question_type_snapshot='choice' then
      update public.quiz_answers a set awarded_points=coalesce(v_round.points_snapshot,0)+case
        when coalesce((v_room.settings->>'speed_bonus_enabled')::boolean,true) and coalesce(v_round.speed_bonus_pct_snapshot,0)>0
        then round(coalesce(v_round.points_snapshot,0)*(v_round.speed_bonus_pct_snapshot/100.0)*greatest(0,1-(a.response_ms/v_limit_ms)))::int else 0 end
      where a.round_id=v_round.id and a.choice_value=v_key.correct_choice;
      select coalesce(jsonb_agg(jsonb_build_object('key',x.k,'count',x.c) order by x.k),'[]'::jsonb) into v_dist from (select choice_value k,count(*) c from public.quiz_answers where round_id=v_round.id group by choice_value)x;
    else
      with ranked as(select id,row_number() over(order by abs(numeric_value-v_key.correct_number),response_ms,submitted_at,participant_id) rn from public.quiz_answers where round_id=v_round.id)
      update public.quiz_answers a set awarded_points=coalesce(v_round.points_snapshot,0) from ranked r where a.id=r.id and r.rn=1;
      select coalesce(jsonb_agg(jsonb_build_object('participant_id',a.participant_id,'value',a.numeric_value,'difference',abs(a.numeric_value-v_key.correct_number),'response_ms',a.response_ms) order by abs(a.numeric_value-v_key.correct_number),a.response_ms),'[]'::jsonb) into v_dist from public.quiz_answers a where a.round_id=v_round.id;
    end if;
  end if;
  perform private.recalculate_aux_scores(p_room_id);
  if coalesce((v_room.settings->>'streak_enabled')::boolean,true) and coalesce((v_room.settings->>'streak_bonus')::int,0)>0 then
    update public.quiz_answers a set awarded_points=a.awarded_points+coalesce((v_room.settings->>'streak_bonus')::int,0)*greatest(p.current_streak-1,0)
    from public.quiz_participants p where a.round_id=v_round.id and a.participant_id=p.id and a.awarded_points>0;
  end if;
  perform private.recalculate_room_totals(p_room_id); perform private.recalculate_aux_scores(p_room_id); v_rank:=private.generate_ranking(p_room_id);
  select coalesce(ranking_snapshot,'[]'::jsonb) into v_prev from public.quiz_rounds where room_id=p_room_id and round_no<v_round.round_no order by round_no desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('participant_id',x.participant_id,'display_name',x.display_name,'response_ms',x.response_ms,'points',x.awarded_points) order by x.awarded_points desc,x.response_ms),'[]'::jsonb) into v_winners
  from (select a.participant_id,p.display_name,a.response_ms,a.awarded_points from public.quiz_answers a join public.quiz_participants p on p.id=a.participant_id where a.round_id=v_round.id and a.awarded_points>0 order by a.awarded_points desc,a.response_ms limit 20)x;
  perform set_config('quiz.allow_round_reset','on',true);
  update public.quiz_rounds set ranking_snapshot=v_rank,previous_ranking_snapshot=coalesce(v_prev,'[]'::jsonb),ranking_movers_snapshot=private.ranking_movers(coalesce(v_prev,'[]'::jsonb),v_rank),winner_snapshot=v_winners,distribution_snapshot=coalesce(v_dist,distribution_snapshot),
    result_text=case when question_type_snapshot='choice' then 'Resposta correta: '||v_key.correct_choice||coalesce((select ' — '||(o->>'text') from jsonb_array_elements(coalesce(options_snapshot,'[]'::jsonb))o where o->>'key'=v_key.correct_choice limit 1),'') else 'Valor correto: '||v_key.correct_number::text end
  where id=v_round.id;
  update public.quiz_rooms set final_ranking_snapshot=case when phase='finished' then v_rank else final_ranking_snapshot end where id=p_room_id;
  perform set_config('quiz.allow_round_reset','off',true);
  perform private.audit_event(p_room_id,v_uid,'round_regraded','round',v_round.id,jsonb_build_object('correct_choice',p_correct_choice,'correct_number',p_correct_number)); perform private.notify_room(p_room_id);
  return jsonb_build_object('regraded',true,'round_no',v_round.round_no);
exception when others then perform set_config('quiz.allow_round_reset','off',true); raise; end $$;
revoke all on function public.admin_regrade_round(uuid,text,numeric) from public;
grant execute on function public.admin_regrade_round(uuid,text,numeric) to authenticated;
