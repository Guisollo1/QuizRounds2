-- QuizRounds2 v3.68-r52 — formação de equipes em 3 modos
-- Requer schema 042.
-- Modos: auto (equilibrado), player (jogador escolhe), admin (ADM define).

create or replace function public.admin_save_teams(p_room_id uuid,p_teams jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_room public.quiz_rooms;
  x jsonb;
  v_count integer:=0;
  v_name text;
  v_color text;
  v_icon text;
  v_assignments jsonb:='{}'::jsonb;
  v_mode text;
  v_part record;
  v_team public.quiz_teams;
begin
  perform private.require_admin_capability('present');
  perform private.require_live_control(p_room_id);
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.phase<>'lobby' then raise exception 'As equipes só podem ser alteradas no lobby'; end if;
  if jsonb_typeof(coalesce(p_teams,'[]'::jsonb))<>'array' then raise exception 'Lista de equipes inválida'; end if;

  select coalesce(jsonb_object_agg(p.id::text,t.name),'{}'::jsonb)
    into v_assignments
    from public.quiz_participants p
    join public.quiz_teams t on t.id=p.team_id
   where p.room_id=p_room_id and not p.kicked;

  update public.quiz_participants set team_id=null,ready=false where room_id=p_room_id;
  delete from public.quiz_teams where room_id=p_room_id;

  for x in select value from jsonb_array_elements(coalesce(p_teams,'[]'::jsonb)) loop
    v_name:=left(trim(coalesce(x->>'name','')),40);
    if v_name='' then continue; end if;
    v_color:=coalesce(nullif(x->>'color',''),'#1976d2');
    if v_color !~ '^#[0-9A-Fa-f]{6}$' then v_color:='#1976d2'; end if;
    v_icon:=left(coalesce(nullif(x->>'icon',''),'★'),4);
    insert into public.quiz_teams(room_id,name,color,icon,sort_order)
      values(p_room_id,v_name,v_color,v_icon,v_count);
    v_count:=v_count+1;
    if v_count>=12 then exit; end if;
  end loop;

  if v_count<2 and coalesce(v_room.settings->>'game_mode','classic')='teams' then
    raise exception 'Use pelo menos duas equipes no modo Equipes';
  end if;

  update public.quiz_participants p
     set team_id=t.id
    from public.quiz_teams t
   where p.room_id=p_room_id
     and t.room_id=p_room_id
     and t.name=(v_assignments->>p.id::text);

  v_mode:=coalesce(nullif(v_room.settings->>'team_join_mode',''),'auto');
  if v_mode='auto' then
    for v_part in
      select p.id from public.quiz_participants p
       where p.room_id=p_room_id and not p.kicked and p.team_id is null
       order by p.joined_at,p.id
    loop
      select t.* into v_team
        from public.quiz_teams t
        left join lateral(
          select count(*) c from public.quiz_participants p
           where p.room_id=p_room_id and p.team_id=t.id and not p.kicked
        ) pc on true
       where t.room_id=p_room_id
       order by pc.c asc,t.sort_order,t.name limit 1;
      if v_team.id is not null then
        update public.quiz_participants set team_id=v_team.id where id=v_part.id;
      end if;
    end loop;
  end if;

  perform private.notify_room(p_room_id);
  return public.admin_list_teams(p_room_id);
end $$;

create or replace function public.admin_set_team_join_mode(p_room_id uuid,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_room public.quiz_rooms;
  v_mode text:=lower(trim(coalesce(p_mode,'auto')));
  v_part record;
  v_team public.quiz_teams;
begin
  perform private.require_admin_capability('present');
  perform private.require_live_control(p_room_id);
  if v_mode not in ('auto','player','admin') then raise exception 'Modo de formação de equipes inválido'; end if;
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.phase<>'lobby' then raise exception 'A formação das equipes só pode ser alterada no lobby'; end if;
  if coalesce(v_room.settings->>'game_mode','classic')<>'teams' then raise exception 'A sala não está no modo Equipes'; end if;

  update public.quiz_rooms
     set settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{team_join_mode}',to_jsonb(v_mode),true)
   where id=p_room_id
   returning * into v_room;

  if not exists(select 1 from public.quiz_teams where room_id=p_room_id) then
    insert into public.quiz_teams(room_id,name,color,icon,sort_order) values
      (p_room_id,'Equipe Azul','#1976d2','●',0),
      (p_room_id,'Equipe Verde','#20a06c','●',1)
    on conflict(room_id,name) do nothing;
  end if;

  if v_mode='auto' then
    for v_part in
      select p.id from public.quiz_participants p
       where p.room_id=p_room_id and not p.kicked and p.team_id is null
       order by p.joined_at,p.id
    loop
      select t.* into v_team
        from public.quiz_teams t
        left join lateral(
          select count(*) c from public.quiz_participants p
           where p.room_id=p_room_id and p.team_id=t.id and not p.kicked
        ) pc on true
       where t.room_id=p_room_id
       order by pc.c asc,t.sort_order,t.name limit 1;
      if v_team.id is not null then
        update public.quiz_participants set team_id=v_team.id where id=v_part.id;
      end if;
    end loop;
  end if;

  perform private.notify_room(p_room_id);
  return jsonb_build_object('room_id',p_room_id,'team_join_mode',v_mode);
end $$;

create or replace function public.pro_player_team_state(p_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_part public.quiz_participants;
  v_team public.quiz_teams;
  v_teams jsonb;
  v_mode text;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) and status<>'finished' order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;
  select * into v_part from public.quiz_participants where room_id=v_room.id and user_id=v_uid and not kicked;
  if not found then raise exception 'Participante não encontrado'; end if;
  v_mode:=coalesce(nullif(v_room.settings->>'team_join_mode',''),'auto');
  if v_mode not in ('auto','player','admin') then v_mode:='auto'; end if;
  if v_part.team_id is not null then select * into v_team from public.quiz_teams where id=v_part.team_id; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id',x.id,'name',x.name,'color',x.color,'icon',x.icon,'sort_order',x.sort_order,'players',x.players
    ) order by x.sort_order,x.name),'[]'::jsonb)
    into v_teams
    from (
      select t.id,t.name,t.color,t.icon,t.sort_order,count(p.id)::integer players
        from public.quiz_teams t
        left join public.quiz_participants p on p.team_id=t.id and not p.kicked
       where t.room_id=v_room.id
       group by t.id,t.name,t.color,t.icon,t.sort_order
    ) x;

  return jsonb_build_object(
    'mode',case when coalesce(v_room.settings->>'game_mode','classic')='teams' then 'teams' else 'classic' end,
    'join_mode',v_mode,
    'phase',v_room.phase,
    'can_choose',coalesce(v_room.settings->>'game_mode','classic')='teams' and v_room.phase='lobby' and v_mode='player',
    'assigned',v_part.team_id is not null,
    'team_id',v_team.id,
    'team_name',v_team.name,
    'team_color',v_team.color,
    'team_icon',v_team.icon,
    'teams',v_teams
  );
