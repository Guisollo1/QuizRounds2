-- QuizRounds v3.67 / r25
-- Auditoria profunda: integridade de salas/rounds e ranking persistente no jogador.

-- 1) Corrige salas históricas antigas que permaneceram ativas apesar de já existir
-- uma sala mais nova do mesmo administrador. Antes de encerrá-las, anula qualquer
-- round ainda aberto para não deixar estado contraditório.
with stale_rooms as (
  select r.id
  from public.quiz_rooms r
  where r.status <> 'finished'
    and exists (
      select 1
      from public.quiz_rooms newer
      where newer.created_by = r.created_by
        and newer.created_at > r.created_at
    )
)
update public.quiz_rounds r
set status = 'closed',
    closed_at = coalesce(r.closed_at, clock_timestamp()),
    closes_at = least(coalesce(r.closes_at, clock_timestamp()), clock_timestamp()),
    annulled = true,
    result_locked = true,
    result_text = coalesce(nullif(r.result_text, ''), 'Round encerrado automaticamente por correção de integridade.')
where r.status = 'open'
  and r.room_id in (select id from stale_rooms);

with stale_rooms as (
  select r.id
  from public.quiz_rooms r
  where r.status <> 'finished'
    and exists (
      select 1
      from public.quiz_rooms newer
      where newer.created_by = r.created_by
        and newer.created_at > r.created_at
    )
)
update public.quiz_rooms r
set status = 'finished',
    game_status = 'finished',
    phase = 'finished',
    finished_at = coalesce(r.finished_at, clock_timestamp()),
    prepared_queue_id = null,
    prepared_until = null
where r.id in (select id from stale_rooms);

-- 2) Corrige qualquer round aberto cuja sala já não esteja aceitando respostas.
update public.quiz_rounds r
set status = 'closed',
    closed_at = coalesce(r.closed_at, clock_timestamp()),
    closes_at = least(coalesce(r.closes_at, clock_timestamp()), clock_timestamp()),
    annulled = true,
    result_locked = true,
    result_text = coalesce(nullif(r.result_text, ''), 'Round encerrado automaticamente por correção de integridade.')
from public.quiz_rooms q
where q.id = r.room_id
  and r.status = 'open'
  and q.phase <> 'question_open';

