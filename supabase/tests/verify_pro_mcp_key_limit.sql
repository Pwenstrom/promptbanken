-- supabase/tests/verify_pro_mcp_key_limit.sql
-- Self-contained, rollback-wrapped. Skapar en Pro-personlig workspace,
-- infogar 3 aktiva MCP-nycklar direkt (samma väg som vault.js:793s
-- createMcpKey går -- en vanlig authenticated-insert, ingen bypass),
-- och bekräftar att en 4:e nyckel avvisas.

begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('80000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'key.limit.check@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.workspaces (id, name, slug, type, plan, owner_user_id, max_prompts, mcp_enabled)
values ('81000000-0000-0000-0000-000000000001', 'Key limit ws', 'key-limit-ws', 'personal', 'pro', '80000000-0000-0000-0000-000000000001', 100, true);

insert into public.profiles (user_id, workspace_id, role)
values ('80000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'workspace_owner');

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true);

do $$
declare
    i integer;
    v_rejected_at_4 boolean := false;
begin
    for i in 1..3 loop
        insert into public.api_keys (workspace_id, created_by, name, key_prefix, key_hash, scopes)
        values ('81000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001',
                'Key ' || i, 'pfx' || i, 'hash' || i, array['mcp']);
    end loop;

    begin
        insert into public.api_keys (workspace_id, created_by, name, key_prefix, key_hash, scopes)
        values ('81000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001',
                'Key 4', 'pfx4', 'hash4', array['mcp']);
    exception
        when others then
            v_rejected_at_4 := true;
    end;

    if not v_rejected_at_4 then
        raise exception 'Pro-konto tillät en 4:e MCP-nyckel -- gränsen är inte 3.';
    end if;

    raise notice 'Pro MCP key limit is 3, as expected.';
end $$;
reset role;

rollback;
