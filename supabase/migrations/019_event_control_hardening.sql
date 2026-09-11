-- QuizRounds v3.31
-- Controle principal por lease + pausa de emergência com preservação do tempo.

alter table public.quiz_rooms add column if not exists paused_remaining_ms integer;
alter table public.quiz_rooms add column if not exists paused_at timestamptz;

create table if not exists public.quiz_admin_control_leases (
  room_id uuid primary key references public.quiz_rooms(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  device_token_hash text not null,
  device_label text not null default 'Painel ADM',
  claimed_at timestamptz not null default clock_timestamp(),
  heartbeat_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null
);
alter table public.quiz_admin_control_leases enable row level security;
revoke all on table public.quiz_admin_control_leases from public, anon, authenticated;

create or replace function public.admin_claim_controller(p_room_id uuid,p_device_token text,p_device_label text default 'Painel ADM',p_force boolean default false)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_lease public.quiz_admin_control_leases; v_hash text; v_now timestamptz:=clock_timestamp();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id and created_by=v_uid;
  if not found then raise exception 'Sala inválida'; end if;
  if length(coalesce(p_device_token,''))<12 then raise exception 'Dispositivo inválido'; end if;
  v_hash:=encode(extensions.digest(p_device_token,'sha256'),'hex');
  delete from public.quiz_admin_control_leases where room_id=p_room_id and expires_at<=v_now;
  select * into v_lease from public.quiz_admin_control_leases where room_id=p_room_id for update;
  if found and v_lease.device_token_hash<>v_hash and not coalesce(p_force,false) then
    return jsonb_build_object('granted',false,'device_label',v_lease.device_label,'expires_at',v_lease.expires_at,'heartbeat_at',v_lease.heartbeat_at);
  end if;
  insert into public.quiz_admin_control_leases(room_id,owner_user_id,device_token_hash,device_label,claimed_at,heartbeat_at,expires_at)
  values(p_room_id,v_uid,v_hash,left(coalesce(nullif(trim(p_device_label),''),'Painel ADM'),80),v_now,v_now,v_now+interval '35 seconds')
  on conflict(room_id) do update set owner_user_id=excluded.owner_user_id,device_token_hash=excluded.device_token_hash,device_label=excluded.device_label,
    claimed_at=case when public.quiz_admin_control_leases.device_token_hash=excluded.device_token_hash then public.quiz_admin_control_leases.claimed_at else excluded.claimed_at end,
    heartbeat_at=excluded.heartbeat_at,expires_at=excluded.expires_at;
  return jsonb_build_object('granted',true,'device_label',left(coalesce(nullif(trim(p_device_label),''),'Painel ADM'),80),'expires_at',v_now+interval '35 seconds');
end $function$;

create or replace function public.admin_controller_heartbeat(p_room_id uuid,p_device_token text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_hash text; v_now timestamptz:=clock_timestamp(); v_rows integer;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  v_hash:=encode(extensions.digest(coalesce(p_device_token,''),'sha256'),'hex');
  update public.quiz_admin_control_leases set heartbeat_at=v_now,expires_at=v_now+interval '35 seconds'
  where room_id=p_room_id and owner_user_id=v_uid and device_token_hash=v_hash and expires_at>v_now-interval '5 seconds';
  get diagnostics v_rows=row_count;
  return jsonb_build_object('granted',v_rows=1,'expires_at',case when v_rows=1 then v_now+interval '35 seconds' else null end);
end $function$;

create or replace function public.admin_release_controller(p_room_id uuid,p_device_token text)
returns boolean language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_hash text; v_rows integer;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  v_hash:=encode(extensions.digest(coalesce(p_device_token,''),'sha256'),'hex');
  delete from public.quiz_admin_control_leases where room_id=p_room_id and owner_user_id=v_uid and device_token_hash=v_hash;
  get diagnostics v_rows=row_count;
  return v_rows>0;
end $function$;

create or replace function public.admin_controller_status(p_room_id uuid,p_device_token text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_hash text; v_lease public.quiz_admin_control_leases; v_now timestamptz:=clock_timestamp();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  v_hash:=encode(extensions.digest(coalesce(p_device_token,''),'sha256'),'hex');
  delete from public.quiz_admin_control_leases where room_id=p_room_id and expires_at<=v_now;
  select * into v_lease from public.quiz_admin_control_leases where room_id=p_room_id;
  if not found then return jsonb_build_object('active',false,'mine',false); end if;
  return jsonb_build_object('active',true,'mine',v_lease.owner_user_id=v_uid and v_lease.device_token_hash=v_hash,'device_label',v_lease.device_label,'expires_at',v_lease.expires_at,'heartbeat_at',v_lease.heartbeat_at);
end $function$;

create or replace function public.admin_pause_quiz(p_room_id uuid,p_pause boolean)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_round public.quiz_rounds; v_now timestamptz:=clock_timestamp(); v_ms integer:=0; v_restore text;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update; if not found then raise exception 'Sala inválida'; end if;
  if p_pause then
    if v_room.phase in ('finished','paused','lobby') then return to_jsonb(v_room); end if;
    if v_room.phase='question_open' then
      select * into v_round from public.quiz_rounds where room_id=p_room_id and status='open' order by round_no desc limit 1 for update;
      if not found then raise exception 'Round aberto não encontrado'; end if;
      v_ms:=greatest(0,least(3600000,(extract(epoch from (coalesce(v_round.closes_at,v_now)-v_now))*1000)::integer));
    elsif v_room.phase='preparing' then
      v_ms:=greatest(0,least(60000,(extract(epoch from (coalesce(v_room.prepared_until,v_now)-v_now))*1000)::integer));
    end if;
    update public.quiz_rooms set paused_phase=v_room.phase,phase='paused',paused_remaining_ms=v_ms,paused_at=v_now where id=p_room_id returning * into v_room;
  else
    if v_room.phase<>'paused' then return to_jsonb(v_room); end if;
    v_restore:=coalesce(nullif(v_room.paused_phase,''),'result');
    if v_restore='question_open' then
      select * into v_round from public.quiz_rounds where room_id=p_room_id and status='open' order by round_no desc limit 1 for update;
      if found then update public.quiz_rounds set closes_at=v_now+(greatest(0,coalesce(v_room.paused_remaining_ms,0))::text||' milliseconds')::interval where id=v_round.id; end if;
    elsif v_restore='preparing' then
      update public.quiz_rooms set prepared_until=v_now+(greatest(0,coalesce(v_room.paused_remaining_ms,0))::text||' milliseconds')::interval where id=p_room_id;
    end if;
    update public.quiz_rooms set phase=v_restore,paused_phase=null,paused_remaining_ms=null,paused_at=null where id=p_room_id returning * into v_room;
  end if;
  perform private.audit_event(p_room_id,v_uid,case when p_pause then 'quiz_emergency_paused' else 'quiz_resumed' end,'room',p_room_id,jsonb_build_object('restore_phase',coalesce(v_room.paused_phase,v_restore),'remaining_ms',v_ms));
  perform private.notify_room(p_room_id);
  return to_jsonb(v_room);
end $function$;

create or replace function public.admin_get_room_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_round public.quiz_rounds; v_item public.quiz_room_queue; v_key private.quiz_round_answer_keys; v_round_json jsonb; v_rank jsonb; v_now timestamptz:=clock_timestamp(); v_participants int:=0;v_active int:=0;v_ready int:=0;v_answers int:=0;v_used int:=0;v_queued int:=0; begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if; select * into v_room from public.quiz_rooms where id=p_room_id; if not found then raise exception 'Sala não encontrada'; end if;
  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at) values(v_uid,p_room_id,'admin',v_now) on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;
  select * into v_round from public.quiz_rounds where room_id=p_room_id order by round_no desc limit 1;
  if found then select * into v_key from private.quiz_round_answer_keys where round_id=v_round.id; v_round_json:=jsonb_build_object('id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,'closed_at',v_round.closed_at,'result_text',v_round.result_text,'time_limit_seconds',v_round.time_limit_seconds,'closes_at',v_round.closes_at,'accepting_responses',(v_room.phase='question_open' and v_round.status='open' and v_now<=v_round.closes_at),'prompt',v_round.prompt_snapshot,'question_type',v_round.question_type_snapshot,'options',coalesce(v_round.options_snapshot,'[]'::jsonb),'points',v_round.points_snapshot,'category',v_round.category_snapshot,'difficulty',v_round.difficulty_snapshot,'score_enabled',v_round.score_enabled_snapshot,'speed_bonus_pct',v_round.speed_bonus_pct_snapshot,'is_tiebreaker',v_round.is_tiebreaker_snapshot,'presenter_notes',coalesce(v_round.presenter_notes_snapshot,''),'annulled',v_round.annulled,'answer_count_snapshot',v_round.answer_count_snapshot,'winner_snapshot',v_round.winner_snapshot,'distribution',v_round.distribution_snapshot,'movers',v_round.ranking_movers_snapshot,'correct_choice',v_key.correct_choice,'correct_number',v_key.correct_number); end if;
  if v_room.prepared_queue_id is not null then select * into v_item from public.quiz_room_queue where id=v_room.prepared_queue_id; end if;
  v_rank:=private.generate_ranking(p_room_id); select count(*) into v_participants from public.quiz_participants where room_id=p_room_id and not kicked; select count(*) into v_active from public.quiz_participants where room_id=p_room_id and not kicked and last_seen_at>=v_now-interval '90 seconds'; select count(*) into v_ready from public.quiz_participants where room_id=p_room_id and not kicked and ready; select count(*) into v_used from public.quiz_rounds where room_id=p_room_id; select count(*) into v_queued from public.quiz_room_queue where room_id=p_room_id and status='queued'; if v_round.id is not null and v_round.status='open' then select count(*) into v_answers from public.quiz_answers where round_id=v_round.id; else v_answers:=coalesce(v_round.answer_count_snapshot,0); end if;
  return jsonb_build_object('room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'phase',v_room.phase,'paused_phase',v_room.paused_phase,'paused_remaining_ms',v_room.paused_remaining_ms,'paused_at',v_room.paused_at,'state_version',v_room.state_version,'generation',v_room.game_generation,'started_at',v_room.started_at,'finished_at',v_room.finished_at,'randomize_queue',v_room.randomize_queue,'settings',v_room.settings,'theme',v_room.theme_preset,'logo_url',v_room.logo_url,'prepared_until',v_room.prepared_until,'reveal_stage',v_room.reveal_stage,'is_rehearsal',v_room.is_rehearsal),'round',v_round_json,'prepared',case when v_item.id is null then null else jsonb_build_object('queue_id',v_item.id,'prompt',v_item.prompt_snapshot,'question_type',v_item.question_type_snapshot,'options',v_item.options_snapshot,'points',v_item.points_snapshot,'category',v_item.category_snapshot,'difficulty',v_item.difficulty_snapshot,'presenter_notes',v_item.presenter_notes_snapshot) end,'ranking',v_rank,'participant_count',v_participants,'active_count',v_active,'ready_count',v_ready,'answer_count',v_answers,'used_rounds',v_used,'queued_count',v_queued,'server_now',v_now);
end
$function$;

revoke all on function public.admin_claim_controller(uuid,text,text,boolean) from public,anon;
revoke all on function public.admin_controller_heartbeat(uuid,text) from public,anon;
revoke all on function public.admin_release_controller(uuid,text) from public,anon;
revoke all on function public.admin_controller_status(uuid,text) from public,anon;
revoke all on function public.admin_pause_quiz(uuid,boolean) from public,anon;
revoke all on function public.admin_get_room_state(uuid) from public,anon;
grant execute on function public.admin_claim_controller(uuid,text,text,boolean) to authenticated;
grant execute on function public.admin_controller_heartbeat(uuid,text) to authenticated;
grant execute on function public.admin_release_controller(uuid,text) to authenticated;
grant execute on function public.admin_controller_status(uuid,text) to authenticated;
grant execute on function public.admin_pause_quiz(uuid,boolean) to authenticated;
grant execute on function public.admin_get_room_state(uuid) to authenticated;
