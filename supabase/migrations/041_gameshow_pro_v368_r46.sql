-- QuizRounds2 v3.68-r46 — GameShow Pro / schema 041
-- Recursos opt-in e retrocompatíveis:
-- modos de jogo, equipes, mídia e metadados avançados de perguntas,
-- dashboard pós-evento, permissões administrativas, branding e apoio ao modo ensaio.

-- -----------------------------------------------------------------------------
-- 1) Permissões administrativas por papel
-- -----------------------------------------------------------------------------
alter table public.quiz_admins
  add column if not exists role text not null default 'owner',
  add column if not exists permissions jsonb not null default '{}'::jsonb;

do $$ begin
  alter table public.quiz_admins add constraint quiz_admins_role_check
    check (role in ('owner','presenter','editor','viewer'));
exception when duplicate_object then null; end $$;

create or replace function private.admin_role(p_uid uuid)
returns text language sql stable security definer set search_path='' as $$
  select coalesce((select a.role from public.quiz_admins a where a.user_id=p_uid),'none')
$$;
revoke all on function private.admin_role(uuid) from public,anon,authenticated;

create or replace function private.require_admin_capability(p_capability text)
returns void language plpgsql stable security definer set search_path='' as $$
declare v_role text:=private.admin_role(auth.uid());
begin
  if p_capability='owner' and v_role<>'owner' then raise exception 'Apenas o proprietário pode executar esta ação'; end if;
  if p_capability='present' and v_role not in ('owner','presenter') then raise exception 'Seu perfil não pode controlar a apresentação'; end if;
  if p_capability='edit' and v_role not in ('owner','editor') then raise exception 'Seu perfil não pode editar o banco de perguntas'; end if;
  if p_capability='view' and v_role='none' then raise exception 'Acesso negado'; end if;
end $$;
revoke all on function private.require_admin_capability(text) from public,anon,authenticated;

create or replace function public.admin_get_my_role()
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('user_id',auth.uid(),'role',private.admin_role(auth.uid()))
$$;
revoke all on function public.admin_get_my_role() from public,anon;
grant execute on function public.admin_get_my_role() to authenticated;

create or replace function public.admin_list_role_members()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v jsonb;
begin
  perform private.require_admin_capability('owner');
  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id',a.user_id,'email',u.email,'role',a.role,'created_at',a.created_at
  ) order by case a.role when 'owner' then 1 when 'presenter' then 2 when 'editor' then 3 else 4 end,u.email),'[]'::jsonb)
  into v
  from public.quiz_admins a join auth.users u on u.id=a.user_id;
  return v;
end $$;
revoke all on function public.admin_list_role_members() from public,anon;
grant execute on function public.admin_list_role_members() to authenticated;

create or replace function public.admin_set_role_by_email(p_email text,p_role text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user auth.users; v_role text:=lower(trim(coalesce(p_role,''))); v_owner_count integer;
begin
  perform private.require_admin_capability('owner');
  if v_role not in ('owner','presenter','editor','viewer','remove') then raise exception 'Papel inválido'; end if;
  select * into v_user from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if not found then raise exception 'Usuário não encontrado no Supabase Authentication'; end if;
  if v_role='remove' then
    select count(*) into v_owner_count from public.quiz_admins where role='owner';
    if exists(select 1 from public.quiz_admins where user_id=v_user.id and role='owner') and v_owner_count<=1 then
      raise exception 'Não é possível remover o último proprietário';
    end if;
    delete from public.quiz_admins where user_id=v_user.id;
    return jsonb_build_object('email',v_user.email,'role','removed');
  end if;
  insert into public.quiz_admins(user_id,role) values(v_user.id,v_role)
  on conflict(user_id) do update set role=excluded.role;
  return jsonb_build_object('email',v_user.email,'role',v_role,'user_id',v_user.id);
end $$;
revoke all on function public.admin_set_role_by_email(text,text) from public,anon;
grant execute on function public.admin_set_role_by_email(text,text) to authenticated;

-- -----------------------------------------------------------------------------
-- 2) Equipes
-- -----------------------------------------------------------------------------
create table if not exists public.quiz_teams(
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.quiz_rooms(id) on delete cascade,
  name text not null check(length(name) between 1 and 40),
  color text not null default '#1976d2',
  icon text not null default '★',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique(room_id,name)
);
alter table public.quiz_teams enable row level security;
revoke all on public.quiz_teams from anon,authenticated;

