-- QuizRounds v3.68 / r30 — catálogo completo de 31 avatares no Supabase.
-- Preserva todas as chaves legadas e adiciona as chaves canônicas do pacote de avatares r37d.

create or replace function private.normalize_avatar_key(p_key text)
returns text
language sql
immutable
security definer
set search_path=''
as $$
  select case
    when lower(coalesce(trim(p_key),'')) = any(array['scientist_m','scientist_f','chemist_m','chemist_f','cleanroom_m','cleanroom_f','oil_ops_m','oil_ops_f','oil_ops_green_m','oil_ops_green_f','oil_maint_m','oil_maint_f','labcoat_white_m','labcoat_white_f','labcoat_blue_m','labcoat_blue_f','labcoat_gray_m','labcoat_gray_f','jumpsuit_orange_m','jumpsuit_orange_f','jumpsuit_blue_m','jumpsuit_blue_f','jumpsuit_orange_green_m','jumpsuit_orange_green_f','chem_protect_white_m','chem_protect_white_f','social_business_m','social_business_f','executive_alt_m','executive_alt_f','et_skunk','fox','cat','panda','lion','frog','unicorn','shark','owl','dog','rabbit','tiger','bear','koala','monkey','penguin','wolf','man_classic','man_beard','man_curly','man_blond','man_redhair','man_glasses','man_cap','boy','woman_classic','woman_curly','woman_blond','woman_redhair','woman_glasses','woman_hat','girl','princess','anime_hero','anime_blue','anime_fire','anime_ninja','anime_magic','anime_pink','anime_bluegirl','anime_star','robot','astro','ninja','alien','wizard','fairy','pirate','detective']::text[])
      then lower(trim(p_key))
    else 'scientist_m'
  end
$$;
revoke all on function private.normalize_avatar_key(text) from public;

create or replace function public.get_quiz_backend_meta()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select jsonb_build_object(
    'schema_version',40,
    'release','3.68-r30',
    'min_frontend_build','3.68-r30',
    'features',jsonb_build_array(
      'secure_display_pairing','controller_backend_guard','round_eligibility_snapshot',
      'display_state_privacy','logo_reference_guard','build_handshake',
      'avatar_catalog_31','avatar_canonical_keys','lobby_map_31_avatars'
    ),
    'server_now',clock_timestamp()
  );
$$;
revoke all on function public.get_quiz_backend_meta() from public;
grant execute on function public.get_quiz_backend_meta() to anon,authenticated;