end $$;

create or replace function public.pro_player_ensure_team(p_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_part public.quiz_participants;
  v_team public.quiz_teams;
  v_mode text;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) and status<>'finished' order by created_at desc limit 1;
  if not found then raise exception 'Sala não encontrada'; end if;
  select * into v_part from public.quiz_participants where room_id=v_room.id and user_id=v_uid and not kicked for update;
  if not found then raise exception 'Participante não encontrado'; end if;
  if coalesce(v_room.settings->>'game_mode','classic')<>'teams' then
    return jsonb_build_object('team_id',null,'team_name',null,'mode','classic','join_mode','auto','assigned',false);
  end if;
  if not exists(select 1 from public.quiz_teams where room_id=v_room.id) then
    insert into public.quiz_teams(room_id,name,color,icon,sort_order) values
      (v_room.id,'Equipe Azul','#1976d2','●',0),
      (v_room.id,'Equipe Verde','#20a06c','●',1)
    on conflict(room_id,name) do nothing;
  end if;
  v_mode:=coalesce(nullif(v_room.settings->>'team_join_mode',''),'auto');
  if v_mode not in ('auto','player','admin') then v_mode:='auto'; end if;

  if v_part.team_id is null and v_mode='auto' then
    select t.* into v_team
      from public.quiz_teams t
      left join lateral(
        select count(*) c from public.quiz_participants p
         where p.room_id=v_room.id and p.team_id=t.id and not p.kicked
      ) pc on true
     where t.room_id=v_room.id
     order by pc.c asc,t.sort_order,t.name limit 1;
    if v_team.id is not null then
      update public.quiz_participants set team_id=v_team.id where id=v_part.id;
      v_part.team_id:=v_team.id;
      perform private.notify_room(v_room.id);
    end if;
  elsif v_part.team_id is not null then
    select * into v_team from public.quiz_teams where id=v_part.team_id;
  end if;

  if v_part.team_id is not null and v_team.id is null then select * into v_team from public.quiz_teams where id=v_part.team_id; end if;
  return jsonb_build_object(
    'team_id',v_team.id,'team_name',v_team.name,'team_color',v_team.color,'team_icon',v_team.icon,
    'mode','teams','join_mode',v_mode,'assigned',v_team.id is not null
  );
