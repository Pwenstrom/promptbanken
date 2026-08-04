-- 20260805100000_fix_save_prompt_for_key_status.sql
-- Bug: save_prompt_for_key (20260712100000, backing the MCP tool
-- save_workspace_prompt) inserts content_items with status='draft'. But
-- get_workspace_prompts_for_key (20260702, backing list_my_prompts) filters
-- status='published'. Every row ever written via save_workspace_prompt has
-- therefore been permanently unreadable through list_my_prompts,
-- list_my_private_prompts, or any other read path -- confirmed by a live
-- ChatGPT test 2026-08-04: save_workspace_prompt returned status=success
-- with a real id, but get_my_item/list_my_items/search_my_items/
-- list_my_prompts/list_my_private_prompts all came back empty for it.
-- (module differing between the two paths, kommun vs valvet, is a red
-- herring -- get_workspace_prompts_for_key never filters on module.)
--
-- Fix: write status='published' (with published_at, required by the
-- content_items_published_at_check constraint) instead of 'draft'. There is
-- no separate review/publish step exposed anywhere for this MCP write path,
-- so 'draft' never served a purpose here -- it just made every save
-- unreadable. Also backfills existing stranded rows so already-created
-- items (including the test row from the 2026-08-04 report) become visible
-- without needing a new cleanup/delete MCP tool.

update public.content_items
   set status = 'published',
       published_at = now()
 where module = 'kommun'
   and status = 'draft'
   and source in ('manual', 'chat_extraction')
   and idempotency_key is not null;

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
        insert into app_private.mcp_write_attempts (key_hash, outcome, risk_check_passed)
        values (p_key_hash, 'invalid_key', p_risk_check_passed);
        raise exception 'Ogiltig eller aterkallad MCP-nyckel.';
    end if;

    select w.* into v_workspace
      from public.workspaces w
     where w.id = v_key.workspace_id
       and w.mcp_enabled = true
       and w.status = 'active';

    if not found then
        insert into app_private.mcp_write_attempts (key_hash, outcome, risk_check_passed)
        values (p_key_hash, 'invalid_key', p_risk_check_passed);
        raise exception 'Arbetsytan ar inte aktiv eller saknar MCP-atkomst.';
    end if;

    -- 2. Plan = pro?
    if v_workspace.type <> 'personal' or v_workspace.plan <> 'pro' then
        insert into app_private.mcp_write_attempts (key_hash, workspace_id, outcome, risk_check_passed)
        values (p_key_hash, v_workspace.id, 'not_pro', p_risk_check_passed);
        raise exception 'save_workspace_prompt kraver en Pro-nyckel pa en personlig arbetsyta.';
    end if;

    -- 3. Rate limit: max 10 forsok/60s for samma nyckel.
    select count(*) into v_recent_count
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash
       and created_at > now() - interval '60 seconds';

    if v_recent_count >= 10 then
        insert into app_private.mcp_write_attempts (key_hash, workspace_id, outcome, risk_check_passed)
        values (p_key_hash, v_workspace.id, 'rate_limited', p_risk_check_passed);
        raise exception 'For manga skrivforsok senaste minuten. Forsok igen om en liten stund.';
    end if;

    -- 4. Innehallsvalidering.
    if trim(coalesce(p_title, '')) = '' or length(p_title) > 200
       or trim(coalesce(p_content, '')) = '' or length(p_content) > 20000
       or trim(coalesce(p_category, '')) = '' then
        insert into app_private.mcp_write_attempts (key_hash, workspace_id, outcome, risk_check_passed)
        values (p_key_hash, v_workspace.id, 'invalid_input', p_risk_check_passed);
        raise exception 'Ogiltig indata: title (1-200 tecken), content (1-20000 tecken) och category kravs.';
    end if;

    -- 5. Idempotens: samma nyckel i samma workspace -> returnera befintlig rad.
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
        insert into app_private.mcp_write_attempts (key_hash, workspace_id, outcome, risk_check_passed)
        values (p_key_hash, v_workspace.id, 'risk_check_not_passed', p_risk_check_passed);
        raise exception 'risk_check_passed maste vara true. Kor check_input_risk och lat anvandaren godkanna forst.';
    end if;

    -- 7. Slug + INSERT. Triggern enforce_content_access_model korer harifran
    --    (auth.uid() loses fran raden vi satter nedan) och kan fortfarande
    --    avvisa pa max_prompts-gransen -> loggas som limit_reached i exception-fallet.
    --    status='published' (inte 'draft'): det finns ingen granskningsflora
    --    for denna MCP-skrivvag, och get_workspace_prompts_for_key laser bara
    --    status='published' -- 'draft' gjorde raden permanent oatkomlig
    --    (se 20260805100000_fix_save_prompt_for_key_status.sql).
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

    begin
        insert into public.content_items (
            workspace_id, owner_user_id, type, title, slug, content,
            status, published_at, visibility, category, created_by, source, idempotency_key
        ) values (
            v_workspace.id, v_workspace.owner_user_id, 'prompt', p_title, v_candidate_slug, p_content,
            'published', now(), 'private', p_category, v_workspace.owner_user_id, p_source, p_idempotency_key
        )
        returning * into v_row;
    exception when others then
        insert into app_private.mcp_write_attempts (key_hash, workspace_id, outcome, risk_check_passed)
        values (p_key_hash, v_workspace.id, 'limit_reached', p_risk_check_passed);
        raise;
    end;

    -- 8. Lyckad skrivning.
    insert into app_private.mcp_write_attempts (key_hash, workspace_id, outcome, risk_check_passed)
    values (p_key_hash, v_workspace.id, 'success', p_risk_check_passed);

    return v_row;
end;
$$;

revoke all on function app_private.save_prompt_for_key(text, text, text, text, text, boolean, uuid) from public;
grant execute on function app_private.save_prompt_for_key(text, text, text, text, text, boolean, uuid) to anon;