alter table public.quiz_participants add column if not exists team_id uuid references public.quiz_teams(id) on delete set null;
create index if not exists quiz_participants_team_idx on public.quiz_participants(room_id,team_id,total_points desc);
create index if not exists quiz_teams_room_idx on public.quiz_teams(room_id,sort_order,name);

create or replace function public.admin_save_teams(p_room_id uuid,p_teams jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_room public.quiz_rooms; x jsonb; v_count integer:=0; v_name text; v_color text; v_icon text;
begin
  perform private.require_admin_capability('present');
  perform private.require_live_control(p_room_id);
  select * into v_room from public.quiz_rooms where id=p_room_id for update;
  if not found then raise exception 'Sala não encontrada'; end if;
  if v_room.phase<>'lobby' then raise exception 'As equipes só podem ser alteradas no lobby'; end if;
  if jsonb_typeof(coalesce(p_teams,'[]'::jsonb))<>'array' then raise exception 'Lista de equipes inválida'; end if;
  update public.quiz_participants set team_id=null where room_id=p_room_id;
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
  perform private.notify_room(p_room_id);
  return public.admin_list_teams(p_room_id);
end $$;

create or replace function public.admin_list_teams(p_room_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v jsonb;
begin
  perform private.require_admin_capability('view');
  if not exists(select 1 from public.quiz_rooms r where r.id=p_room_id and r.created_by=auth.uid()) then raise exception 'Sala inválida'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'color',t.color,'icon',t.icon,'sort_order',t.sort_order) order by t.sort_order,t.name),'[]'::jsonb)
  into v from public.quiz_teams t where t.room_id=p_room_id;
  return v;
end $$;

create or replace function public.pro_player_ensure_team(p_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_part public.quiz_participants; v_team public.quiz_teams;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) and status<>'finished';
  if not found then raise exception 'Sala não encontrada'; end if;
  select * into v_part from public.quiz_participants where room_id=v_room.id and user_id=v_uid and not kicked for update;
  if not found then raise exception 'Participante não encontrado'; end if;
  if coalesce(v_room.settings->>'game_mode','classic')<>'teams' then
    return jsonb_build_object('team_id',null,'team_name',null,'mode','classic');
  end if;
  if not exists(select 1 from public.quiz_teams where room_id=v_room.id) then
    insert into public.quiz_teams(room_id,name,color,icon,sort_order) values
      (v_room.id,'Equipe Azul','#1976d2','●',0),
      (v_room.id,'Equipe Verde','#20a06c','●',1)
    on conflict(room_id,name) do nothing;
  end if;
  if v_part.team_id is null then
    select t.* into v_team
    from public.quiz_teams t
    left join lateral(select count(*) c from public.quiz_participants p where p.room_id=v_room.id and p.team_id=t.id and not p.kicked) pc on true
    where t.room_id=v_room.id
    order by pc.c asc,t.sort_order,t.name limit 1;
    update public.quiz_participants set team_id=v_team.id where id=v_part.id;
  else select * into v_team from public.quiz_teams where id=v_part.team_id; end if;
  perform private.notify_room(v_room.id);
  return jsonb_build_object('team_id',v_team.id,'team_name',v_team.name,'team_color',v_team.color,'team_icon',v_team.icon,'mode','teams');
end $$;

create or replace function public.pro_public_team_ranking(p_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_room uuid; v jsonb;
begin
  select id into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if v_room is null then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'team_id',x.id,'name',x.name,'color',x.color,'icon',x.icon,'points',x.points,'players',x.players
  ) order by x.points desc,x.sort_order,x.name),'[]'::jsonb) into v
  from (
    select t.id,t.name,t.color,t.icon,t.sort_order,coalesce(sum(p.total_points),0)::bigint points,count(p.id)::integer players
    from public.quiz_teams t left join public.quiz_participants p on p.team_id=t.id and not p.kicked
    where t.room_id=v_room group by t.id,t.name,t.color,t.icon,t.sort_order
  ) x;
  return v;
end $$;

revoke all on function public.admin_save_teams(uuid,jsonb),public.admin_list_teams(uuid) from public,anon;
grant execute on function public.admin_save_teams(uuid,jsonb),public.admin_list_teams(uuid) to authenticated;
revoke all on function public.pro_player_ensure_team(text),public.pro_public_team_ranking(text) from public;
grant execute on function public.pro_player_ensure_team(text),public.pro_public_team_ranking(text) to anon,authenticated;

