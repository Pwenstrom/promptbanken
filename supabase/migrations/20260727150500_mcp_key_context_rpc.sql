-- The authenticated HTTP MCP endpoint needs key validity and plan metadata
-- before it can expose the correct tool profile. Prompt reads remain bound
-- to get_workspace_prompts_for_key.

create or replace function app_private.get_mcp_key_context(p_key_hash text)
returns table(
    workspace_id uuid,
    plan text,
    workspace_type text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        w.id,
        w.plan::text,
        w.type::text
    from public.api_keys k
    join public.workspaces w on w.id = k.workspace_id
    where k.key_hash = p_key_hash
      and k.revoked_at is null
      and k.scopes @> array['mcp']::text[]
      and w.mcp_enabled = true
      and w.status = 'active'
    limit 1;
$$;

revoke all on function app_private.get_mcp_key_context(text) from public;
grant execute on function app_private.get_mcp_key_context(text) to mcp_server;