-- 3) Ao criar uma nova sala, encerra de forma transacional qualquer round aberto
-- da sala substituída. Isso impede resíduos que poderiam reaparecer no remoto.
create or replace function public.admin_create_room_v3(p_title text, p_planned_rounds integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.quiz_rooms;
  v_old record;
  v_code text;
  v_rounds integer := greatest(1, least(200, coalesce(p_planned_rounds, 10)));
begin
  if not private.is_admin(v_uid) then
    raise exception 'Acesso negado';
  end if;

  for v_old in
    select r.id, r.code
    from public.quiz_rooms r
    where r.created_by = v_uid
      and r.status <> 'finished'
    order by r.created_at desc
    for update
  loop
    update public.quiz_rounds
       set status = 'closed',
           closed_at = coalesce(closed_at, clock_timestamp()),
           closes_at = least(coalesce(closes_at, clock_timestamp()), clock_timestamp()),
           annulled = true,
           result_locked = true,
           result_text = coalesce(nullif(result_text, ''), 'Round encerrado porque uma nova sala foi criada.')
     where room_id = v_old.id
       and status = 'open';

    update public.quiz_rooms
       set status = 'finished',
           game_status = 'finished',
           phase = 'finished',
           finished_at = coalesce(finished_at, clock_timestamp()),
           prepared_queue_id = null,
           prepared_until = null
     where id = v_old.id;

    perform private.audit_event(
      v_old.id,
      v_uid,
      'room_superseded',
      'room',
      v_old.id,
      jsonb_build_object('reason', 'new_room_created')
    );
    perform private.notify_room(v_old.id);
  end loop;

  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists(select 1 from public.quiz_rooms where code = v_code);
  end loop;

  insert into public.quiz_rooms(code, title, created_by, status, planned_rounds, game_status, phase)
  values(v_code, coalesce(nullif(trim(p_title), ''), 'Quiz ao vivo'), v_uid, 'live', v_rounds, 'lobby', 'lobby')
  returning * into v_room;

  insert into public.quiz_realtime_memberships(user_id, room_id, role)
  values(v_uid, v_room.id, 'admin')
  on conflict do nothing;

  perform private.audit_event(
    v_room.id,
    v_uid,
    'room_created',
    'room',
    v_room.id,
    jsonb_build_object('planned_rounds', v_rounds, 'title', v_room.title)
  );
  perform private.publish_room_event(v_room.id, 'room_created', '{}'::jsonb);

  select * into v_room from public.quiz_rooms where id = v_room.id;
  return to_jsonb(v_room);
end
$$;

-- 4) Estado do jogador: mantém visível a última classificação já revelada
-- enquanto uma nova pergunta está aberta, sem antecipar o ranking do round atual.
create or replace function public.get_game_state(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_part public.quiz_participants;
  v_room public.quiz_rooms;
  v_round public.quiz_rounds;
  v_my public.quiz_answers;
  v_round_json jsonb;
  v_rank jsonb := '[]'::jsonb;
  v_now timestamptz := clock_timestamp();
  v_pos int;
  v_missed int := 0;
begin
  select * into v_part
  from public.quiz_participants
  where room_id = p_room_id
    and user_id = v_uid;

  if not found or v_part.kicked then
    raise exception 'Participante não pertence à sala';
  end if;

  select * into v_room
  from public.quiz_rooms
  where id = p_room_id;

  if not found then
    raise exception 'Sala não encontrada';
  end if;

  select * into v_round
  from public.quiz_rounds
  where room_id = p_room_id
  order by round_no desc
  limit 1;

  if found then
    select * into v_my
    from public.quiz_answers
    where round_id = v_round.id
      and participant_id = v_part.id;

    v_round_json := jsonb_build_object(
      'id', v_round.id,
      'round_no', v_round.round_no,
      'status', v_round.status,
      'opened_at', v_round.opened_at,
      'closes_at', v_round.closes_at,
      'time_limit_seconds', v_round.time_limit_seconds,
      'accepting_responses', (v_room.phase = 'question_open' and v_round.status = 'open' and v_now <= v_round.closes_at),
      'prompt', v_round.prompt_snapshot,
      'question_type', v_round.question_type_snapshot,
      'options', coalesce(v_round.options_snapshot, '[]'::jsonb),
      'points', v_round.points_snapshot,
      'category', v_round.category_snapshot,
      'difficulty', v_round.difficulty_snapshot,
      'score_enabled', v_round.score_enabled_snapshot,
      'is_tiebreaker', v_round.is_tiebreaker_snapshot,
      'my_answer', case when v_my.id is null then null else to_jsonb(v_my) end,
      'result_text', case when v_round.status = 'closed' and v_room.reveal_stage in ('answer','distribution','ranking','final') then v_round.result_text else null end,
      'distribution', case when v_room.reveal_stage in ('distribution','ranking','final') then v_round.distribution_snapshot else null end,
      'movers', case when v_room.reveal_stage in ('ranking','final') then v_round.ranking_movers_snapshot else null end
    );
  else
    v_round_json := null;
  end if;

  if v_room.phase = 'lobby' then
    v_rank := '[]'::jsonb;
  elsif v_room.phase = 'finished' then
    v_rank := v_room.final_ranking_snapshot;
    if v_rank is null then
      select r.ranking_snapshot into v_rank
      from public.quiz_rounds r
      where r.room_id = p_room_id
        and r.status = 'closed'
        and not r.annulled
        and r.ranking_snapshot is not null
      order by r.round_no desc
      limit 1;
    end if;
    v_rank := coalesce(v_rank, '[]'::jsonb);
  elsif v_room.phase = 'result' and v_room.reveal_stage in ('ranking','final') then
    v_rank := coalesce(v_round.ranking_snapshot, '[]'::jsonb);
  elsif v_room.phase = 'result' then
    -- O round atual já foi fechado, mas o novo ranking ainda não foi revelado.
    -- Exibe somente a última classificação de um round anterior.
    select r.ranking_snapshot into v_rank
    from public.quiz_rounds r
    where r.room_id = p_room_id
      and r.status = 'closed'
      and not r.annulled
      and r.ranking_snapshot is not null
      and (v_round.id is null or r.round_no < v_round.round_no)
    order by r.round_no desc
    limit 1;
    v_rank := coalesce(v_rank, '[]'::jsonb);
  else
    -- Pergunta aberta, preparação ou pausa: conserva a última classificação
    -- de um round fechado. O round aberto nunca possui ranking visível aqui.
    select r.ranking_snapshot into v_rank
    from public.quiz_rounds r
    where r.room_id = p_room_id
      and r.status = 'closed'
      and not r.annulled
      and r.ranking_snapshot is not null
    order by r.round_no desc
    limit 1;
    v_rank := coalesce(v_rank, '[]'::jsonb);
  end if;

  select ordinality::int into v_pos
  from jsonb_array_elements(coalesce(v_rank, '[]'::jsonb)) with ordinality
  where value->>'participant_id' = v_part.id::text
  limit 1;

  select count(*) into v_missed
  from public.quiz_rounds r
  where r.room_id = p_room_id
    and r.status = 'closed'
    and not r.annulled
    and not exists(
      select 1
      from public.quiz_answers a
      where a.round_id = r.id
        and a.participant_id = v_part.id
    );

  return jsonb_build_object(
    'room', jsonb_build_object(
      'id', v_room.id,
      'code', v_room.code,
      'title', v_room.title,
      'planned_rounds', v_room.planned_rounds,
      'phase', v_room.phase,
      'state_version', v_room.state_version,
      'generation', v_room.game_generation,
      'settings', v_room.settings,
      'theme', v_room.theme_preset,
      'logo_url', v_room.logo_url,
      'prepared_until', v_room.prepared_until,
      'reveal_stage', v_room.reveal_stage
    ),
    'round', v_round_json,
    'ranking', coalesce(v_rank, '[]'::jsonb),
    'participant', jsonb_build_object(
      'id', v_part.id,
      'display_name', v_part.display_name,
      'total_points', v_part.total_points,
      'current_streak', v_part.current_streak,
      'best_streak', v_part.best_streak,
      'position', v_pos,
      'ready', v_part.ready,
      'missed_rounds', v_missed
    ),
    'server_now', v_now
  );
end
$$;

revoke all on function public.get_game_state(uuid) from public;
revoke all on function public.get_game_state(uuid) from anon;
grant execute on function public.get_game_state(uuid) to authenticated;

revoke all on function public.admin_create_room_v3(text, integer) from public;
revoke all on function public.admin_create_room_v3(text, integer) from anon;
grant execute on function public.admin_create_room_v3(text, integer) to authenticated;
