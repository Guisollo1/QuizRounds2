-- QuizRounds v3.38 — prontidão explícita e métricas do lobby
create or replace function public.player_set_ready(p_room_id uuid, p_ready boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_changed integer:=0;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  if not exists(select 1 from public.quiz_rooms r where r.id=p_room_id and r.phase='lobby') then
    raise exception 'Prontidão só pode ser alterada no lobby';
  end if;
  update public.quiz_participants
     set ready=coalesce(p_ready,false),last_seen_at=clock_timestamp()
   where room_id=p_room_id and user_id=v_uid and not kicked;
  get diagnostics v_changed=row_count;
  if v_changed<1 then raise exception 'Participante não encontrado'; end if;
  perform private.notify_room(p_room_id);
end
$function$;

create or replace function public.get_public_avatar_roster(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_now timestamptz:=clock_timestamp(); v_rows jsonb;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;
  if not exists(select 1 from public.quiz_realtime_memberships where user_id=v_uid and room_id=v_room.id and role in ('display','admin','participant')) then raise exception 'Tela não autorizada'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'participant_id',p.id,'display_name',p.display_name,'avatar_key',p.avatar_key,'total_points',p.total_points,
    'connected',p.last_seen_at>=v_now-interval '90 seconds','ready',p.ready,'joined_at',p.joined_at
  ) order by p.joined_at,p.id),'[]'::jsonb) into v_rows
  from public.quiz_participants p where p.room_id=v_room.id and not p.kicked;
  return v_rows;
end
$function$;

create or replace function public.get_public_display_state(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();v_room public.quiz_rooms;v_round public.quiz_rounds;v_round_json jsonb;v_rank jsonb;v_now timestamptz:=clock_timestamp();
  v_participants int:=0;v_active int:=0;v_ready int:=0;v_answers int:=0;v_used int:=0;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;
  if not exists(select 1 from public.quiz_realtime_memberships where user_id=v_uid and room_id=v_room.id and role in ('display','admin','participant')) then raise exception 'Tela não autorizada'; end if;
  select * into v_round from public.quiz_rounds where room_id=v_room.id order by round_no desc limit 1;
  if found then
    v_round_json:=jsonb_build_object('id',v_round.id,'round_no',v_round.round_no,'status',v_round.status,'opened_at',v_round.opened_at,'closed_at',v_round.closed_at,'closes_at',v_round.closes_at,'time_limit_seconds',v_round.time_limit_seconds,'prompt',v_round.prompt_snapshot,'question_type',v_round.question_type_snapshot,'options',coalesce(v_round.options_snapshot,'[]'::jsonb),'points',v_round.points_snapshot,'category',v_round.category_snapshot,'difficulty',v_round.difficulty_snapshot,'result_text',case when v_room.reveal_stage in ('answer','distribution','ranking','final') then v_round.result_text end,'winner_snapshot',case when v_room.reveal_stage in ('answer','distribution','ranking','final') then v_round.winner_snapshot end,'distribution',case when v_room.reveal_stage in ('distribution','ranking','final') then v_round.distribution_snapshot end,'movers',case when v_room.reveal_stage in ('ranking','final') then v_round.ranking_movers_snapshot end);
  end if;
  v_rank:=case when v_room.reveal_stage in ('ranking','final') or v_room.phase='finished' then private.generate_ranking(v_room.id) else '[]'::jsonb end;
  select count(*) into v_participants from public.quiz_participants where room_id=v_room.id and not kicked;
  select count(*) into v_active from public.quiz_participants where room_id=v_room.id and not kicked and last_seen_at>=v_now-interval '90 seconds';
  select count(*) into v_ready from public.quiz_participants where room_id=v_room.id and not kicked and ready;
  select count(*) into v_used from public.quiz_rounds where room_id=v_room.id;
  if v_round.id is not null and v_round.status='open' then select count(*) into v_answers from public.quiz_answers where round_id=v_round.id; else v_answers:=coalesce(v_round.answer_count_snapshot,0); end if;
  return jsonb_build_object('room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'planned_rounds',v_room.planned_rounds,'phase',v_room.phase,'state_version',v_room.state_version,'generation',v_room.game_generation,'settings',v_room.settings,'theme',v_room.theme_preset,'logo_url',v_room.logo_url,'prepared_until',v_room.prepared_until,'reveal_stage',v_room.reveal_stage),'round',v_round_json,'ranking',v_rank,'participant_count',v_participants,'active_count',v_active,'ready_count',v_ready,'answer_count',v_answers,'used_rounds',v_used,'server_now',v_now);
end
$function$;

revoke all on function public.player_set_ready(uuid,boolean) from public,anon;
grant execute on function public.player_set_ready(uuid,boolean) to authenticated;
revoke all on function public.get_public_avatar_roster(text) from public,anon;
grant execute on function public.get_public_avatar_roster(text) to authenticated;
revoke all on function public.get_public_display_state(text) from public,anon;
grant execute on function public.get_public_display_state(text) to authenticated;
