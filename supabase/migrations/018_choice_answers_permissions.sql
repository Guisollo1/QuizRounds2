-- QuizRounds v3.30
-- RPCs administrativos tocados pela compatibilidade A-E: somente authenticated.
revoke all on function public.admin_create_question_v2(text,text,jsonb,text,numeric,integer,integer) from public, anon;
grant execute on function public.admin_create_question_v2(text,text,jsonb,text,numeric,integer,integer) to authenticated;

revoke all on function public.admin_update_question_v3(uuid,text,text,jsonb,text,numeric,integer,integer,text,text,boolean,integer,boolean,text) from public, anon;
grant execute on function public.admin_update_question_v3(uuid,text,text,jsonb,text,numeric,integer,integer,text,text,boolean,integer,boolean,text) to authenticated;

revoke all on function public.admin_import_questions_v2(jsonb,text) from public, anon;
grant execute on function public.admin_import_questions_v2(jsonb,text) to authenticated;

revoke all on function public.admin_regrade_round(uuid,text,numeric) from public, anon;
grant execute on function public.admin_regrade_round(uuid,text,numeric) to authenticated;