-- -----------------------------------------------------------------------------
-- 3) Banco de perguntas profissional: mídia, tags, origem e tipo especial
-- -----------------------------------------------------------------------------
alter table public.quiz_questions
  add column if not exists media_type text not null default 'none',
  add column if not exists media_url text,
  add column if not exists media_caption text not null default '',
  add column if not exists special_type text not null default 'normal',
  add column if not exists tags jsonb not null default '[]'::jsonb,
  add column if not exists source_label text not null default '',
  add column if not exists starred boolean not null default false;

do $$ begin alter table public.quiz_questions add constraint quiz_questions_media_type_check check(media_type in ('none','image','audio','video')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.quiz_questions add constraint quiz_questions_special_type_check check(special_type in ('normal','double','lightning','tiebreaker','final','bonus')); exception when duplicate_object then null; end $$;

alter table public.quiz_room_queue
  add column if not exists media_type_snapshot text not null default 'none',
  add column if not exists media_url_snapshot text,
  add column if not exists media_caption_snapshot text not null default '',
  add column if not exists special_type_snapshot text not null default 'normal',
  add column if not exists tags_snapshot jsonb not null default '[]'::jsonb,
  add column if not exists source_label_snapshot text not null default '';

alter table public.quiz_rounds
  add column if not exists media_type_snapshot text not null default 'none',
  add column if not exists media_url_snapshot text,
  add column if not exists media_caption_snapshot text not null default '',
  add column if not exists special_type_snapshot text not null default 'normal',
  add column if not exists tags_snapshot jsonb not null default '[]'::jsonb,
  add column if not exists source_label_snapshot text not null default '';

create or replace function public.admin_update_question_pro(
  p_question_id uuid,p_media_type text,p_media_url text,p_media_caption text,
  p_special_type text,p_tags jsonb,p_source_label text,p_starred boolean
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_q public.quiz_questions; v_media text:=lower(coalesce(p_media_type,'none')); v_special text:=lower(coalesce(p_special_type,'normal')); v_url text;
begin
  perform private.require_admin_capability('edit');
  if v_media not in ('none','image','audio','video') then raise exception 'Tipo de mídia inválido'; end if;
  if v_special not in ('normal','double','lightning','tiebreaker','final','bonus') then raise exception 'Tipo especial inválido'; end if;
  v_url:=nullif(left(trim(coalesce(p_media_url,'')),1000),'');
  if v_url is not null and v_url !~ '^https://' then raise exception 'A mídia deve usar HTTPS'; end if;
  update public.quiz_questions set
    media_type=v_media,
    media_url=case when v_media='none' then null else v_url end,
    media_caption=left(trim(coalesce(p_media_caption,'')),240),
    special_type=v_special,
    tags=case when jsonb_typeof(coalesce(p_tags,'[]'::jsonb))='array' then coalesce(p_tags,'[]'::jsonb) else '[]'::jsonb end,
    source_label=left(trim(coalesce(p_source_label,'')),120),
    starred=coalesce(p_starred,false)
  where id=p_question_id and created_by=v_uid and active returning * into v_q;
  if not found then raise exception 'Pergunta não encontrada'; end if;
  return to_jsonb(v_q);
end $$;
revoke all on function public.admin_update_question_pro(uuid,text,text,text,text,jsonb,text,boolean) from public,anon;
grant execute on function public.admin_update_question_pro(uuid,text,text,text,text,jsonb,text,boolean) to authenticated;

-- Lista profissional substitui apenas a projeção; mantém o contrato antigo e adiciona campos.
create or replace function public.admin_list_question_bank(p_scope text default 'active')
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_result jsonb;v_scope text:=lower(coalesce(p_scope,'active')); begin
  perform private.require_admin_capability('view');
  if v_scope not in ('active','archived','all') then v_scope:='active'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'prompt',q.prompt,'question_type',q.question_type,'options',q.options,'points',q.points,'time_limit_seconds',q.time_limit_seconds,
    'correct_choice',k.correct_choice,'correct_number',k.correct_number,'archived',q.archived_at is not null,'archived_at',q.archived_at,'created_at',q.created_at,
    'category',q.category,'difficulty',q.difficulty,'score_enabled',q.score_enabled,'speed_bonus_pct',q.speed_bonus_pct,'is_tiebreaker',q.is_tiebreaker,
    'presenter_notes',q.presenter_notes,'use_count',q.use_count,'last_used_at',q.last_used_at,
    'media_type',q.media_type,'media_url',q.media_url,'media_caption',q.media_caption,'special_type',q.special_type,'tags',q.tags,'source_label',q.source_label,'starred',q.starred
  ) order by q.starred desc,q.created_at desc),'[]'::jsonb) into v_result
  from public.quiz_questions q join private.quiz_answer_keys k on k.question_id=q.id
  where q.active and q.created_by=v_uid and (v_scope='all' or (v_scope='active' and q.archived_at is null) or (v_scope='archived' and q.archived_at is not null));
  return v_result;
