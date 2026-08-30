-- supabase/tests/verify_pro_mcp_key_limit.sql
-- Self-contained, rollback-wrapped. Skapar en Pro-personlig workspace,
-- infogar 3 aktiva MCP-nycklar direkt (samma väg som vault.js:793s
-- createMcpKey går -- en vanlig authenticated-insert, ingen bypass),
-- och bekräftar att en 4:e nyckel avvisas.
--
-- Fixture-profilen använder rollen 'workspace_owner', inte 'editor':
-- RLS-policyn api_keys_admins_insert (20260612121000_rls_policies.sql)
-- tillåter bara workspace_owner/workspace_admin att infoga i api_keys,
-- så 'editor' skulle blockera redan den första nyckeln.

begin;

create temp table key_limit_results (
  test text primary key,
  ok boolean not null,
  detail text not null
);

grant select, insert, update, delete on table key_limit_results to anon, authenticated;

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
    v_created integer := 0;
    v_rejected_at_4 boolean := false;
    v_reject_message text;
begin
    for i in 1..3 loop
        insert into public.api_keys (workspace_id, created_by, name, key_prefix, key_hash, scopes)
        values ('81000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001',
                'Key ' || i, 'pfx' || i, 'hash' || i, array['mcp']);
        v_created := v_created + 1;
    end loop;

    insert into key_limit_results values (
        '1 - three keys inserted for Pro workspace',
        v_created = 3,
        'created=' || v_created
    );

    begin
        insert into public.api_keys (workspace_id, created_by, name, key_prefix, key_hash, scopes)
        values ('81000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001',
                'Key 4', 'pfx4', 'hash4', array['mcp']);
    exception
        when others then
            v_rejected_at_4 := true;
            v_reject_message := sqlerrm;
    end;

    insert into key_limit_results values (
        '2 - fourth key rejected at Pro limit of 3',
        v_rejected_at_4,
        coalesce(v_reject_message, 'NOT rejected -- 4th key was allowed, limit is not 3')
    );
end $$;

select count(*)::int as active_keys_after_test
  from public.api_keys
 where workspace_id = '81000000-0000-0000-0000-000000000001'
   and revoked_at is null;

select test, ok, detail from key_limit_results order by test;
reset role;

rollback;
