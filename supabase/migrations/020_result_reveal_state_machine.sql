-- QuizRounds v3.31
-- Faz o resultado seguir: encerrado -> resposta -> distribuição -> ranking -> final.

create or replace function private.quiz_hold_result_before_finish()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if old.phase='question_open' and new.phase in ('result','finished') then
    new.reveal_stage:='hidden';
    if new.phase='finished' then
      new.phase:='result';
      new.game_status:='running';
      new.status:='live';
      new.finished_at:=null;
    end if;
  end if;
  return new;
end $function$;

drop trigger if exists trg_quiz_hold_result_before_finish on public.quiz_rooms;
create trigger trg_quiz_hold_result_before_finish
before update on public.quiz_rooms
for each row execute function private.quiz_hold_result_before_finish();

create or replace function public.admin_set_reveal_stage(p_room_id uuid,p_stage text)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_round_count integer; v_rank jsonb;
begin
  if not private.is_admin(v_uid) then raise exception 'Acesso negado'; end if;
  if p_stage not in ('hidden','answer','distribution','ranking','final') then raise exception 'Etapa inválida'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id and created_by=v_uid for update;
  if not found then raise exception 'Sala inválida'; end if;
  if p_stage='final' then
    select count(*) into v_round_count from public.quiz_rounds where room_id=p_room_id;
    if v_round_count<v_room.planned_rounds then raise exception 'Ainda existem rounds a apresentar'; end if;
    if exists(select 1 from public.quiz_rounds where room_id=p_room_id and status='open') then raise exception 'Encerre a pergunta antes do resultado final'; end if;
    v_rank:=private.generate_ranking(p_room_id);
    update public.quiz_rooms set phase='finished',game_status='finished',status='finished',finished_at=clock_timestamp(),reveal_stage='final',final_ranking_snapshot=v_rank where id=p_room_id;
    perform private.audit_event(p_room_id,v_uid,'quiz_final_revealed','room',p_room_id,jsonb_build_object('rounds',v_round_count));
    perform private.publish_room_event(p_room_id,'quiz_finished',jsonb_build_object('rounds',v_round_count));
    return;
  end if;
  if v_room.phase not in ('result','finished') then raise exception 'Revelação disponível somente após encerrar o round'; end if;
  update public.quiz_rooms set reveal_stage=p_stage where id=p_room_id;
  perform private.publish_room_event(p_room_id,'reveal_changed',jsonb_build_object('stage',p_stage));
end $function$;

revoke all on function public.admin_set_reveal_stage(uuid,text) from public,anon;
grant execute on function public.admin_set_reveal_stage(uuid,text) to authenticated;
