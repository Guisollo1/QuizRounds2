-- QuizRounds v3.27 — pareamento de celular e controle remoto do telão.

create table if not exists public.quiz_admin_remote_pairings (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  room_id uuid not null references public.quiz_rooms(id) on delete cascade,
  code_hash text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists quiz_admin_remote_pairings_admin_idx
  on public.quiz_admin_remote_pairings(admin_user_id,expires_at desc);

create table if not exists public.quiz_admin_remote_devices (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  device_hash text not null,
  device_label text not null default 'Celular remoto',
  paired_from_room_id uuid references public.quiz_rooms(id) on delete set null,
  active boolean not null default true,
  paired_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique(admin_user_id,device_hash)
);

create index if not exists quiz_admin_remote_devices_admin_idx
  on public.quiz_admin_remote_devices(admin_user_id,active,last_seen_at desc);

alter table public.quiz_admin_remote_pairings enable row level security;
alter table public.quiz_admin_remote_devices enable row level security;
revoke all on public.quiz_admin_remote_pairings, public.quiz_admin_remote_devices from public,anon,authenticated;

create or replace function public.admin_create_remote_pairing(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_code text;
  v_hash text;
  v_expires timestamptz:=clock_timestamp()+interval '5 minutes';
  v_try integer:=0;
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id and created_by=v_uid;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.status='finished' or v_room.phase='finished' then raise exception 'A sala já foi encerrada'; end if;

  delete from public.quiz_admin_remote_pairings
   where admin_user_id=v_uid and (consumed_at is not null or expires_at<clock_timestamp());

  loop
    v_try:=v_try+1;
    v_code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
    v_hash:=encode(extensions.digest(v_code,'sha256'),'hex');
    exit when not exists(select 1 from public.quiz_admin_remote_pairings where code_hash=v_hash and expires_at>clock_timestamp());
    if v_try>12 then raise exception 'Não foi possível gerar o código de pareamento'; end if;
  end loop;

  insert into public.quiz_admin_remote_pairings(admin_user_id,room_id,code_hash,expires_at)
  values(v_uid,p_room_id,v_hash,v_expires);

  perform private.audit_event(p_room_id,v_uid,'remote_pairing_created','room',p_room_id,jsonb_build_object('expires_at',v_expires));
  return jsonb_build_object('code',v_code,'expires_at',v_expires,'room_id',v_room.id,'room_code',v_room.code,'room_title',v_room.title);
end $$;

revoke all on function public.admin_create_remote_pairing(uuid) from public,anon;
grant execute on function public.admin_create_remote_pairing(uuid) to authenticated;

create or replace function public.admin_claim_remote_pairing(p_code text,p_device_token text,p_device_label text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_pair public.quiz_admin_remote_pairings;
  v_device public.quiz_admin_remote_devices;
  v_room public.quiz_rooms;
  v_code text:=upper(trim(coalesce(p_code,'')));
  v_hash text;
  v_device_hash text;
  v_label text:=left(coalesce(nullif(trim(p_device_label),''),'Meu celular'),60);
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if length(v_code)<4 or length(v_code)>16 then raise exception 'Código de pareamento inválido'; end if;
  if length(coalesce(p_device_token,''))<20 or length(p_device_token)>200 then raise exception 'Identificação do dispositivo inválida'; end if;

  v_hash:=encode(extensions.digest(v_code,'sha256'),'hex');
  v_device_hash:=encode(extensions.digest(p_device_token,'sha256'),'hex');

  select * into v_pair
    from public.quiz_admin_remote_pairings
   where code_hash=v_hash
     and admin_user_id=v_uid
     and consumed_at is null
     and expires_at>=clock_timestamp()
   order by created_at desc
   limit 1
   for update;
  if not found then raise exception 'Código expirado, inválido ou já utilizado'; end if;

  select * into v_room from public.quiz_rooms where id=v_pair.room_id and created_by=v_uid;
  if not found then raise exception 'Sala do pareamento não encontrada'; end if;

  insert into public.quiz_admin_remote_devices(admin_user_id,device_hash,device_label,paired_from_room_id,active,paired_at,last_seen_at,revoked_at)
  values(v_uid,v_device_hash,v_label,v_pair.room_id,true,clock_timestamp(),clock_timestamp(),null)
  on conflict(admin_user_id,device_hash) do update set
    device_label=excluded.device_label,
    paired_from_room_id=excluded.paired_from_room_id,
    active=true,
    paired_at=clock_timestamp(),
    last_seen_at=clock_timestamp(),
    revoked_at=null
  returning * into v_device;

  update public.quiz_admin_remote_pairings set consumed_at=clock_timestamp() where id=v_pair.id;
  perform private.audit_event(v_pair.room_id,v_uid,'remote_device_paired','remote_device',v_device.id,jsonb_build_object('label',v_device.device_label));

  return jsonb_build_object(
    'authorized',true,
    'device_id',v_device.id,
    'device_label',v_device.device_label,
    'room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'phase',v_room.phase,'planned_rounds',v_room.planned_rounds)
  );
end $$;

revoke all on function public.admin_claim_remote_pairing(text,text,text) from public,anon;
grant execute on function public.admin_claim_remote_pairing(text,text,text) to authenticated;

create or replace function public.admin_remote_device_status(p_device_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_device public.quiz_admin_remote_devices;
  v_room public.quiz_rooms;
  v_device_hash text;
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if length(coalesce(p_device_token,''))<20 or length(p_device_token)>200 then
    return jsonb_build_object('authorized',false);
  end if;
  v_device_hash:=encode(extensions.digest(p_device_token,'sha256'),'hex');
  select * into v_device
    from public.quiz_admin_remote_devices
   where admin_user_id=v_uid and device_hash=v_device_hash and active=true
   order by paired_at desc limit 1;
  if not found then return jsonb_build_object('authorized',false); end if;

  update public.quiz_admin_remote_devices set last_seen_at=clock_timestamp() where id=v_device.id;

  select * into v_room
    from public.quiz_rooms
   where created_by=v_uid and status<>'finished' and phase<>'finished'
   order by created_at desc
   limit 1;

  return jsonb_build_object(
    'authorized',true,
    'device_id',v_device.id,
    'device_label',v_device.device_label,
    'paired_at',v_device.paired_at,
    'room',case when v_room.id is null then null else jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'phase',v_room.phase,'planned_rounds',v_room.planned_rounds) end
  );
end $$;

revoke all on function public.admin_remote_device_status(text) from public,anon;
grant execute on function public.admin_remote_device_status(text) to authenticated;

create or replace function public.admin_list_remote_devices()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_rows jsonb;
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,'label',d.device_label,'active',d.active,'paired_at',d.paired_at,'last_seen_at',d.last_seen_at,'revoked_at',d.revoked_at
  ) order by d.active desc,d.last_seen_at desc),'[]'::jsonb)
  into v_rows
  from public.quiz_admin_remote_devices d where d.admin_user_id=v_uid;
  return v_rows;
end $$;

revoke all on function public.admin_list_remote_devices() from public,anon;
grant execute on function public.admin_list_remote_devices() to authenticated;

create or replace function public.admin_revoke_remote_devices()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_count integer:=0;
begin
  if v_uid is null or not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  update public.quiz_admin_remote_devices
     set active=false,revoked_at=clock_timestamp()
   where admin_user_id=v_uid and active=true;
  get diagnostics v_count=row_count;
  delete from public.quiz_admin_remote_pairings where admin_user_id=v_uid and consumed_at is null;
  return v_count;
end $$;

revoke all on function public.admin_revoke_remote_devices() from public,anon;
grant execute on function public.admin_revoke_remote_devices() to authenticated;
