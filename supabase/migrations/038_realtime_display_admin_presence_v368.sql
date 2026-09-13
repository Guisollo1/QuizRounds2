-- QuizRounds v3.68 / r26
-- Corrige a escrita de Presence no canal privado para telão e painéis ADM.
-- A política anterior aceitava somente participant, embora a leitura já reconhecesse
-- participant/admin/display. Isso fazia channel.track({kind:'display'}) falhar e o
-- controle remoto exibir "Telão não detectado" mesmo com o display aberto.

drop policy if exists quiz_realtime_presence_write on realtime.messages;
create policy quiz_realtime_presence_write
on realtime.messages for insert to authenticated
with check (
  realtime.messages.extension='presence'
  and exists (
    select 1
    from public.quiz_realtime_memberships m
    where m.user_id=(select auth.uid())
      and m.role in ('participant','admin','display')
      and ('quiz:'||m.room_id::text)=(select realtime.topic())
  )
);
