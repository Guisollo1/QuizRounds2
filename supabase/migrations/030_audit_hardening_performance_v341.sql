-- QuizRounds v3.41 — hardening pós-auditoria
-- 1) remove execução anônima de RPCs administrativas
-- 2) mantém execução autenticada; cada RPC continua validando private.is_admin(auth.uid())
-- 3) adiciona índices para FKs apontadas pelo advisor
-- 4) otimiza admin_list_participants
-- 5) restringe gravação de logos à pasta do próprio administrador

-- RPCs administrativas: não devem ser invocáveis pela role anon/PUBLIC.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and (left(p.proname,6)='admin_' or p.proname='is_quiz_admin')
  loop
    execute format('revoke execute on function %s from public, anon', r.signature);
    execute format('grant execute on function %s to authenticated', r.signature);
  end loop;
end $$;

-- Índices de FKs / caminhos quentes.
create index if not exists quiz_admin_control_leases_owner_user_idx on public.quiz_admin_control_leases(owner_user_id);
create index if not exists quiz_admin_remote_devices_room_idx on public.quiz_admin_remote_devices(paired_from_room_id);
create index if not exists quiz_admin_remote_pairings_room_idx on public.quiz_admin_remote_pairings(room_id);
create index if not exists quiz_answers_participant_idx on public.quiz_answers(participant_id);
create index if not exists quiz_audit_log_actor_idx on public.quiz_audit_log(actor_user_id);
create index if not exists quiz_event_templates_created_by_idx on public.quiz_event_templates(created_by);
create index if not exists quiz_participants_user_idx on public.quiz_participants(user_id);
create index if not exists quiz_question_collections_created_by_idx on public.quiz_question_collections(created_by);
create index if not exists quiz_room_bans_user_idx on public.quiz_room_bans(user_id);
create index if not exists quiz_room_queue_question_idx on public.quiz_room_queue(question_id);
create index if not exists quiz_room_queue_round_idx on public.quiz_room_queue(round_id);
create index if not exists quiz_rooms_created_by_idx on public.quiz_rooms(created_by);
create index if not exists quiz_rounds_question_idx on public.quiz_rounds(question_id);

-- Índices compostos para telas ao vivo e estatísticas de participantes.
create index if not exists quiz_rounds_room_status_idx on public.quiz_rounds(room_id,status,id);
create index if not exists quiz_answers_participant_round_idx on public.quiz_answers(participant_id,round_id);
create index if not exists quiz_participants_room_seen_idx on public.quiz_participants(room_id,last_seen_at desc) where not kicked;

-- Evita subqueries correlacionadas repetidas por participante.
create or replace function public.admin_list_participants(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_result jsonb;
begin
  if not private.is_admin(v_uid) then
    raise exception 'Acesso negado';
  end if;

  with closed_rounds as (
    select count(*)::int as total
    from public.quiz_rounds
    where room_id=p_room_id and status='closed'
  ), answer_counts as (
    select a.participant_id,count(*)::int as answer_count
    from public.quiz_answers a
    join public.quiz_rounds r on r.id=a.round_id
    where r.room_id=p_room_id
    group by a.participant_id
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',p.id,
      'user_id',p.user_id,
      'display_name',p.display_name,
      'avatar_key',p.avatar_key,
      'total_points',p.total_points,
      'ready',p.ready,
      'kicked',p.kicked,
      'last_seen_at',p.last_seen_at,
      'current_streak',p.current_streak,
      'best_streak',p.best_streak,
      'answer_count',coalesce(ac.answer_count,0),
      'missed_count',greatest(0,cr.total-coalesce(ac.answer_count,0))
    ) order by p.total_points desc,p.joined_at,p.id
  ),'[]'::jsonb)
  into v_result
  from public.quiz_participants p
  cross join closed_rounds cr
  left join answer_counts ac on ac.participant_id=p.id
  where p.room_id=p_room_id;

  return v_result;
end $$;

revoke all on function public.admin_list_participants(uuid) from public, anon;
grant execute on function public.admin_list_participants(uuid) to authenticated;

-- Storage: qualquer administrador pode ser válido, mas só manipula objetos sob sua própria pasta UUID.
drop policy if exists quiz_logos_admin_insert on storage.objects;
create policy quiz_logos_admin_insert
on storage.objects
for insert
to authenticated
with check(
  bucket_id='quiz-logos'
  and private.is_admin(auth.uid())
  and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists quiz_logos_admin_update on storage.objects;
create policy quiz_logos_admin_update
on storage.objects
for update
to authenticated
using(
  bucket_id='quiz-logos'
  and private.is_admin(auth.uid())
  and (storage.foldername(name))[1]=auth.uid()::text
)
with check(
  bucket_id='quiz-logos'
  and private.is_admin(auth.uid())
  and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists quiz_logos_admin_delete on storage.objects;
create policy quiz_logos_admin_delete
on storage.objects
for delete
to authenticated
using(
  bucket_id='quiz-logos'
  and private.is_admin(auth.uid())
  and (storage.foldername(name))[1]=auth.uid()::text
);
