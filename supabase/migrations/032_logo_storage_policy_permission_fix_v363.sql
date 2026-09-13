-- QuizRounds v3.63 — correção de permissão no upload de logos
-- Root cause: as policies do Storage chamavam private.is_admin(auth.uid()) diretamente.
-- O papel authenticated não possui USAGE no schema private nem EXECUTE nessa função, por design.
-- A policy agora usa public.is_quiz_admin(), função SECURITY DEFINER já autorizada para authenticated,
-- preservando o isolamento por pasta UUID do administrador.

drop policy if exists quiz_logos_admin_insert on storage.objects;
create policy quiz_logos_admin_insert
on storage.objects
for insert
to authenticated
with check(
  bucket_id='quiz-logos'
  and (select public.is_quiz_admin())
  and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists quiz_logos_admin_update on storage.objects;
create policy quiz_logos_admin_update
on storage.objects
for update
to authenticated
using(
  bucket_id='quiz-logos'
  and (select public.is_quiz_admin())
  and (storage.foldername(name))[1]=auth.uid()::text
)
with check(
  bucket_id='quiz-logos'
  and (select public.is_quiz_admin())
  and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists quiz_logos_admin_delete on storage.objects;
create policy quiz_logos_admin_delete
on storage.objects
for delete
to authenticated
using(
  bucket_id='quiz-logos'
  and (select public.is_quiz_admin())
  and (storage.foldername(name))[1]=auth.uid()::text
);
