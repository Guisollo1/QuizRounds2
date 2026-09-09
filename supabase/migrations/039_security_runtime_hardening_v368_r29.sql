-- QuizRounds v3.68 / r29
-- Hardening de produção: pareamento seguro do telão, build/schema handshake,
-- controlador autoritativo no backend, elegibilidade por round e ciclo de vida de logos.

-- ---------------------------------------------------------------------------
-- 1) Metadados de backend para bloquear frontend incompatível.
-- ---------------------------------------------------------------------------
create or replace function public.get_quiz_backend_meta()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select jsonb_build_object(
    'schema_version',39,
    'release','3.68-r29',
    'min_frontend_build','3.68-r29',
    'features',jsonb_build_array(
      'secure_display_pairing','controller_backend_guard','round_eligibility_snapshot',
      'display_state_privacy','logo_reference_guard','build_handshake'
    ),
    'server_now',clock_timestamp()
  );
$$;
revoke all on function public.get_quiz_backend_meta() from public;
grant execute on function public.get_quiz_backend_meta() to anon,authenticated;

-- ---------------------------------------------------------------------------
-- 2) Telão: pareamento de uso único. Saber o PIN da sala não concede papel display.
-- ---------------------------------------------------------------------------
create table if not exists public.quiz_display_pairings (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.quiz_rooms(id) on delete cascade,
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp()
);

create table if not exists public.quiz_display_authorizations (
  room_id uuid not null references public.quiz_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  paired_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  primary key(room_id,user_id)
);

alter table public.quiz_display_pairings enable row level security;
alter table public.quiz_display_authorizations enable row level security;
revoke all on public.quiz_display_pairings,public.quiz_display_authorizations from public,anon,authenticated;
create index if not exists quiz_display_pairings_room_exp_idx on public.quiz_display_pairings(room_id,expires_at desc);
create index if not exists quiz_display_auth_room_exp_idx on public.quiz_display_authorizations(room_id,expires_at desc);

