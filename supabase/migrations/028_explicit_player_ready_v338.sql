-- QuizRounds v3.38 — jogador novo entra aguardando confirmação de prontidão
create or replace function public.join_quiz_room(p_code text, p_name text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_room public.quiz_rooms; v_part public.quiz_participants; v_uid uuid:=auth.uid(); v_name text:=trim(p_name); v_rounds integer:=0; v_policy text; v_allow_dupes boolean; v_bad text;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  if length(v_name)<1 or length(v_name)>32 then raise exception 'Nome inválido'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) and status<>'finished' order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada ou encerrada'; end if;
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
  if not v_allow_dupes and exists(select 1 from public.quiz_participants where room_id=v_room.id and lower(display_name)=lower(v_name) and user_id<>v_uid and not kicked) then raise exception 'Esse nome já está em uso'; end if;
  insert into public.quiz_participants(room_id,user_id,display_name,last_join_at,last_seen_at,ready,kicked)
  values(v_room.id,v_uid,v_name,clock_timestamp(),clock_timestamp(),false,false)
  on conflict(room_id,user_id) do update set display_name=excluded.display_name,last_join_at=excluded.last_join_at,last_seen_at=excluded.last_seen_at,kicked=false
  returning * into v_part;
  insert into public.quiz_realtime_memberships(user_id,room_id,role,authorized_at)
  values(v_uid,v_room.id,'participant',clock_timestamp())
  on conflict(user_id,room_id,role) do update set authorized_at=excluded.authorized_at;
  perform private.notify_room(v_room.id);
  return jsonb_build_object('room',to_jsonb(v_room),'participant',to_jsonb(v_part),'missed_before_join',greatest(0,v_rounds));
end
$function$;

revoke all on function public.join_quiz_room(text,text) from public,anon;
grant execute on function public.join_quiz_room(text,text) to authenticated;
