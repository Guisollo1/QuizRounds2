-- QuizRounds v3.66 — estado final do controle remoto + conclusão robusta
-- Mantém o remoto preso à sala que terminou e só migra para uma sala realmente mais nova.

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
  v_paired public.quiz_rooms;
  v_newer public.quiz_rooms;
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

  if v_device.paired_from_room_id is not null then
    select * into v_paired
      from public.quiz_rooms
     where id=v_device.paired_from_room_id
       and created_by=v_uid;
  end if;

  -- Só troca automaticamente se existir uma sala ATIVA criada DEPOIS da sala pareada.
  if v_paired.id is not null then
    select * into v_newer
      from public.quiz_rooms
     where created_by=v_uid
       and status<>'finished'
       and phase<>'finished'
       and created_at>v_paired.created_at
     order by created_at desc
     limit 1;
    if v_newer.id is not null then v_room:=v_newer; else v_room:=v_paired; end if;
  else
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

create or replace function public.admin_set_reveal_stage(p_room_id uuid,p_stage text)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_round_count integer;
  v_queued integer;
  v_rank jsonb;
  v_expected text;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_stage not in ('answer','distribution','ranking','final') then raise exception 'Etapa inválida'; end if;

  select * into v_room
    from public.quiz_rooms
   where id=p_room_id and created_by=v_uid
   for update;
  if not found then raise exception 'Sala inválida'; end if;
  if v_room.phase not in ('result','finished') then raise exception 'Revelação disponível somente após encerrar o round'; end if;

  v_expected:=case coalesce(v_room.reveal_stage,'hidden')
    when 'hidden' then 'answer'
    when 'answer' then 'distribution'
    when 'distribution' then 'ranking'
    when 'ranking' then 'final'
    else null
  end;
  if p_stage<>v_expected then
    raise exception 'Sequência inválida: a próxima etapa é %',coalesce(v_expected,'nenhuma');
  end if;

  if p_stage='final' then
    select count(*) into v_round_count from public.quiz_rounds where room_id=p_room_id;
    select count(*) into v_queued from public.quiz_room_queue where room_id=p_room_id and status='queued';

    if exists(select 1 from public.quiz_rounds where room_id=p_room_id and status='open') then
      raise exception 'Encerre a pergunta antes do resultado final';
    end if;

    -- Se a fila realmente acabou, o número de rounds realizado vira a fonte de verdade.
    if v_round_count<v_room.planned_rounds then
      if v_queued=0 and v_room.prepared_queue_id is null and v_round_count>0 then
        update public.quiz_rooms set planned_rounds=v_round_count where id=p_room_id;
      else
        raise exception 'Ainda existem rounds a apresentar';
      end if;
    end if;

    v_rank:=private.generate_ranking(p_room_id);
    update public.quiz_rooms
       set phase='finished',
           game_status='finished',
           status='finished',
           finished_at=clock_timestamp(),
           reveal_stage='final',
           final_ranking_snapshot=v_rank,
           settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{final_show_stage}',to_jsonb('ranking'::text),true)
     where id=p_room_id;

    perform private.audit_event(p_room_id,v_uid,'quiz_final_revealed','room',p_room_id,jsonb_build_object('rounds',v_round_count,'final_show_stage','ranking'));
    perform private.publish_room_event(p_room_id,'quiz_finished',jsonb_build_object('rounds',v_round_count,'final_show_stage','ranking'));
    return;
  end if;

  update public.quiz_rooms set reveal_stage=p_stage where id=p_room_id;
  perform private.publish_room_event(p_room_id,'reveal_changed',jsonb_build_object('stage',p_stage));
end
$function$;

revoke all on function public.admin_set_reveal_stage(uuid,text) from public,anon;
grant execute on function public.admin_set_reveal_stage(uuid,text) to authenticated;