create or replace function private.can_view_display(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(
    (
      private.is_admin(auth.uid())
      and exists(select 1 from public.quiz_rooms r where r.id=p_room_id and r.created_by=auth.uid())
    )
    or exists(
      select 1 from public.quiz_display_authorizations a
      where a.room_id=p_room_id and a.user_id=auth.uid() and a.expires_at>clock_timestamp()
    ),false
  );
$$;
revoke all on function private.can_view_display(uuid) from public,anon;
grant execute on function private.can_view_display(uuid) to authenticated;

create or replace function public.admin_create_display_pairing(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_token text;
  v_hash text;
  v_expires timestamptz:=clock_timestamp()+interval '5 minutes';
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id and created_by=v_uid;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.status='finished' or v_room.phase='finished' then raise exception 'A sala já foi encerrada'; end if;

  delete from public.quiz_display_pairings
   where admin_user_id=v_uid and (consumed_at is not null or expires_at<clock_timestamp());

  v_token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
  v_hash:=encode(extensions.digest(v_token,'sha256'),'hex');
  insert into public.quiz_display_pairings(room_id,admin_user_id,token_hash,expires_at)
  values(p_room_id,v_uid,v_hash,v_expires);

  perform private.audit_event(p_room_id,v_uid,'display_pairing_created','room',p_room_id,jsonb_build_object('expires_at',v_expires));
  return jsonb_build_object('pair_token',v_token,'expires_at',v_expires,'room_id',v_room.id,'room_code',v_room.code);
end;
$$;
revoke all on function public.admin_create_display_pairing(uuid) from public,anon;
grant execute on function public.admin_create_display_pairing(uuid) to authenticated;

-- Desativa o caminho inseguro legado (PIN sozinho).
create or replace function public.authorize_quiz_display(p_code text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'Pareamento do telão obrigatório. Abra o telão pelo painel ADM.';
end;
$$;
revoke all on function public.authorize_quiz_display(text) from public,anon;
grant execute on function public.authorize_quiz_display(text) to authenticated;

create or replace function public.authorize_quiz_display(p_code text,p_pair_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_pair public.quiz_display_pairings;
  v_hash text;
  v_now timestamptz:=clock_timestamp();
  v_auth_expires timestamptz:=v_now+interval '24 hours';
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  if length(coalesce(p_pair_token,''))<32 or length(p_pair_token)>256 then raise exception 'Pareamento inválido'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.status='finished' or v_room.phase='finished' then raise exception 'Sala encerrada'; end if;

  v_hash:=encode(extensions.digest(trim(p_pair_token),'sha256'),'hex');
  select * into v_pair
    from public.quiz_display_pairings
   where room_id=v_room.id and token_hash=v_hash and consumed_at is null and expires_at>=v_now
   order by created_at desc limit 1 for update;
  if not found then raise exception 'Pareamento do telão expirado, inválido ou já utilizado'; end if;

  update public.quiz_display_pairings set consumed_at=v_now,consumed_by=v_uid where id=v_pair.id;
  insert into public.quiz_display_authorizations(room_id,user_id,paired_at,expires_at)
  values(v_room.id,v_uid,v_now,v_auth_expires)
  on conflict(room_id,user_id) do update set paired_at=excluded.paired_at,expires_at=excluded.expires_at;
  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at)
  values(v_uid,v_room.id,'display',v_now)
  on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;

  perform private.audit_event(v_room.id,v_uid,'display_paired','display',v_uid,jsonb_build_object('expires_at',v_auth_expires));
  return jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'authorized_until',v_auth_expires);
end;
$$;
revoke all on function public.authorize_quiz_display(text,text) from public,anon;
grant execute on function public.authorize_quiz_display(text,text) to authenticated;

-- Remove autorizações display herdadas do modelo antigo; a r29 repareia automaticamente.
delete from public.quiz_realtime_memberships where role='display';

-- ---------------------------------------------------------------------------
-- 3) Privacidade: participante não pode consultar roster/estado do telão.
--    Mantém implementações anteriores apenas como detalhes internos.
-- ---------------------------------------------------------------------------
alter function public.get_public_avatar_roster(text) rename to get_public_avatar_roster_r28_impl;
revoke all on function public.get_public_avatar_roster_r28_impl(text) from public,anon,authenticated;

create or replace function public.get_public_avatar_roster(p_code text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_room_id uuid;
begin
  select id into v_room_id from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if v_room_id is null then raise exception 'Sala não encontrada'; end if;
  if not private.can_view_display(v_room_id) then raise exception 'Tela não autorizada'; end if;
  return public.get_public_avatar_roster_r28_impl(p_code);
end;
$$;
revoke all on function public.get_public_avatar_roster(text) from public,anon;
grant execute on function public.get_public_avatar_roster(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Snapshot de elegibilidade por round para auto-close e taxa de resposta.
-- ---------------------------------------------------------------------------
create table if not exists public.quiz_round_eligibility (
  round_id uuid not null references public.quiz_rounds(id) on delete cascade,
  participant_id uuid not null references public.quiz_participants(id) on delete cascade,
  captured_at timestamptz not null default clock_timestamp(),
  primary key(round_id,participant_id)
);
alter table public.quiz_round_eligibility enable row level security;
revoke all on public.quiz_round_eligibility from public,anon,authenticated;
create index if not exists quiz_round_eligibility_round_idx on public.quiz_round_eligibility(round_id);

create or replace function private.capture_round_eligibility(p_round_id uuid)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_room_id uuid; v_count integer;
begin
  select room_id into v_room_id from public.quiz_rounds where id=p_round_id;
  if v_room_id is null then return 0; end if;
  insert into public.quiz_round_eligibility(round_id,participant_id)
  select p_round_id,p.id from public.quiz_participants p
   where p.room_id=v_room_id and not p.kicked and p.last_seen_at>=clock_timestamp()-interval '90 seconds'
  on conflict do nothing;
  select count(*) into v_count from public.quiz_round_eligibility where round_id=p_round_id;
  return v_count;
end;
$$;
revoke all on function private.capture_round_eligibility(uuid) from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 5) Controlador autoritativo: vincula lease/remoto à sessão autenticada.
-- ---------------------------------------------------------------------------
alter table public.quiz_admin_control_leases add column if not exists owner_session_id text;
alter table public.quiz_admin_remote_devices add column if not exists auth_session_id text;

create or replace function private.current_auth_session_id()
returns text
language sql
stable
security definer
set search_path=''
as $$ select nullif(coalesce(auth.jwt()->>'session_id',''),''); $$;
revoke all on function private.current_auth_session_id() from public,anon,authenticated;

create or replace function private.require_live_control(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_sid text:=private.current_auth_session_id(); v_now timestamptz:=clock_timestamp();
begin
  if current_setting('quiz.controller_internal',true)='on' then return; end if;
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if v_sid is null then raise exception 'Sessão administrativa sem identificador de controle'; end if;

  if exists(
    select 1 from public.quiz_admin_control_leases l
    where l.room_id=p_room_id and l.owner_user_id=v_uid and l.owner_session_id=v_sid and l.expires_at>v_now
  ) then return; end if;

  if exists(
    select 1 from public.quiz_admin_remote_devices d
    where d.admin_user_id=v_uid and d.auth_session_id=v_sid and d.active=true
      and d.paired_from_room_id=p_room_id and d.revoked_at is null
  ) then return; end if;

  raise exception 'Este dispositivo não é o controlador ativo da sala';
end;
$$;
revoke all on function private.require_live_control(uuid) from public,anon,authenticated;

create or replace function public.admin_claim_controller(p_room_id uuid,p_device_token text,p_device_label text default 'Painel ADM',p_force boolean default false)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_lease public.quiz_admin_control_leases; v_hash text; v_now timestamptz:=clock_timestamp(); v_sid text:=private.current_auth_session_id();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if v_sid is null then raise exception 'Sessão administrativa inválida'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id and created_by=v_uid;
  if not found then raise exception 'Sala inválida'; end if;
  if length(coalesce(p_device_token,''))<12 then raise exception 'Dispositivo inválido'; end if;
  v_hash:=encode(extensions.digest(p_device_token,'sha256'),'hex');
  delete from public.quiz_admin_control_leases where room_id=p_room_id and expires_at<=v_now;
  select * into v_lease from public.quiz_admin_control_leases where room_id=p_room_id for update;
  if found and (v_lease.device_token_hash<>v_hash or coalesce(v_lease.owner_session_id,'')<>v_sid) and not coalesce(p_force,false) then
    return jsonb_build_object('granted',false,'device_label',v_lease.device_label,'expires_at',v_lease.expires_at,'heartbeat_at',v_lease.heartbeat_at);
  end if;
  insert into public.quiz_admin_control_leases(room_id,owner_user_id,device_token_hash,device_label,claimed_at,heartbeat_at,expires_at,owner_session_id)
  values(p_room_id,v_uid,v_hash,left(coalesce(nullif(trim(p_device_label),''),'Painel ADM'),80),v_now,v_now,v_now+interval '35 seconds',v_sid)
  on conflict(room_id) do update set owner_user_id=excluded.owner_user_id,device_token_hash=excluded.device_token_hash,device_label=excluded.device_label,
    claimed_at=case when public.quiz_admin_control_leases.device_token_hash=excluded.device_token_hash and public.quiz_admin_control_leases.owner_session_id=excluded.owner_session_id then public.quiz_admin_control_leases.claimed_at else excluded.claimed_at end,
    heartbeat_at=excluded.heartbeat_at,expires_at=excluded.expires_at,owner_session_id=excluded.owner_session_id;
  return jsonb_build_object('granted',true,'device_label',left(coalesce(nullif(trim(p_device_label),''),'Painel ADM'),80),'expires_at',v_now+interval '35 seconds');
end;
$$;

create or replace function public.admin_controller_heartbeat(p_room_id uuid,p_device_token text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_hash text; v_now timestamptz:=clock_timestamp(); v_rows integer; v_sid text:=private.current_auth_session_id();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if v_sid is null then return jsonb_build_object('granted',false); end if;
  v_hash:=encode(extensions.digest(coalesce(p_device_token,''),'sha256'),'hex');
  update public.quiz_admin_control_leases set heartbeat_at=v_now,expires_at=v_now+interval '35 seconds'
  where room_id=p_room_id and owner_user_id=v_uid and device_token_hash=v_hash and owner_session_id=v_sid and expires_at>v_now-interval '5 seconds';
  get diagnostics v_rows=row_count;
  return jsonb_build_object('granted',v_rows=1,'expires_at',case when v_rows=1 then v_now+interval '35 seconds' else null end);
end;
$$;

create or replace function public.admin_controller_status(p_room_id uuid,p_device_token text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_hash text; v_lease public.quiz_admin_control_leases; v_now timestamptz:=clock_timestamp(); v_sid text:=private.current_auth_session_id();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  v_hash:=encode(extensions.digest(coalesce(p_device_token,''),'sha256'),'hex');
  delete from public.quiz_admin_control_leases where room_id=p_room_id and expires_at<=v_now;
  select * into v_lease from public.quiz_admin_control_leases where room_id=p_room_id;
  if not found then return jsonb_build_object('active',false,'mine',false); end if;
  return jsonb_build_object('active',true,'mine',v_lease.owner_user_id=v_uid and v_lease.device_token_hash=v_hash and v_lease.owner_session_id=v_sid,'device_label',v_lease.device_label,'expires_at',v_lease.expires_at,'heartbeat_at',v_lease.heartbeat_at);
end;
$$;

-- O status remoto vincula a autorização persistente à sessão atual do aparelho.
create or replace function public.admin_remote_device_status(p_device_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid(); v_device public.quiz_admin_remote_devices; v_room public.quiz_rooms;
  v_device_hash text; v_sid text:=private.current_auth_session_id();
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if v_sid is null then return jsonb_build_object('authorized',false); end if;
  if length(coalesce(p_device_token,''))<20 or length(p_device_token)>200 then return jsonb_build_object('authorized',false); end if;
  v_device_hash:=encode(extensions.digest(p_device_token,'sha256'),'hex');
  select * into v_device from public.quiz_admin_remote_devices
   where admin_user_id=v_uid and device_hash=v_device_hash and active=true order by paired_at desc limit 1;
  if not found then return jsonb_build_object('authorized',false); end if;
  if v_device.paired_from_room_id is not null then
    select * into v_room from public.quiz_rooms where id=v_device.paired_from_room_id and created_by=v_uid and status<>'finished' and phase<>'finished';
  end if;
  if v_room.id is null then
    select * into v_room from public.quiz_rooms where created_by=v_uid and status<>'finished' and phase<>'finished' order by created_at desc limit 1;
  end if;
  update public.quiz_admin_remote_devices set last_seen_at=clock_timestamp(),auth_session_id=v_sid,
    paired_from_room_id=case when v_room.id is null then paired_from_room_id else v_room.id end where id=v_device.id;
  return jsonb_build_object('authorized',true,'device_id',v_device.id,'device_label',v_device.device_label,'paired_at',v_device.paired_at,
    'room',case when v_room.id is null then null else jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'phase',v_room.phase,'status',v_room.status,'planned_rounds',v_room.planned_rounds) end);
end;
$$;
revoke all on function public.admin_remote_device_status(text) from public,anon;
grant execute on function public.admin_remote_device_status(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Encapsula comandos críticos. Implementações r28 ficam inacessíveis ao cliente.
-- ---------------------------------------------------------------------------
alter function public.admin_update_planned_rounds(uuid,integer) rename to admin_update_planned_rounds_r28_impl;
alter function public.admin_queue_question(uuid,uuid) rename to admin_queue_question_r28_impl;
alter function public.admin_remove_queue_item(uuid,uuid) rename to admin_remove_queue_item_r28_impl;
alter function public.admin_move_queue_item(uuid,uuid,integer) rename to admin_move_queue_item_r28_impl;
alter function public.admin_start_quiz(uuid) rename to admin_start_quiz_r28_impl;
alter function public.admin_prepare_next_round(uuid) rename to admin_prepare_next_round_r28_impl;
alter function public.admin_open_prepared_round(uuid) rename to admin_open_prepared_round_r28_impl;
alter function public.admin_close_and_score_round(uuid) rename to admin_close_and_score_round_r28_impl;
alter function public.admin_pause_quiz(uuid,boolean) rename to admin_pause_quiz_r28_impl;
alter function public.admin_extend_round(uuid,integer) rename to admin_extend_round_r28_impl;
alter function public.admin_annul_round(uuid) rename to admin_annul_round_r28_impl;
alter function public.admin_regrade_round(uuid,text,numeric) rename to admin_regrade_round_r28_impl;
alter function public.admin_kick_participant(uuid,uuid,boolean) rename to admin_kick_participant_r28_impl;
alter function public.admin_restart_quiz(uuid) rename to admin_restart_quiz_r28_impl;
alter function public.admin_shuffle_queue(uuid) rename to admin_shuffle_queue_r28_impl;
alter function public.admin_set_randomize_queue(uuid,boolean) rename to admin_set_randomize_queue_r28_impl;
alter function public.admin_update_room_settings(uuid,jsonb) rename to admin_update_room_settings_r28_impl;
alter function public.admin_set_reveal_stage(uuid,text) rename to admin_set_reveal_stage_r28_impl;
alter function public.admin_set_final_show_stage(uuid,text) rename to admin_set_final_show_stage_r28_impl;
alter function public.admin_create_room_v4(text,integer) rename to admin_create_room_v4_r28_impl;
alter function public.admin_create_from_template(uuid,text) rename to admin_create_from_template_r28_impl;
alter function public.admin_duplicate_room(uuid,text) rename to admin_duplicate_room_r28_impl;
alter function public.admin_create_remote_pairing(uuid) rename to admin_create_remote_pairing_r28_impl;

revoke all on function public.admin_update_planned_rounds_r28_impl(uuid,integer) from public,anon,authenticated;
revoke all on function public.admin_queue_question_r28_impl(uuid,uuid) from public,anon,authenticated;
revoke all on function public.admin_remove_queue_item_r28_impl(uuid,uuid) from public,anon,authenticated;
revoke all on function public.admin_move_queue_item_r28_impl(uuid,uuid,integer) from public,anon,authenticated;
revoke all on function public.admin_start_quiz_r28_impl(uuid) from public,anon,authenticated;
revoke all on function public.admin_prepare_next_round_r28_impl(uuid) from public,anon,authenticated;
revoke all on function public.admin_open_prepared_round_r28_impl(uuid) from public,anon,authenticated;
revoke all on function public.admin_close_and_score_round_r28_impl(uuid) from public,anon,authenticated;
revoke all on function public.admin_pause_quiz_r28_impl(uuid,boolean) from public,anon,authenticated;
revoke all on function public.admin_extend_round_r28_impl(uuid,integer) from public,anon,authenticated;
revoke all on function public.admin_annul_round_r28_impl(uuid) from public,anon,authenticated;
revoke all on function public.admin_regrade_round_r28_impl(uuid,text,numeric) from public,anon,authenticated;
revoke all on function public.admin_kick_participant_r28_impl(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.admin_restart_quiz_r28_impl(uuid) from public,anon,authenticated;
revoke all on function public.admin_shuffle_queue_r28_impl(uuid) from public,anon,authenticated;
revoke all on function public.admin_set_randomize_queue_r28_impl(uuid,boolean) from public,anon,authenticated;
revoke all on function public.admin_update_room_settings_r28_impl(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.admin_set_reveal_stage_r28_impl(uuid,text) from public,anon,authenticated;
revoke all on function public.admin_set_final_show_stage_r28_impl(uuid,text) from public,anon,authenticated;
revoke all on function public.admin_create_room_v4_r28_impl(text,integer) from public,anon,authenticated;
revoke all on function public.admin_create_from_template_r28_impl(uuid,text) from public,anon,authenticated;
revoke all on function public.admin_duplicate_room_r28_impl(uuid,text) from public,anon,authenticated;
revoke all on function public.admin_create_remote_pairing_r28_impl(uuid) from public,anon,authenticated;

create or replace function public.admin_update_planned_rounds(p_room_id uuid,p_planned_rounds integer) returns integer language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_update_planned_rounds_r28_impl(p_room_id,p_planned_rounds); end $$;
create or replace function public.admin_queue_question(p_room_id uuid,p_question_id uuid) returns uuid language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_queue_question_r28_impl(p_room_id,p_question_id); end $$;
create or replace function public.admin_remove_queue_item(p_room_id uuid,p_queue_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); perform public.admin_remove_queue_item_r28_impl(p_room_id,p_queue_id); end $$;
create or replace function public.admin_move_queue_item(p_room_id uuid,p_queue_id uuid,p_direction integer) returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); perform public.admin_move_queue_item_r28_impl(p_room_id,p_queue_id,p_direction); end $$;
create or replace function public.admin_prepare_next_round(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_prepare_next_round_r28_impl(p_room_id); end $$;
create or replace function public.admin_open_prepared_round(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ declare v jsonb; v_round uuid; begin perform private.require_live_control(p_room_id); v:=public.admin_open_prepared_round_r28_impl(p_room_id); begin v_round:=(v->'round'->>'id')::uuid; exception when others then v_round:=null; end; if v_round is not null then perform private.capture_round_eligibility(v_round); end if; return v; end $$;
create or replace function public.admin_close_and_score_round(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_close_and_score_round_r28_impl(p_room_id); end $$;
create or replace function public.admin_pause_quiz(p_room_id uuid,p_pause boolean) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_pause_quiz_r28_impl(p_room_id,p_pause); end $$;
create or replace function public.admin_extend_round(p_room_id uuid,p_seconds integer) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_extend_round_r28_impl(p_room_id,p_seconds); end $$;
create or replace function public.admin_annul_round(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_annul_round_r28_impl(p_room_id); end $$;
create or replace function public.admin_regrade_round(p_room_id uuid,p_correct_choice text default null,p_correct_number numeric default null) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_regrade_round_r28_impl(p_room_id,p_correct_choice,p_correct_number); end $$;
create or replace function public.admin_kick_participant(p_room_id uuid,p_participant_id uuid,p_block boolean default true) returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); perform public.admin_kick_participant_r28_impl(p_room_id,p_participant_id,p_block); end $$;
create or replace function public.admin_restart_quiz(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_restart_quiz_r28_impl(p_room_id); end $$;
create or replace function public.admin_shuffle_queue(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_shuffle_queue_r28_impl(p_room_id); end $$;
create or replace function public.admin_set_randomize_queue(p_room_id uuid,p_enabled boolean) returns boolean language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_set_randomize_queue_r28_impl(p_room_id,p_enabled); end $$;
create or replace function public.admin_update_room_settings(p_room_id uuid,p_patch jsonb) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_update_room_settings_r28_impl(p_room_id,p_patch); end $$;
create or replace function public.admin_set_reveal_stage(p_room_id uuid,p_stage text) returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); perform public.admin_set_reveal_stage_r28_impl(p_room_id,p_stage); end $$;
create or replace function public.admin_set_final_show_stage(p_room_id uuid,p_stage text) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_set_final_show_stage_r28_impl(p_room_id,p_stage); end $$;
create or replace function public.admin_create_remote_pairing(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_create_remote_pairing_r28_impl(p_room_id); end $$;

-- Start chama prepare internamente; libera apenas a chamada aninhada, não o cliente.
create or replace function public.admin_start_quiz(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ declare v jsonb; begin perform private.require_live_control(p_room_id); perform set_config('quiz.controller_internal','on',true); begin v:=public.admin_start_quiz_r28_impl(p_room_id); exception when others then perform set_config('quiz.controller_internal','off',true); raise; end; perform set_config('quiz.controller_internal','off',true); return v; end $$;

-- Criação/substituição de sala exige controle da sala ativa existente, se houver.
create or replace function private.require_active_room_control_if_any()
returns void language plpgsql security definer set search_path='' as $$ declare v_room uuid; begin
  select id into v_room from public.quiz_rooms where created_by=auth.uid() and status<>'finished' and phase<>'finished' order by created_at desc limit 1;
  if v_room is not null then perform private.require_live_control(v_room); end if;
end $$;
revoke all on function private.require_active_room_control_if_any() from public,anon,authenticated;

create or replace function public.admin_create_room_v4(p_title text,p_planned_rounds integer) returns jsonb language plpgsql security definer set search_path='' as $$ declare v jsonb; begin perform private.require_active_room_control_if_any(); perform set_config('quiz.controller_internal','on',true); begin v:=public.admin_create_room_v4_r28_impl(p_title,p_planned_rounds); exception when others then perform set_config('quiz.controller_internal','off',true); raise; end; perform set_config('quiz.controller_internal','off',true); return v; end $$;
create or replace function public.admin_create_from_template(p_template_id uuid,p_title text default null) returns jsonb language plpgsql security definer set search_path='' as $$ declare v jsonb; begin perform private.require_active_room_control_if_any(); perform set_config('quiz.controller_internal','on',true); begin v:=public.admin_create_from_template_r28_impl(p_template_id,p_title); exception when others then perform set_config('quiz.controller_internal','off',true); raise; end; perform set_config('quiz.controller_internal','off',true); return v; end $$;
create or replace function public.admin_duplicate_room(p_room_id uuid,p_title text default null) returns jsonb language plpgsql security definer set search_path='' as $$ declare v jsonb; begin perform private.require_live_control(p_room_id); perform set_config('quiz.controller_internal','on',true); begin v:=public.admin_duplicate_room_r28_impl(p_room_id,p_title); exception when others then perform set_config('quiz.controller_internal','off',true); raise; end; perform set_config('quiz.controller_internal','off',true); return v; end $$;

-- Mutações do banco de perguntas/modelos também respeitam o controlador quando existe sala ativa.
alter function public.admin_create_question_v2(text,text,jsonb,text,numeric,integer,integer) rename to admin_create_question_v2_r28_impl;
alter function public.admin_update_question_v3(uuid,text,text,jsonb,text,numeric,integer,integer,text,text,boolean,integer,boolean,text) rename to admin_update_question_v3_r28_impl;
alter function public.admin_import_questions_v2(jsonb,text) rename to admin_import_questions_v2_r28_impl;
alter function public.admin_set_question_archived(uuid,boolean) rename to admin_set_question_archived_r28_impl;
alter function public.admin_update_question_metadata(uuid,text,text,boolean,integer,boolean,text) rename to admin_update_question_metadata_r28_impl;
alter function public.admin_duplicate_question(uuid) rename to admin_duplicate_question_r28_impl;
alter function public.admin_save_question_collection(text,jsonb) rename to admin_save_question_collection_r28_impl;
alter function public.admin_delete_question_collection(uuid) rename to admin_delete_question_collection_r28_impl;
alter function public.admin_save_template(uuid,text) rename to admin_save_template_r28_impl;
alter function public.admin_revoke_remote_devices() rename to admin_revoke_remote_devices_r28_impl;

revoke all on function public.admin_create_question_v2_r28_impl(text,text,jsonb,text,numeric,integer,integer),public.admin_update_question_v3_r28_impl(uuid,text,text,jsonb,text,numeric,integer,integer,text,text,boolean,integer,boolean,text),public.admin_import_questions_v2_r28_impl(jsonb,text),public.admin_set_question_archived_r28_impl(uuid,boolean),public.admin_update_question_metadata_r28_impl(uuid,text,text,boolean,integer,boolean,text),public.admin_duplicate_question_r28_impl(uuid),public.admin_save_question_collection_r28_impl(text,jsonb),public.admin_delete_question_collection_r28_impl(uuid),public.admin_save_template_r28_impl(uuid,text),public.admin_revoke_remote_devices_r28_impl() from public,anon,authenticated;

create or replace function public.admin_create_question_v2(p_prompt text,p_type text,p_options jsonb,p_correct_choice text,p_correct_number numeric,p_points integer,p_time_limit integer) returns uuid language plpgsql security definer set search_path='' as $$ begin perform private.require_active_room_control_if_any(); return public.admin_create_question_v2_r28_impl(p_prompt,p_type,p_options,p_correct_choice,p_correct_number,p_points,p_time_limit); end $$;
create or replace function public.admin_update_question_v3(p_question_id uuid,p_prompt text,p_type text,p_options jsonb,p_correct_choice text,p_correct_number numeric,p_points integer,p_time_limit integer,p_category text,p_difficulty text,p_score_enabled boolean,p_speed_bonus_pct integer,p_is_tiebreaker boolean,p_presenter_notes text) returns uuid language plpgsql security definer set search_path='' as $$ begin perform private.require_active_room_control_if_any(); return public.admin_update_question_v3_r28_impl(p_question_id,p_prompt,p_type,p_options,p_correct_choice,p_correct_number,p_points,p_time_limit,p_category,p_difficulty,p_score_enabled,p_speed_bonus_pct,p_is_tiebreaker,p_presenter_notes); end $$;
create or replace function public.admin_import_questions_v2(p_questions jsonb,p_mode text default 'append') returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_active_room_control_if_any(); return public.admin_import_questions_v2_r28_impl(p_questions,p_mode); end $$;
create or replace function public.admin_set_question_archived(p_question_id uuid,p_archived boolean) returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_active_room_control_if_any(); perform public.admin_set_question_archived_r28_impl(p_question_id,p_archived); end $$;
create or replace function public.admin_update_question_metadata(p_question_id uuid,p_category text,p_difficulty text,p_score_enabled boolean,p_speed_bonus_pct integer,p_is_tiebreaker boolean,p_presenter_notes text) returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_active_room_control_if_any(); perform public.admin_update_question_metadata_r28_impl(p_question_id,p_category,p_difficulty,p_score_enabled,p_speed_bonus_pct,p_is_tiebreaker,p_presenter_notes); end $$;
create or replace function public.admin_duplicate_question(p_question_id uuid) returns uuid language plpgsql security definer set search_path='' as $$ begin perform private.require_active_room_control_if_any(); return public.admin_duplicate_question_r28_impl(p_question_id); end $$;
create or replace function public.admin_save_question_collection(p_name text,p_question_ids jsonb) returns uuid language plpgsql security definer set search_path='' as $$ begin perform private.require_active_room_control_if_any(); return public.admin_save_question_collection_r28_impl(p_name,p_question_ids); end $$;
create or replace function public.admin_delete_question_collection(p_collection_id uuid) returns boolean language plpgsql security definer set search_path='' as $$ begin perform private.require_active_room_control_if_any(); return public.admin_delete_question_collection_r28_impl(p_collection_id); end $$;
create or replace function public.admin_save_template(p_room_id uuid,p_name text) returns uuid language plpgsql security definer set search_path='' as $$ begin perform private.require_live_control(p_room_id); return public.admin_save_template_r28_impl(p_room_id,p_name); end $$;
create or replace function public.admin_revoke_remote_devices() returns integer language plpgsql security definer set search_path='' as $$ begin perform private.require_active_room_control_if_any(); return public.admin_revoke_remote_devices_r28_impl(); end $$;

-- Least privilege explícito: wrappers novos não ficam executáveis por PUBLIC/anon.
revoke all on function public.admin_update_planned_rounds(uuid,integer),public.admin_queue_question(uuid,uuid),public.admin_remove_queue_item(uuid,uuid),public.admin_move_queue_item(uuid,uuid,integer),public.admin_start_quiz(uuid),public.admin_prepare_next_round(uuid),public.admin_open_prepared_round(uuid),public.admin_close_and_score_round(uuid),public.admin_pause_quiz(uuid,boolean),public.admin_extend_round(uuid,integer),public.admin_annul_round(uuid),public.admin_regrade_round(uuid,text,numeric),public.admin_kick_participant(uuid,uuid,boolean),public.admin_restart_quiz(uuid),public.admin_shuffle_queue(uuid),public.admin_set_randomize_queue(uuid,boolean),public.admin_update_room_settings(uuid,jsonb),public.admin_set_reveal_stage(uuid,text),public.admin_set_final_show_stage(uuid,text),public.admin_create_room_v4(text,integer),public.admin_create_from_template(uuid,text),public.admin_duplicate_room(uuid,text),public.admin_create_remote_pairing(uuid),public.admin_create_question_v2(text,text,jsonb,text,numeric,integer,integer),public.admin_update_question_v3(uuid,text,text,jsonb,text,numeric,integer,integer,text,text,boolean,integer,boolean,text),public.admin_import_questions_v2(jsonb,text),public.admin_set_question_archived(uuid,boolean),public.admin_update_question_metadata(uuid,text,text,boolean,integer,boolean,text),public.admin_duplicate_question(uuid),public.admin_save_question_collection(text,jsonb),public.admin_delete_question_collection(uuid),public.admin_save_template(uuid,text),public.admin_revoke_remote_devices() from public,anon;

-- Grants apenas para wrappers públicos.
grant execute on function public.admin_update_planned_rounds(uuid,integer),public.admin_queue_question(uuid,uuid),public.admin_remove_queue_item(uuid,uuid),public.admin_move_queue_item(uuid,uuid,integer),public.admin_start_quiz(uuid),public.admin_prepare_next_round(uuid),public.admin_open_prepared_round(uuid),public.admin_close_and_score_round(uuid),public.admin_pause_quiz(uuid,boolean),public.admin_extend_round(uuid,integer),public.admin_annul_round(uuid),public.admin_regrade_round(uuid,text,numeric),public.admin_kick_participant(uuid,uuid,boolean),public.admin_restart_quiz(uuid),public.admin_shuffle_queue(uuid),public.admin_set_randomize_queue(uuid,boolean),public.admin_update_room_settings(uuid,jsonb),public.admin_set_reveal_stage(uuid,text),public.admin_set_final_show_stage(uuid,text),public.admin_create_room_v4(text,integer),public.admin_create_from_template(uuid,text),public.admin_duplicate_room(uuid,text),public.admin_create_remote_pairing(uuid),public.admin_create_question_v2(text,text,jsonb,text,numeric,integer,integer),public.admin_update_question_v3(uuid,text,text,jsonb,text,numeric,integer,integer,text,text,boolean,integer,boolean,text),public.admin_import_questions_v2(jsonb,text),public.admin_set_question_archived(uuid,boolean),public.admin_update_question_metadata(uuid,text,text,boolean,integer,boolean,text),public.admin_duplicate_question(uuid),public.admin_save_question_collection(text,jsonb),public.admin_delete_question_collection(uuid),public.admin_save_template(uuid,text),public.admin_revoke_remote_devices() to authenticated;

-- ---------------------------------------------------------------------------
-- 7) Estado ADM e Display com eligible_count; Display exige autorização real.
-- ---------------------------------------------------------------------------
alter function public.admin_get_room_state(uuid) rename to admin_get_room_state_r28_impl;
revoke all on function public.admin_get_room_state_r28_impl(uuid) from public,anon,authenticated;
create or replace function public.admin_get_room_state(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v jsonb; v_round uuid; v_eligible integer:=0; v_eligible_answers integer:=0; begin
  v:=public.admin_get_room_state_r28_impl(p_room_id);
  begin v_round:=(v->'round'->>'id')::uuid; exception when others then v_round:=null; end;
  if v_round is not null then select count(*) into v_eligible from public.quiz_round_eligibility where round_id=v_round; end if;
  if v_eligible=0 and v_round is not null and (v->'round'->>'status')='open' then v_eligible:=private.capture_round_eligibility(v_round); end if;
  if v_round is not null then
    select count(*) into v_eligible_answers
      from public.quiz_answers a
      join public.quiz_round_eligibility e on e.round_id=a.round_id and e.participant_id=a.participant_id
     where a.round_id=v_round;
  end if;
  return v||jsonb_build_object('eligible_count',v_eligible,'eligible_answer_count',v_eligible_answers,'waiting_count',greatest(0,v_eligible-v_eligible_answers));
end $$;
revoke all on function public.admin_get_room_state(uuid) from public,anon;
grant execute on function public.admin_get_room_state(uuid) to authenticated;

alter function public.get_public_display_state(text) rename to get_public_display_state_r28_impl;
revoke all on function public.get_public_display_state_r28_impl(text) from public,anon,authenticated;
create or replace function public.get_public_display_state(p_code text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v jsonb; v_room uuid; v_round uuid; v_eligible integer:=0; v_eligible_answers integer:=0; begin
  select id into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if v_room is null then raise exception 'Sala não encontrada'; end if;
  if not private.can_view_display(v_room) then raise exception 'Tela não autorizada'; end if;
  v:=public.get_public_display_state_r28_impl(p_code);
  begin v_round:=(v->'round'->>'id')::uuid; exception when others then v_round:=null; end;
  if v_round is not null then
    select count(*) into v_eligible from public.quiz_round_eligibility where round_id=v_round;
    select count(*) into v_eligible_answers
      from public.quiz_answers a
      join public.quiz_round_eligibility e on e.round_id=a.round_id and e.participant_id=a.participant_id
     where a.round_id=v_round;
  end if;
  return v||jsonb_build_object('eligible_count',v_eligible,'eligible_answer_count',v_eligible_answers,'waiting_count',greatest(0,v_eligible-v_eligible_answers));
end $$;
revoke all on function public.get_public_display_state(text) from public,anon;
grant execute on function public.get_public_display_state(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8) Ciclo de vida da logo: frontend só remove objeto gerenciado sem referências.
-- ---------------------------------------------------------------------------
create or replace function public.admin_managed_logo_usage_count(p_url text)
returns integer
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_count integer:=0; begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if coalesce(trim(p_url),'')='' then return 0; end if;
  select count(*) into v_count from public.quiz_rooms r where r.created_by=v_uid and r.logo_url=p_url;
  return v_count;
end $$;
revoke all on function public.admin_managed_logo_usage_count(text) from public,anon;
grant execute on function public.admin_managed_logo_usage_count(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 9) Realtime: display só escreve/lê presença quando há autorização válida.
-- ---------------------------------------------------------------------------
drop policy if exists quiz_realtime_read on realtime.messages;
create policy quiz_realtime_read
on realtime.messages for select to authenticated
using (
  realtime.messages.extension in ('broadcast','presence')
  and exists (
    select 1 from public.quiz_realtime_memberships m
    where m.user_id=(select auth.uid())
      and (
        (
          ('quiz:'||m.room_id::text)=(select realtime.topic())
          and (realtime.messages.extension='broadcast' or m.role in ('participant','admin','display'))
          and (m.role<>'display' or private.can_view_display(m.room_id))
        )
        or (
          ('quiz-admin:'||m.room_id::text)=(select realtime.topic())
          and realtime.messages.extension='broadcast'
          and m.role in ('admin','display')
          and (m.role<>'display' or private.can_view_display(m.room_id))
        )
      )
  )
);

drop policy if exists quiz_realtime_presence_write on realtime.messages;
create policy quiz_realtime_presence_write
on realtime.messages for insert to authenticated
with check (
  realtime.messages.extension='presence'
  and exists (
    select 1 from public.quiz_realtime_memberships m
    where m.user_id=(select auth.uid())
      and m.role in ('participant','admin','display')
      and ('quiz:'||m.room_id::text)=(select realtime.topic())
      and (m.role<>'display' or private.can_view_display(m.room_id))
  )
);


-- ---------------------------------------------------------------------------
-- 10) Fechamento de rotas legadas e vínculo de sessão em operações auxiliares.
-- ---------------------------------------------------------------------------
-- Rotas antigas que alteravam a partida sem o lease r29 ficam indisponíveis a clientes.
revoke all on function public.admin_create_room_v3(text,integer) from public,anon,authenticated;
revoke all on function public.admin_open_next_round(uuid) from public,anon,authenticated;
revoke all on function public.admin_recover_queue_for_room(uuid) from public,anon,authenticated;

-- Liberar o controlador exige o mesmo usuário, token e sessão que detêm o lease.
create or replace function public.admin_release_controller(p_room_id uuid,p_device_token text)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_hash text; v_rows integer; v_sid text:=private.current_auth_session_id();
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if v_sid is null then return false; end if;
  v_hash:=encode(extensions.digest(coalesce(p_device_token,''),'sha256'),'hex');
  delete from public.quiz_admin_control_leases
   where room_id=p_room_id and owner_user_id=v_uid and device_token_hash=v_hash and owner_session_id=v_sid;
  get diagnostics v_rows=row_count;
  return v_rows>0;
end;
$$;
revoke all on function public.admin_release_controller(uuid,text) from public,anon;
grant execute on function public.admin_release_controller(uuid,text) to authenticated;

-- O pareamento remoto já nasce preso à sessão autenticada do aparelho que consumiu o código.
create or replace function public.admin_claim_remote_pairing(p_code text,p_device_token text,p_device_label text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid(); v_pair public.quiz_admin_remote_pairings; v_device public.quiz_admin_remote_devices;
  v_room public.quiz_rooms; v_code text:=upper(trim(coalesce(p_code,''))); v_hash text; v_device_hash text;
  v_label text:=left(coalesce(nullif(trim(p_device_label),''),'Meu celular'),60); v_sid text:=private.current_auth_session_id();
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if v_sid is null then raise exception 'Sessão administrativa inválida'; end if;
  if length(v_code)<4 or length(v_code)>16 then raise exception 'Código de pareamento inválido'; end if;
  if length(coalesce(p_device_token,''))<20 or length(p_device_token)>200 then raise exception 'Identificação do dispositivo inválida'; end if;
  v_hash:=encode(extensions.digest(v_code,'sha256'),'hex');
  v_device_hash:=encode(extensions.digest(p_device_token,'sha256'),'hex');
  select * into v_pair from public.quiz_admin_remote_pairings
   where code_hash=v_hash and admin_user_id=v_uid and consumed_at is null and expires_at>=clock_timestamp()
   order by created_at desc limit 1 for update;
  if not found then raise exception 'Código expirado, inválido ou já utilizado'; end if;
  select * into v_room from public.quiz_rooms where id=v_pair.room_id and created_by=v_uid;
  if not found then raise exception 'Sala do pareamento não encontrada'; end if;
  insert into public.quiz_admin_remote_devices(admin_user_id,device_hash,device_label,paired_from_room_id,active,paired_at,last_seen_at,revoked_at,auth_session_id)
  values(v_uid,v_device_hash,v_label,v_pair.room_id,true,clock_timestamp(),clock_timestamp(),null,v_sid)
  on conflict(admin_user_id,device_hash) do update set device_label=excluded.device_label,paired_from_room_id=excluded.paired_from_room_id,
    active=true,paired_at=clock_timestamp(),last_seen_at=clock_timestamp(),revoked_at=null,auth_session_id=excluded.auth_session_id
  returning * into v_device;
  update public.quiz_admin_remote_pairings set consumed_at=clock_timestamp() where id=v_pair.id;
  perform private.audit_event(v_pair.room_id,v_uid,'remote_device_paired','remote_device',v_device.id,jsonb_build_object('label',v_device.device_label));
  return jsonb_build_object('authorized',true,'device_id',v_device.id,'device_label',v_device.device_label,
    'room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'phase',v_room.phase,'planned_rounds',v_room.planned_rounds));
end;
$$;
revoke all on function public.admin_claim_remote_pairing(text,text,text) from public,anon;
grant execute on function public.admin_claim_remote_pairing(text,text,text) to authenticated;

-- Criar credencial do telão também exige que este aparelho seja o controlador real.
create or replace function public.admin_create_display_pairing(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_token text; v_hash text;
  v_expires timestamptz:=clock_timestamp()+interval '5 minutes';
begin
  perform private.require_live_control(p_room_id);
  select * into v_room from public.quiz_rooms where id=p_room_id and created_by=v_uid;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.status='finished' or v_room.phase='finished' then raise exception 'A sala já foi encerrada'; end if;
  delete from public.quiz_display_pairings where admin_user_id=v_uid and (consumed_at is not null or expires_at<clock_timestamp());
  v_token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
  v_hash:=encode(extensions.digest(v_token,'sha256'),'hex');
  insert into public.quiz_display_pairings(room_id,admin_user_id,token_hash,expires_at) values(p_room_id,v_uid,v_hash,v_expires);
  perform private.audit_event(p_room_id,v_uid,'display_pairing_created','room',p_room_id,jsonb_build_object('expires_at',v_expires));
  return jsonb_build_object('pair_token',v_token,'expires_at',v_expires,'room_id',v_room.id,'room_code',v_room.code);
end;
$$;
revoke all on function public.admin_create_display_pairing(uuid) from public,anon;
grant execute on function public.admin_create_display_pairing(uuid) to authenticated;

-- Recarregar um telão já pareado não exige reutilizar o token de uso único.
create or replace function public.resume_quiz_display(p_code text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_expires timestamptz;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;
  if not private.can_view_display(v_room.id) then raise exception 'Telão não pareado. Abra o telão pelo painel ADM.'; end if;
  select a.expires_at into v_expires from public.quiz_display_authorizations a where a.room_id=v_room.id and a.user_id=v_uid;
  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at)
  values(v_uid,v_room.id,'display',clock_timestamp())
  on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;
  return jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'authorized_until',v_expires);
end;
$$;
revoke all on function public.resume_quiz_display(text) from public,anon;
grant execute on function public.resume_quiz_display(text) to authenticated;