end $$;
revoke all on function public.admin_list_question_bank(text) from public,anon;
grant execute on function public.admin_list_question_bank(text) to authenticated;

-- Fila: executa o motor estável e completa os snapshots profissionais.
create or replace function public.admin_queue_question(p_room_id uuid,p_question_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_q public.quiz_questions;
begin
  perform private.require_admin_capability('present');
  perform private.require_live_control(p_room_id);
  v_id:=public.admin_queue_question_r28_impl(p_room_id,p_question_id);
  select * into v_q from public.quiz_questions where id=p_question_id;
  update public.quiz_room_queue set
    media_type_snapshot=v_q.media_type,media_url_snapshot=v_q.media_url,media_caption_snapshot=v_q.media_caption,
    special_type_snapshot=v_q.special_type,tags_snapshot=v_q.tags,source_label_snapshot=v_q.source_label,
    points_snapshot=case when v_q.special_type='double' then least(100000,v_q.points*2) else points_snapshot end,
    time_limit_snapshot=case when v_q.special_type='lightning' then least(time_limit_snapshot,15) else time_limit_snapshot end,
    is_tiebreaker_snapshot=case when v_q.special_type='tiebreaker' then true else is_tiebreaker_snapshot end,
    difficulty_snapshot=case when v_q.special_type='final' then 'final' else difficulty_snapshot end
  where id=v_id;
  return v_id;
end $$;

create or replace function public.admin_list_room_queue(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb; begin
  perform private.require_admin_capability('view');
  if not exists(select 1 from public.quiz_rooms r where r.id=p_room_id and r.created_by=auth.uid()) then raise exception 'Sala inválida'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',rq.id,'question_id',rq.question_id,'position',rq.position,'status',rq.status,'round_id',rq.round_id,'prompt',rq.prompt_snapshot,
    'question_type',rq.question_type_snapshot,'options',rq.options_snapshot,'points',rq.points_snapshot,'time_limit_seconds',rq.time_limit_snapshot,
    'category',rq.category_snapshot,'difficulty',rq.difficulty_snapshot,'score_enabled',rq.score_enabled_snapshot,'speed_bonus_pct',rq.speed_bonus_pct_snapshot,
    'is_tiebreaker',rq.is_tiebreaker_snapshot,'presenter_notes',rq.presenter_notes_snapshot,
    'media_type',rq.media_type_snapshot,'media_url',rq.media_url_snapshot,'media_caption',rq.media_caption_snapshot,
    'special_type',rq.special_type_snapshot,'tags',rq.tags_snapshot,'source_label',rq.source_label_snapshot
  ) order by rq.position,rq.added_at),'[]'::jsonb) into v_result from public.quiz_room_queue rq where rq.room_id=p_room_id;
  return v_result;
end $$;

-- Ao abrir um round, copia os snapshots profissionais da fila correspondente.
create or replace function public.admin_open_prepared_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb; v_round uuid;
begin
  perform private.require_admin_capability('present');
  perform private.require_live_control(p_room_id);
  v:=public.admin_open_prepared_round_r28_impl(p_room_id);
  begin v_round:=(v->'round'->>'id')::uuid; exception when others then v_round:=null; end;
  if v_round is not null then
    perform private.capture_round_eligibility(v_round);
    update public.quiz_rounds r set
      media_type_snapshot=q.media_type_snapshot,media_url_snapshot=q.media_url_snapshot,media_caption_snapshot=q.media_caption_snapshot,
      special_type_snapshot=q.special_type_snapshot,tags_snapshot=q.tags_snapshot,source_label_snapshot=q.source_label_snapshot
    from public.quiz_room_queue q where q.round_id=r.id and r.id=v_round;
  end if;
  return v;
end $$;

