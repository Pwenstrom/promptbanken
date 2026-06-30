-- MCP RPC-funktioner för mcp_promptbanken.
-- Anropas med service-role-key via /rest/v1/rpc/
-- så att RLS bypassas och nyckelhash aldrig exponeras i HTTP-svar.

-- ============================================================
-- 1. verify_mcp_key
--    In:  p_key_hash  text  (sha256-hex av rånyckeln)
--    Out: workspace_id, plan, workspace_type
--         NULL-rad om nyckeln saknas, är återkallad eller om
--         workspace inte har mcp_enabled.
-- ============================================================
create or replace function app_private.verify_mcp_key(
    p_key_hash text
)
returns table(
    workspace_id      uuid,
    plan              text,
    workspace_type    text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    return query
    select
        w.id,
        w.plan::text,
        w.type::text
    from public.api_keys k
    join public.workspaces w on w.id = k.workspace_id
    where k.key_hash    = p_key_hash
      and k.revoked_at  is null
      and k.scopes      @> array['mcp']::text[]
      and w.mcp_enabled = true
      and w.status      = 'active'
    limit 1;
end;
$$;

revoke all on function app_private.verify_mcp_key(text) from public;

-- ============================================================
-- 2. get_workspace_prompts
--    In:  p_workspace_id  uuid
--    Out: id, title, summary, content, visibility, category,
--         audience, status
--
--    Vilka prompts returneras beror på workspace-typ och plan:
--
--    personal / free  → egna privata prompts (visibility = private)
--    personal / pro   → privata + workspace-synliga egna prompts
--    organization     → alla workspace-synliga prompts i workspacet
--
--    Publika Promptbanken-prompts hanteras separat av MCP-servern
--    via lokala filer — de ingår inte här.
-- ============================================================
create or replace function app_private.get_workspace_prompts(
    p_workspace_id uuid
)
returns table(
    id          uuid,
    title       text,
    summary     text,
    content     text,
    visibility  text,
    category    text,
    audience    text,
    status      text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_workspace public.workspaces%rowtype;
begin
    select * into v_workspace
    from public.workspaces w
    where w.id = p_workspace_id
      and w.status = 'active';

    if not found then
        return;
    end if;

    if v_workspace.type = 'personal' then
        if v_workspace.plan = 'free' then
            -- Free: bara privata prompts
            return query
            select
                ci.id,
                ci.title,
                ci.summary,
                ci.content,
                ci.visibility::text,
                ci.category,
                ci.audience,
                ci.status::text
            from public.content_items ci
            where ci.workspace_id = p_workspace_id
              and ci.type         = 'prompt'
              and ci.visibility   = 'private'
              and ci.status       != 'archived';

        else
            -- Pro+: privata och workspace-synliga
            return query
            select
                ci.id,
                ci.title,
                ci.summary,
                ci.content,
                ci.visibility::text,
                ci.category,
                ci.audience,
                ci.status::text
            from public.content_items ci
            where ci.workspace_id = p_workspace_id
              and ci.type         = 'prompt'
              and ci.visibility   in ('private', 'workspace')
              and ci.status       != 'archived';
        end if;

    else
        -- Organisation: alla workspace-synliga prompts
        return query
        select
            ci.id,
            ci.title,
            ci.summary,
            ci.content,
            ci.visibility::text,
            ci.category,
            ci.audience,
            ci.status::text
        from public.content_items ci
        where ci.workspace_id = p_workspace_id
          and ci.type         = 'prompt'
          and ci.visibility   = 'workspace'
          and ci.status       != 'archived';
    end if;
end;
$$;

revoke all on function app_private.get_workspace_prompts(uuid) from public;