end $$;

create or replace function public.pro_player_choose_team(p_code text,p_team_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_part public.quiz_participants;
  v_mode text;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) and status<>'finished' order by created_at desc limit 1 for update;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.phase<>'lobby' then raise exception 'A equipe só pode ser escolhida no lobby'; end if;
  if coalesce(v_room.settings->>'game_mode','classic')<>'teams' then raise exception 'Esta sala não está no modo Equipes'; end if;
  v_mode:=coalesce(nullif(v_room.settings->>'team_join_mode',''),'auto');
  if v_mode<>'player' then raise exception 'A escolha de equipe pelo jogador não está habilitada'; end if;
  if not exists(select 1 from public.quiz_teams where id=p_team_id and room_id=v_room.id) then raise exception 'Equipe inválida'; end if;
  select * into v_part from public.quiz_participants where room_id=v_room.id and user_id=v_uid and not kicked for update;
  if not found then raise exception 'Participante não encontrado'; end if;
  update public.quiz_participants set team_id=p_team_id,ready=false,last_seen_at=clock_timestamp() where id=v_part.id;
  perform private.notify_room(v_room.id);
  return public.pro_player_team_state(p_code);
end $$;

create or replace function public.admin_team_lobby_state(p_room_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_room public.quiz_rooms;
  v_teams jsonb;
  v_players jsonb;
  v_mode text;
begin
  perform private.require_admin_capability('view');
  select * into v_room from public.quiz_rooms where id=p_room_id;
  if not found then raise exception 'Sala não encontrada'; end if;
  v_mode:=coalesce(nullif(v_room.settings->>'team_join_mode',''),'auto');
  if v_mode not in ('auto','player','admin') then v_mode:='auto'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',x.id,'name',x.name,'color',x.color,'icon',x.icon,'sort_order',x.sort_order,'players',x.players
  ) order by x.sort_order,x.name),'[]'::jsonb)
  into v_teams
  from (
    select t.id,t.name,t.color,t.icon,t.sort_order,count(p.id)::integer players
      from public.quiz_teams t
      left join public.quiz_participants p on p.team_id=t.id and not p.kicked
     where t.room_id=p_room_id
     group by t.id,t.name,t.color,t.icon,t.sort_order
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'name',p.display_name,'avatar_key',p.avatar_key,'team_id',p.team_id,'ready',p.ready,
    'connected',p.last_seen_at>=clock_timestamp()-interval '90 seconds'
  ) order by p.joined_at,p.display_name),'[]'::jsonb)
  into v_players
  from public.quiz_participants p where p.room_id=p_room_id and not p.kicked;

  return jsonb_build_object('room_id',p_room_id,'phase',v_room.phase,'join_mode',v_mode,'teams',v_teams,'players',v_players);
end $$;

