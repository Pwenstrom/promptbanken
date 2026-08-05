-- Säkerhetsfix: get_workspace_prompts(p_workspace_id) tog emot workspace_id
-- som fri parameter utan att kontrollera att den anropande MCP-nyckeln
-- faktiskt hör till det workspacet. verify_mcp_key och get_workspace_prompts
-- anropades som två separata steg, så en komprometterad MCP-server-process
-- kunde i teorin hoppa över verifieringen och fråga efter ett annat
-- workspaces prompts genom att bara skicka in dess UUID.
--
-- Fixen: en enda SECURITY DEFINER-funktion som tar emot nyckelhashen,
-- verifierar den internt och använder det egna, uppslagna workspace_id:t
-- för frågan — anroparen kan aldrig skicka in ett annat workspace_id.
-- mcp_server-rollen får bara köra denna kombinerade funktion; åtkomsten
-- till de gamla separata funktionerna dras tillbaka från rollen.

create or replace function app_private.get_workspace_prompts_for_key(
    p_key_hash text
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
    select w.* into v_workspace
    from public.api_keys k
    join public.workspaces w on w.id = k.workspace_id
    where k.key_hash    = p_key_hash
      and k.revoked_at  is null
      and k.scopes      @> array['mcp']::text[]
      and w.mcp_enabled = true
      and w.status      = 'active'
    limit 1;

    if not found then
        return;
    end if;

    if v_workspace.type = 'personal' then
        if v_workspace.plan = 'free' then
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
            where ci.workspace_id = v_workspace.id
              and ci.type         = 'prompt'
              and ci.visibility   = 'private'
              and ci.status       = 'published';

        else
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
            where ci.workspace_id = v_workspace.id
              and ci.type         = 'prompt'
              and ci.visibility   in ('private', 'workspace')
              and ci.status       = 'published';
        end if;

    else
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
        where ci.workspace_id = v_workspace.id
          and ci.type         = 'prompt'
          and ci.visibility   = 'workspace'
          and ci.status       = 'published';
    end if;
end;
$$;

revoke all on function app_private.get_workspace_prompts_for_key(text) from public;
grant execute on function app_private.get_workspace_prompts_for_key(text) to mcp_server;

-- mcp_server ska bara kunna köra den kombinerade funktionen ovan, inte
-- längre de separata verify/query-stegen.
revoke execute on function app_private.verify_mcp_key(text)       from mcp_server;
revoke execute on function app_private.get_workspace_prompts(uuid) from mcp_server;
