do $$
begin
    if to_regprocedure('app_private.get_mcp_key_context(text)') is null then
        raise exception 'Missing app_private.get_mcp_key_context(text)';
    end if;

    if not has_function_privilege(
        'mcp_server',
        'app_private.get_mcp_key_context(text)',
        'EXECUTE'
    ) then
        raise exception 'mcp_server lacks EXECUTE on get_mcp_key_context(text)';
    end if;

    if has_function_privilege(
        'mcp_server',
        'app_private.verify_mcp_key(text)',
        'EXECUTE'
    ) then
        raise exception 'mcp_server must not regain EXECUTE on verify_mcp_key(text)';
    end if;
end;
$$;