create or replace function public.admin_duplicate_question(p_question_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_new uuid;
begin
  perform private.require_admin_capability('edit');
  v_new:=public.admin_duplicate_question_r28_impl(p_question_id);
  update public.quiz_questions dst set
    media_type=src.media_type,media_url=src.media_url,media_caption=src.media_caption,special_type=src.special_type,
    tags=src.tags,source_label=src.source_label,starred=false
  from public.quiz_questions src where src.id=p_question_id and dst.id=v_new;
  return v_new;
end $$;

create or replace function public.get_round_extras_by_code(p_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_room public.quiz_rooms; v_round public.quiz_rounds;
begin
  select * into v_room from public.quiz_rooms where code=upper(trim(p_code)) order by created_at desc limit 1;
  if not found then return null; end if;
  select * into v_round from public.quiz_rounds where room_id=v_room.id order by round_no desc limit 1;
  return jsonb_build_object(
    'room_id',v_room.id,'code',v_room.code,'phase',v_room.phase,'settings',v_room.settings,'is_rehearsal',v_room.is_rehearsal,
    'round',case when v_round.id is null then null else jsonb_build_object(
      'id',v_round.id,'round_no',v_round.round_no,'media_type',v_round.media_type_snapshot,'media_url',v_round.media_url_snapshot,
      'media_caption',v_round.media_caption_snapshot,'special_type',v_round.special_type_snapshot,'tags',v_round.tags_snapshot,'source_label',v_round.source_label_snapshot
    ) end,
    'server_now',clock_timestamp()
  );
end $$;
revoke all on function public.get_round_extras_by_code(text) from public;
grant execute on function public.get_round_extras_by_code(text) to anon,authenticated;

revoke all on function public.admin_queue_question(uuid,uuid),public.admin_list_room_queue(uuid),public.admin_open_prepared_round(uuid),public.admin_duplicate_question(uuid) from public,anon;
grant execute on function public.admin_queue_question(uuid,uuid),public.admin_list_room_queue(uuid),public.admin_open_prepared_round(uuid),public.admin_duplicate_question(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 4) Importação profissional CSV/JSON -> JSONB normalizado
-- -----------------------------------------------------------------------------
create or replace function public.admin_import_questions_pro(p_questions jsonb,p_mode text default 'append')
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); x jsonb; v_id uuid; v_count integer:=0; v_mode text:=lower(coalesce(p_mode,'append')); v_opts jsonb; v_type text; v_correct_choice text; v_correct_number numeric;
begin
  perform private.require_admin_capability('edit');
  if jsonb_typeof(coalesce(p_questions,'[]'::jsonb))<>'array' then raise exception 'Lote inválido'; end if;
  if v_mode not in ('append','replace') then v_mode:='append'; end if;
  if jsonb_array_length(p_questions)>500 then raise exception 'Limite de 500 perguntas por lote'; end if;
  if v_mode='replace' then update public.quiz_questions set archived_at=clock_timestamp() where created_by=v_uid and active and archived_at is null; end if;
  for x in select value from jsonb_array_elements(p_questions) loop
    v_type:=lower(coalesce(x->>'question_type',x->>'type','choice'));
    v_opts:=case when v_type='choice' then x->'options' else null end;
    v_correct_choice:=case when v_type='choice' then upper(coalesce(x->>'correct_choice','')) else null end;
    begin v_correct_number:=case when v_type='numeric' then (x->>'correct_number')::numeric else null end; exception when others then v_correct_number:=null; end;
    v_id:=public.admin_create_question_v2_r28_impl(
      coalesce(x->>'prompt',''),v_type,v_opts,v_correct_choice,v_correct_number,
      coalesce((x->>'points')::integer,100),coalesce((x->>'time_limit_seconds')::integer,30)
    );
    perform public.admin_update_question_metadata_r28_impl(
      v_id,coalesce(x->>'category','Geral'),coalesce(x->>'difficulty','medio'),coalesce((x->>'score_enabled')::boolean,true),
      coalesce((x->>'speed_bonus_pct')::integer,0),coalesce((x->>'is_tiebreaker')::boolean,false),coalesce(x->>'presenter_notes','')
    );
    update public.quiz_questions set
      media_type=case when lower(coalesce(x->>'media_type','none')) in ('none','image','audio','video') then lower(coalesce(x->>'media_type','none')) else 'none' end,
      media_url=case when coalesce(x->>'media_url','') ~ '^https://' then left(x->>'media_url',1000) else null end,
      media_caption=left(coalesce(x->>'media_caption',''),240),
      special_type=case when lower(coalesce(x->>'special_type','normal')) in ('normal','double','lightning','tiebreaker','final','bonus') then lower(coalesce(x->>'special_type','normal')) else 'normal' end,
      tags=case when jsonb_typeof(coalesce(x->'tags','[]'::jsonb))='array' then coalesce(x->'tags','[]'::jsonb) else '[]'::jsonb end,
      source_label=left(coalesce(x->>'source_label',''),120),starred=coalesce((x->>'starred')::boolean,false)
    where id=v_id;
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('imported',v_count,'mode',v_mode);
end $$;
revoke all on function public.admin_import_questions_pro(jsonb,text) from public,anon;
grant execute on function public.admin_import_questions_pro(jsonb,text) to authenticated;

-- -----------------------------------------------------------------------------
-- 5) Dashboard pós-evento
-- -----------------------------------------------------------------------------
create or replace function public.admin_event_dashboard(p_room_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_room public.quiz_rooms; v_players jsonb; v_questions jsonb; v_fast jsonb; v_summary jsonb; v_teams jsonb;
begin
  perform private.require_admin_capability('view');
  select * into v_room from public.quiz_rooms where id=p_room_id and created_by=auth.uid();
  if not found then raise exception 'Sala não encontrada'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name,'points',p.total_points,'streak',p.best_streak,'team_id',p.team_id) order by p.total_points desc,p.joined_at),'[]'::jsonb)
    into v_players from public.quiz_participants p where p.room_id=p_room_id and not p.kicked;
  select coalesce(jsonb_agg(jsonb_build_object(
    'round_no',r.round_no,'prompt',r.prompt_snapshot,'category',r.category_snapshot,'difficulty',r.difficulty_snapshot,
    'answers',coalesce(r.answer_count_snapshot,0),'participants',(select count(*) from public.quiz_participants p where p.room_id=p_room_id and not p.kicked),
    'accuracy',case when r.question_type_snapshot='choice' then round(100.0*coalesce((select count(*) from public.quiz_answers a join private.quiz_round_answer_keys k on k.round_id=r.id where a.round_id=r.id and a.choice_value=k.correct_choice),0)/greatest(1,coalesce(r.answer_count_snapshot,0)),1) else null end,
    'avg_response_ms',(select round(avg(a.response_ms)) from public.quiz_answers a where a.round_id=r.id),
    'special_type',r.special_type_snapshot,'media_type',r.media_type_snapshot
  ) order by r.round_no),'[]'::jsonb) into v_questions from public.quiz_rounds r where r.room_id=p_room_id;
  select to_jsonb(x) into v_fast from (
    select p.display_name name,a.response_ms,r.round_no,r.prompt_snapshot prompt
    from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id join public.quiz_participants p on p.id=a.participant_id
    where r.room_id=p_room_id and a.awarded_points>0 order by a.response_ms asc limit 1
  ) x;
  select jsonb_build_object(
    'players',(select count(*) from public.quiz_participants p where p.room_id=p_room_id and not p.kicked),
    'rounds',(select count(*) from public.quiz_rounds r where r.room_id=p_room_id),
    'answers',(select count(*) from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id where r.room_id=p_room_id),
    'avg_response_ms',(select round(avg(a.response_ms)) from public.quiz_answers a join public.quiz_rounds r on r.id=a.round_id where r.room_id=p_room_id),
    'total_points',(select coalesce(sum(p.total_points),0) from public.quiz_participants p where p.room_id=p_room_id and not p.kicked)
  ) into v_summary;
  select coalesce(jsonb_agg(jsonb_build_object('team_id',t.id,'name',t.name,'color',t.color,'icon',t.icon,'points',coalesce(x.points,0),'players',coalesce(x.players,0)) order by coalesce(x.points,0) desc,t.sort_order),'[]'::jsonb)
    into v_teams from public.quiz_teams t left join lateral(select sum(p.total_points)::bigint points,count(*)::integer players from public.quiz_participants p where p.team_id=t.id and not p.kicked)x on true where t.room_id=p_room_id;
  return jsonb_build_object('room',jsonb_build_object('id',v_room.id,'code',v_room.code,'title',v_room.title,'phase',v_room.phase,'settings',v_room.settings,'is_rehearsal',v_room.is_rehearsal),
    'summary',v_summary,'players',v_players,'questions',v_questions,'fastest_correct',v_fast,'teams',v_teams,'generated_at',clock_timestamp());
