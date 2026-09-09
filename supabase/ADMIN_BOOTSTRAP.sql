-- Execute no SQL Editor do Supabase depois de criar os dois usuários administradores em Authentication > Users.

insert into public.quiz_admins(user_id)
select id from auth.users where email='solloleao@outlook.com.br'
on conflict(user_id) do nothing;

insert into public.quiz_admins(user_id)
select id from auth.users where email='galaxyygui@gmail.com'
on conflict(user_id) do nothing;
