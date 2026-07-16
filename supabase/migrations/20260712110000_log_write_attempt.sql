-- C:\Users\petwen\OneDrive - Höglandsförbundet\Projekt\mcp_promptbanken\promptbanken\supabase\migrations\20260712110000_log_write_attempt.sql
-- Fix: log inserts made right before `raise exception` in save_prompt_for_key
-- never persist (the raise rolls back the whole transaction, including the
-- log insert made moments earlier in the same call). Verified live on staging
-- 2026-07-12: only the 'success' outcome ever showed up in mcp_write_attempts.
--
-- Fix: log_write_attempt is now a separate RPC, called by the Python layer as
-- its OWN PostgREST request/transaction after catching a rejection from
-- save_prompt_for_key -- so it commits independently of the failed call.
-- save_prompt_for_key no longer attempts to log rejection outcomes itself
-- (those inserts were dead code). It still logs 'idempotent_hit' and
-- 'success' directly, since those paths RETURN instead of raising and their
-- transaction commits normally.

create or replace function app_private.log_write_attempt(
    p_key_hash text,
    p_outcome text,
    p_risk_check_passed boolean default null
) returns void
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    insert into app_private.mcp_write_attempts (key_hash, outcome, risk_check_passed)
    values (p_key_hash, p_outcome, p_risk_check_passed);
$$;

revoke all on function app_private.log_write_attempt(text, text, boolean) from public;
grant execute on function app_private.log_write_attempt(text, text, boolean) to anon;

create or replace function app_private.save_prompt_for_key(
    p_key_hash            text,
    p_title                text,
    p_content               text,
    p_category              text,
    p_source                 text default 'manual',
    p_risk_check_passed      boolean default false,
    p_idempotency_key         uuid default null
) returns public.content_items
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key           public.api_keys%rowtype;
    v_workspace     public.workspaces%rowtype;
    v_recent_count  integer;
    v_existing      public.content_items%rowtype;
    v_candidate_slug text;
    v_suffix        integer := 0;
    v_row           public.content_items%rowtype;
begin
    -- 1. Nyckel giltig?
    select k.* into v_key
      from public.api_keys k
     where k.key_hash = p_key_hash
       and k.revoked_at is null
       and k.scopes @> array['mcp']::text[]
     limit 1;

    if not found then
        raise exception 'Ogiltig eller aterkallad MCP-nyckel.';
    end if;

    select w.* into v_workspace
      from public.workspaces w
     where w.id = v_key.workspace_id
       and w.mcp_enabled = true
       and w.status = 'active';

    if not found then
        raise exception 'Arbetsytan ar inte aktiv eller saknar MCP-atkomst.';
    end if;

    -- 2. Plan = pro?
    if v_workspace.type <> 'personal' or v_workspace.plan <> 'pro' then
        raise exception 'save_workspace_prompt kraver en Pro-nyckel pa en personlig arbetsyta.';
    end if;

    -- 3. Rate limit: max 10 forsok/60s for samma nyckel.
    select count(*) into v_recent_count
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash
       and created_at > now() - interval '60 seconds';

    if v_recent_count >= 10 then
        raise exception 'For manga skrivforsok senaste minuten. Forsok igen om en liten stund.';
    end if;

    -- 4. Innehallsvalidering.
    if trim(coalesce(p_title, '')) = '' or length(p_title) > 200
       or trim(coalesce(p_content, '')) = '' or length(p_content) > 20000
       or trim(coalesce(p_category, '')) = '' then
        raise exception 'Ogiltig indata: title (1-200 tecken), content (1-20000 tecken) och category kravs.';
    end if;

    -- 5. Idempotens: samma nyckel i samma workspace -> returnera befintlig rad.
    --    Ingen raise pa denna vag -> loggningen nedan committar normalt.
    if p_idempotency_key is not null then
        select * into v_existing
          from public.content_items
         where workspace_id = v_workspace.id
           and idempotency_key = p_idempotency_key;

        if found then
            insert into app_private.mcp_write_attempts (key_hash, workspace_id, outcome, risk_check_passed)
            values (p_key_hash, v_workspace.id, 'idempotent_hit', p_risk_check_passed);
            return v_existing;
        end if;
    end if;

    -- 6. Risk-check-flagga.
    if not p_risk_check_passed then
        raise exception 'risk_check_passed maste vara true. Kor check_input_risk och lat anvandaren godkanna forst.';
    end if;

    -- 7. Slug + INSERT. Triggern enforce_content_access_model korer harifran
    --    (auth.uid() loses fran raden vi satter nedan) och kan fortfarande
    --    avvisa pa max_prompts-gransen -> propageras vidare, Python-lagret
    --    loggar 'limit_reached' via log_write_attempt efter att ha fangat felet.
    v_candidate_slug := app_private.slugify_candidate(p_title, 'mall');
    while exists (
        select 1 from public.content_items
         where workspace_id = v_workspace.id and slug = v_candidate_slug
    ) loop
        v_suffix := v_suffix + 1;
        v_candidate_slug := substr(app_private.slugify_candidate(p_title, 'mall'), 1, 110)
            || '-' || v_suffix::text;
    end loop;

    perform set_config('request.jwt.claim.sub', v_workspace.owner_user_id::text, true);

    insert into public.content_items (
        workspace_id, owner_user_id, type, title, slug, content,
        status, visibility, category, created_by, source, idempotency_key
    ) values (
        v_workspace.id, v_workspace.owner_user_id, 'prompt', p_title, v_candidate_slug, p_content,
        'draft', 'private', p_category, v_workspace.owner_user_id, p_source, p_idempotency_key
    )
    returning * into v_row;

    -- 8. Lyckad skrivning. Ingen raise pa denna vag -> committar normalt.
    insert into app_private.mcp_write_attempts (key_hash, workspace_id, outcome, risk_check_passed)
    values (p_key_hash, v_workspace.id, 'success', p_risk_check_passed);

    return v_row;
end;
$$;

revoke all on function app_private.save_prompt_for_key(text, text, text, text, text, boolean, uuid) from public;
grant execute on function app_private.save_prompt_for_key(text, text, text, text, text, boolean, uuid) to anon;