end $$;
revoke all on function public.admin_event_dashboard(uuid) from public,anon;
grant execute on function public.admin_event_dashboard(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 6) Enforcements de papel nos principais caminhos existentes
-- -----------------------------------------------------------------------------
create or replace function private.require_active_room_control_if_any()
returns void language plpgsql security definer set search_path='' as $$
declare v_room uuid; v_role text:=private.admin_role(auth.uid());
begin
  if v_role='editor' then return; end if;
  if v_role not in ('owner','presenter') then raise exception 'Seu perfil não pode executar esta ação'; end if;
  select id into v_room from public.quiz_rooms where created_by=auth.uid() and status<>'finished' and phase<>'finished' order by created_at desc limit 1;
  if v_room is not null then perform private.require_live_control(v_room); end if;
end $$;
revoke all on function private.require_active_room_control_if_any() from public,anon,authenticated;

create or replace function public.admin_create_question_v2(p_prompt text,p_type text,p_options jsonb,p_correct_choice text,p_correct_number numeric,p_points integer,p_time_limit integer)
returns uuid language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('edit'); perform private.require_active_room_control_if_any(); return public.admin_create_question_v2_r28_impl(p_prompt,p_type,p_options,p_correct_choice,p_correct_number,p_points,p_time_limit); end $$;
create or replace function public.admin_update_question_v3(p_question_id uuid,p_prompt text,p_type text,p_options jsonb,p_correct_choice text,p_correct_number numeric,p_points integer,p_time_limit integer,p_category text,p_difficulty text,p_score_enabled boolean,p_speed_bonus_pct integer,p_is_tiebreaker boolean,p_presenter_notes text)
returns uuid language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('edit'); perform private.require_active_room_control_if_any(); return public.admin_update_question_v3_r28_impl(p_question_id,p_prompt,p_type,p_options,p_correct_choice,p_correct_number,p_points,p_time_limit,p_category,p_difficulty,p_score_enabled,p_speed_bonus_pct,p_is_tiebreaker,p_presenter_notes); end $$;
create or replace function public.admin_import_questions_v2(p_questions jsonb,p_mode text default 'append')
returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('edit'); perform private.require_active_room_control_if_any(); return public.admin_import_questions_v2_r28_impl(p_questions,p_mode); end $$;
create or replace function public.admin_set_question_archived(p_question_id uuid,p_archived boolean)
returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('edit'); perform private.require_active_room_control_if_any(); perform public.admin_set_question_archived_r28_impl(p_question_id,p_archived); end $$;
create or replace function public.admin_update_question_metadata(p_question_id uuid,p_category text,p_difficulty text,p_score_enabled boolean,p_speed_bonus_pct integer,p_is_tiebreaker boolean,p_presenter_notes text)
returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('edit'); perform private.require_active_room_control_if_any(); perform public.admin_update_question_metadata_r28_impl(p_question_id,p_category,p_difficulty,p_score_enabled,p_speed_bonus_pct,p_is_tiebreaker,p_presenter_notes); end $$;

