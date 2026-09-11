-- QuizRounds v3.64 — correção definitiva de permissão no Storage de logos
-- Evita qualquer chamada de private.is_admin() durante as policies do bucket quiz-logos.
-- A autorização continua exigindo usuário autenticado presente em public.quiz_admins
-- e restringe cada administrador à própria pasta UUID.

create or replace function private.is_current_quiz_admin()
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.quiz_admins a
    where a.user_id = (select auth.uid())
  )
$$;

revoke all on function private.is_current_quiz_admin() from public;
revoke all on function private.is_current_quiz_admin() from anon;
grant usage on schema private to authenticated;
grant execute on function private.is_current_quiz_admin() to authenticated;

drop policy if exists quiz_logos_admin_insert on storage.objects;
create policy quiz_logos_admin_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'quiz-logos'
  and (select private.is_current_quiz_admin())
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists quiz_logos_admin_update on storage.objects;
create policy quiz_logos_admin_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'quiz-logos'
  and (select private.is_current_quiz_admin())
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'quiz-logos'
  and (select private.is_current_quiz_admin())
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists quiz_logos_admin_delete on storage.objects;
create policy quiz_logos_admin_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'quiz-logos'
  and (select private.is_current_quiz_admin())
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
