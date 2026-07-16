-- Bugg hittad vid produktionsverifiering 2026-07-12: PostgREST exponerar bara
-- funktioner i schemat "public" via /rest/v1/rpc/-endpointen (db-schemas =
-- public som standard). app_private.save_prompt_for_key/log_write_attempt
-- saknade public-wrappers -- samma mönster som redan används av
-- get_workspace_prompts_for_key/get_pro_templates_for_mcp_key
-- (se 20260706103000_context_mcp_scope.sql). Direktanrop mot app_private.*
-- i SQL Editor fungerade under staging-verifieringen (Task 7), vilket
-- dolde felet -- det riktiga HTTP/PostgREST-anropet gick aldrig igenom
-- förrän produktionsverifieringen.

create or replace function public.save_prompt_for_key(
    p_key_hash            text,
    p_title                text,
    p_content               text,
    p_category              text,
    p_source                 text default 'manual',
    p_risk_check_passed      boolean default false,
    p_idempotency_key         uuid default null
) returns public.content_items
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.save_prompt_for_key(
        p_key_hash, p_title, p_content, p_category, p_source, p_risk_check_passed, p_idempotency_key
    );
$$;

revoke all on function public.save_prompt_for_key(text, text, text, text, text, boolean, uuid) from public;
grant execute on function public.save_prompt_for_key(text, text, text, text, text, boolean, uuid) to anon;

create or replace function public.log_write_attempt(
    p_key_hash text,
    p_outcome text,
    p_risk_check_passed boolean default null
) returns void
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select app_private.log_write_attempt(p_key_hash, p_outcome, p_risk_check_passed);
$$;

revoke all on function public.log_write_attempt(text, text, boolean) from public;
grant execute on function public.log_write_attempt(text, text, boolean) to anon;