-- Papel administrativo aplicado aos caminhos mutáveis do motor estável.
create or replace function public.admin_update_planned_rounds(p_room_id uuid,p_planned_rounds integer) returns integer language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_update_planned_rounds_r28_impl(p_room_id,p_planned_rounds); end $$;
create or replace function public.admin_remove_queue_item(p_room_id uuid,p_queue_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); perform public.admin_remove_queue_item_r28_impl(p_room_id,p_queue_id); end $$;
create or replace function public.admin_move_queue_item(p_room_id uuid,p_queue_id uuid,p_direction integer) returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); perform public.admin_move_queue_item_r28_impl(p_room_id,p_queue_id,p_direction); end $$;
create or replace function public.admin_prepare_next_round(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_prepare_next_round_r28_impl(p_room_id); end $$;
create or replace function public.admin_close_and_score_round(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_close_and_score_round_r28_impl(p_room_id); end $$;
create or replace function public.admin_pause_quiz(p_room_id uuid,p_pause boolean) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_pause_quiz_r28_impl(p_room_id,p_pause); end $$;
create or replace function public.admin_extend_round(p_room_id uuid,p_seconds integer) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_extend_round_r28_impl(p_room_id,p_seconds); end $$;
create or replace function public.admin_annul_round(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_annul_round_r28_impl(p_room_id); end $$;
create or replace function public.admin_regrade_round(p_room_id uuid,p_correct_choice text default null,p_correct_number numeric default null) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_regrade_round_r28_impl(p_room_id,p_correct_choice,p_correct_number); end $$;
create or replace function public.admin_kick_participant(p_room_id uuid,p_participant_id uuid,p_block boolean default true) returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); perform public.admin_kick_participant_r28_impl(p_room_id,p_participant_id,p_block); end $$;
create or replace function public.admin_restart_quiz(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_restart_quiz_r28_impl(p_room_id); end $$;
create or replace function public.admin_shuffle_queue(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_shuffle_queue_r28_impl(p_room_id); end $$;
create or replace function public.admin_set_randomize_queue(p_room_id uuid,p_enabled boolean) returns boolean language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_set_randomize_queue_r28_impl(p_room_id,p_enabled); end $$;
create or replace function public.admin_update_room_settings(p_room_id uuid,p_patch jsonb) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_update_room_settings_r28_impl(p_room_id,p_patch); end $$;
create or replace function public.admin_set_reveal_stage(p_room_id uuid,p_stage text) returns void language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); perform public.admin_set_reveal_stage_r28_impl(p_room_id,p_stage); end $$;
create or replace function public.admin_set_final_show_stage(p_room_id uuid,p_stage text) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_set_final_show_stage_r28_impl(p_room_id,p_stage); end $$;
create or replace function public.admin_create_remote_pairing(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); return public.admin_create_remote_pairing_r28_impl(p_room_id); end $$;
create or replace function public.admin_start_quiz(p_room_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ declare v jsonb; begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); perform set_config('quiz.controller_internal','on',true); begin v:=public.admin_start_quiz_r28_impl(p_room_id); exception when others then perform set_config('quiz.controller_internal','off',true); raise; end; perform set_config('quiz.controller_internal','off',true); return v; end $$;
create or replace function public.admin_create_room_v4(p_title text,p_planned_rounds integer) returns jsonb language plpgsql security definer set search_path='' as $$ declare v jsonb; begin perform private.require_admin_capability('present'); perform private.require_active_room_control_if_any(); perform set_config('quiz.controller_internal','on',true); begin v:=public.admin_create_room_v4_r28_impl(p_title,p_planned_rounds); exception when others then perform set_config('quiz.controller_internal','off',true); raise; end; perform set_config('quiz.controller_internal','off',true); return v; end $$;
create or replace function public.admin_create_from_template(p_template_id uuid,p_title text default null) returns jsonb language plpgsql security definer set search_path='' as $$ declare v jsonb; begin perform private.require_admin_capability('present'); perform private.require_active_room_control_if_any(); perform set_config('quiz.controller_internal','on',true); begin v:=public.admin_create_from_template_r28_impl(p_template_id,p_title); exception when others then perform set_config('quiz.controller_internal','off',true); raise; end; perform set_config('quiz.controller_internal','off',true); return v; end $$;
create or replace function public.admin_duplicate_room(p_room_id uuid,p_title text default null) returns jsonb language plpgsql security definer set search_path='' as $$ declare v jsonb; begin perform private.require_admin_capability('present'); perform private.require_live_control(p_room_id); perform set_config('quiz.controller_internal','on',true); begin v:=public.admin_duplicate_room_r28_impl(p_room_id,p_title); exception when others then perform set_config('quiz.controller_internal','off',true); raise; end; perform set_config('quiz.controller_internal','off',true); return v; end $$;
create or replace function public.admin_save_template(p_room_id uuid,p_name text) returns uuid language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('edit'); return public.admin_save_template_r28_impl(p_room_id,p_name); end $$;
create or replace function public.admin_revoke_remote_devices() returns integer language plpgsql security definer set search_path='' as $$ begin perform private.require_admin_capability('present'); return public.admin_revoke_remote_devices_r28_impl(); end $$;

-- Evita que perfis somente leitura/editor tomem a lease de apresentação.
create or replace function public.admin_claim_controller(p_room_id uuid,p_device_token text,p_device_label text default 'Painel ADM',p_force boolean default false)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_room public.quiz_rooms; v_lease public.quiz_admin_control_leases; v_hash text; v_now timestamptz:=clock_timestamp(); v_sid text:=private.current_auth_session_id();
begin
  perform private.require_admin_capability('present');
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
end $$;

-- -----------------------------------------------------------------------------
-- 7) Handshake do schema 041
-- -----------------------------------------------------------------------------
create or replace function public.get_quiz_backend_meta()
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'schema_version',41,
    'release','3.68-r46',
    'min_frontend_build','3.68-r46',
    'features',jsonb_build_array(
      'secure_display_pairing','controller_backend_guard','round_eligibility_snapshot','display_state_privacy','build_handshake',
      'avatar_catalog_31','gameshow_pro','game_modes','teams','question_media','special_questions','professional_question_bank',
      'csv_json_import','post_event_dashboard','audio_profiles','rehearsal_tools','admin_roles','event_branding'
    ),
    'server_now',clock_timestamp()
  );
$$;
revoke all on function public.get_quiz_backend_meta() from public;
grant execute on function public.get_quiz_backend_meta() to anon,authenticated;
