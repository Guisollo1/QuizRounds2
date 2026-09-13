-- QuizRounds v3.65 — controle remoto sempre vinculado à sala correta
-- Corrige aparelho já autorizado descartando novo pareamento e sala lembrada incorreta no navegador móvel.

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
   order by paired_at desc
   limit 1;
  if not found then return jsonb_build_object('authorized',false); end if;

  -- Primeiro respeita a sala explicitamente associada pelo último QR/código, se ainda estiver ativa.
  if v_device.paired_from_room_id is not null then
    select * into v_room
      from public.quiz_rooms
     where id=v_device.paired_from_room_id
       and created_by=v_uid
       and status<>'finished'
       and phase<>'finished';
  end if;

  -- Se a sala associada acabou, acompanha automaticamente a sala ativa mais recente do mesmo ADM.
  if v_room.id is null then
    select * into v_room
      from public.quiz_rooms
     where created_by=v_uid
       and status<>'finished'
       and phase<>'finished'
     order by created_at desc
     limit 1;
  end if;

  update public.quiz_admin_remote_devices
     set last_seen_at=clock_timestamp(),
         paired_from_room_id=case when v_room.id is null then paired_from_room_id else v_room.id end
   where id=v_device.id;

  return jsonb_build_object(
    'authorized',true,
    'device_id',v_device.id,
    'device_label',v_device.device_label,
    'paired_at',v_device.paired_at,
    'room',case when v_room.id is null then null else jsonb_build_object(
      'id',v_room.id,
      'code',v_room.code,
      'title',v_room.title,
      'phase',v_room.phase,
      'status',v_room.status,
      'planned_rounds',v_room.planned_rounds
    ) end
  );
end $$;

revoke all on function public.admin_remote_device_status(text) from public,anon;
grant execute on function public.admin_remote_device_status(text) to authenticated;
