-- QuizRounds v3.18 — catálogo ampliado de avatares.
-- Mantém todas as chaves antigas e adiciona animais, pessoas e anime genérico masculino/feminino.

create or replace function private.normalize_avatar_key(p_key text)
returns text
language sql
immutable
security definer
set search_path=''
as $$
  select case
    when lower(coalesce(trim(p_key),'')) = any(array['fox','cat','panda','lion','frog','unicorn','shark','owl','dog','rabbit','tiger','bear','koala','monkey','penguin','wolf','man_classic','man_beard','man_curly','man_blond','man_redhair','man_glasses','man_cap','boy','woman_classic','woman_curly','woman_blond','woman_redhair','woman_glasses','woman_hat','girl','princess','anime_hero','anime_blue','anime_fire','anime_ninja','anime_magic','anime_pink','anime_bluegirl','anime_star','robot','astro','ninja','alien','wizard','fairy','pirate','detective']::text[])
      then lower(trim(p_key))
    else 'robot'
  end
$$;
revoke all on function private.normalize_avatar_key(text) from public;
