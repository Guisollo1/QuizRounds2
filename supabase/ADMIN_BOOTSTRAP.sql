-- Execute no SQL Editor do Supabase depois de criar o usuário administrador em Authentication > Users.
-- Substitua o e-mail abaixo pelo e-mail real do administrador.
insert into public.quiz_admins(user_id)
select id from auth.users where email='ADMIN@EXEMPLO.COM'
on conflict(user_id) do nothing;