create or replace function public.admin_assign_participant_team(p_room_id uuid,p_participant_id uuid,p_team_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_room public.quiz_rooms;
begin
  perform private.require_admin_capability('present');
  perform private.require_live_control(p_room_id);
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.phase<>'lobby' then raise exception 'As equipes só podem ser alteradas no lobby'; end if;
  if coalesce(v_room.settings->>'game_mode','classic')<>'teams' then raise exception 'A sala não está no modo Equipes'; end if;
  if not exists(select 1 from public.quiz_participants where id=p_participant_id and room_id=p_room_id and not kicked) then raise exception 'Participante inválido'; end if;
  if p_team_id is not null and not exists(select 1 from public.quiz_teams where id=p_team_id and room_id=p_room_id) then raise exception 'Equipe inválida'; end if;
  update public.quiz_participants set team_id=p_team_id,ready=false where id=p_participant_id;
  perform private.notify_room(p_room_id);
  return public.admin_team_lobby_state(p_room_id);
end $$;

create or replace function public.player_set_ready(p_room_id uuid,p_ready boolean)
returns void language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_room public.quiz_rooms;
  v_part public.quiz_participants;
  v_mode text;
  v_changed integer:=0;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms r where r.id=p_room_id and r.phase='lobby';
  if not found then raise exception 'Prontidão só pode ser alterada no lobby'; end if;
  select * into v_part from public.quiz_participants where room_id=p_room_id and user_id=v_uid and not kicked for update;
  if not found then raise exception 'Participante não encontrado'; end if;

  if coalesce(p_ready,false) and coalesce(v_room.settings->>'game_mode','classic')='teams' and v_part.team_id is null then
    v_mode:=coalesce(nullif(v_room.settings->>'team_join_mode',''),'auto');
    if v_mode='auto' then
      perform public.pro_player_ensure_team(v_room.code);
      select * into v_part from public.quiz_participants where id=v_part.id;
    end if;
    if v_part.team_id is null then
      if v_mode='player' then raise exception 'Escolha sua equipe antes de marcar Estou pronto'; end if;
      if v_mode='admin' then raise exception 'Aguarde o ADM definir sua equipe antes de marcar Estou pronto'; end if;
      raise exception 'Sua equipe ainda não foi definida';
    end if;
  end if;

  update public.quiz_participants
     set ready=coalesce(p_ready,false),last_seen_at=clock_timestamp()
   where id=v_part.id;
  get diagnostics v_changed=row_count;
  if v_changed<1 then raise exception 'Participante não encontrado'; end if;
  perform private.notify_room(p_room_id);
end $$;

revoke all on function public.admin_save_teams(uuid,jsonb),public.admin_set_team_join_mode(uuid,text),public.admin_team_lobby_state(uuid),public.admin_assign_participant_team(uuid,uuid,uuid) from public,anon;
grant execute on function public.admin_save_teams(uuid,jsonb),public.admin_set_team_join_mode(uuid,text),public.admin_team_lobby_state(uuid),public.admin_assign_participant_team(uuid,uuid,uuid) to authenticated;
revoke all on function public.pro_player_ensure_team(text),public.pro_player_team_state(text),public.pro_player_choose_team(text,uuid) from public;
grant execute on function public.pro_player_ensure_team(text),public.pro_player_team_state(text),public.pro_player_choose_team(text,uuid) to anon,authenticated;
revoke all on function public.player_set_ready(uuid,boolean) from public,anon;
grant execute on function public.player_set_ready(uuid,boolean) to authenticated;

create or replace function public.get_quiz_backend_meta()
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'schema_version',43,
    'release','3.68-r52',
    'min_frontend_build','3.68-r52',
    'features',jsonb_build_array(
      'secure_display_pairing','controller_backend_guard','round_eligibility_snapshot','display_state_privacy','build_handshake','avatar_catalog_31',
      'gameshow_pro','game_modes','teams','team_formation_auto','team_formation_player','team_formation_admin','question_media','special_questions','professional_question_bank','csv_json_import','post_event_dashboard','audio_profiles','rehearsal_tools','admin_roles','event_branding',
      'nearest','precision_tiers','ordering','matching','classification','true_false_series','hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','team_mission','knowledge_bingo','wheel','surprise_box','chosen_category','random_category','progressive_difficulty','exam_mode','crowd_prediction','live_poll','audience_choice'
    ),
    'server_now',clock_timestamp()
  );
$$;
revoke all on function public.get_quiz_backend_meta() from public;
grant execute on function public.get_quiz_backend_meta() to anon,authenticated;
