-- QuizRounds v3.40 — upload seguro de logos do evento
-- Bucket público apenas para leitura da imagem; gravação restrita a administradores autenticados.

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'quiz-logos',
  'quiz-logos',
  true,
  5242880,
  array['image/png','image/jpeg','image/webp']::text[]
)
on conflict(id) do update set
  public=excluded.public,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists quiz_logos_admin_insert on storage.objects;
create policy quiz_logos_admin_insert
on storage.objects
for insert
to authenticated
with check(bucket_id='quiz-logos' and private.is_admin(auth.uid()));

drop policy if exists quiz_logos_admin_update on storage.objects;
create policy quiz_logos_admin_update
on storage.objects
for update
to authenticated
using(bucket_id='quiz-logos' and private.is_admin(auth.uid()))
with check(bucket_id='quiz-logos' and private.is_admin(auth.uid()));

drop policy if exists quiz_logos_admin_delete on storage.objects;
create policy quiz_logos_admin_delete
on storage.objects
for delete
to authenticated
using(bucket_id='quiz-logos' and private.is_admin(auth.uid()));
