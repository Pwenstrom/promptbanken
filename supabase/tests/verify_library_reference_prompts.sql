-- supabase/tests/verify_library_reference_prompts.sql
-- Self-contained, rollback-wrapped verification of
-- add_catalog_prompt_to_library / get_referenced_library_prompt. Same
-- pattern as rls_staging_check.sql: creates its own fixtures, asserts, and
-- rolls back -- safe to run against production, leaves no trace.

begin;

create temp table lib_ref_results (
  test text primary key,
  ok boolean not null,
  detail text not null
);

grant select, insert, update, delete on table lib_ref_results to anon, authenticated;

-- Fixture users + personal workspaces.
insert into auth.users (id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('30000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'lib.ref.owner@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('30000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'lib.ref.other@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.workspaces (id, name, slug, type, plan, owner_user_id, max_prompts, mcp_enabled)
values
  ('40000000-0000-0000-0000-000000000001', 'Lib ref owner ws', 'lib-ref-owner-ws', 'personal', 'free', '30000000-0000-0000-0000-000000000001', 3, true),
  ('40000000-0000-0000-0000-000000000002', 'Lib ref other ws', 'lib-ref-other-ws', 'personal', 'free', '30000000-0000-0000-0000-000000000002', 3, true);

insert into public.profiles (user_id, workspace_id, role)
values
  ('30000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'editor'),
  ('30000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002', 'editor');

-- Fixture: a published catalog prompt with a 'generell' variant.
insert into public.catalog_prompts (id, slug, status)
values ('50000000-0000-0000-0000-000000000001', 'lib-ref-fixture-prompt', 'published');

insert into public.catalog_prompt_variants (prompt_id, context_key, title, summary, prompt_text, area)
values ('50000000-0000-0000-0000-000000000001', 'generell', 'Fixture titel', 'Fixture summary', 'Fixture prompt text', 'test-area');

-- 1. Add a reference as the owner.
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);

do $$
declare
    v_row public.content_items;
begin
    select * into v_row from public.add_catalog_prompt_to_library('50000000-0000-0000-0000-000000000001');
    insert into lib_ref_results values (
        'add_catalog_prompt_to_library creates a reference row',
        v_row.module = 'valvet' and v_row.content = '' and v_row.status = 'draft'
            and v_row.visibility = 'private' and v_row.source = 'catalog_reference'
            and v_row.library_ref_catalog_prompt_id = '50000000-0000-0000-0000-000000000001'
            and v_row.source_template_id is null,
        'module=' || v_row.module || ' content=[' || v_row.content || '] status=' || v_row.status
            || ' source=' || v_row.source || ' ref=' || v_row.library_ref_catalog_prompt_id::text
    );
end $$;

-- 2. Calling it again returns the same row (dedup), no duplicate created.
do $$
declare
    v_first_id uuid;
    v_second_id uuid;
    v_count integer;
begin
    select id into v_first_id from public.content_items
     where workspace_id = '40000000-0000-0000-0000-000000000001'
       and library_ref_catalog_prompt_id = '50000000-0000-0000-0000-000000000001';

    select (add_catalog_prompt_to_library('50000000-0000-0000-0000-000000000001')).id into v_second_id;

    select count(*) into v_count from public.content_items
     where workspace_id = '40000000-0000-0000-0000-000000000001'
       and library_ref_catalog_prompt_id = '50000000-0000-0000-0000-000000000001';

    insert into lib_ref_results values (
        'duplicate add returns same row, no second row created',
        v_first_id = v_second_id and v_count = 1,
        'first=' || v_first_id::text || ' second=' || v_second_id::text || ' count=' || v_count
    );
end $$;

-- 3. Owner can read the live referenced content.
do $$
declare
    v_content_item_id uuid;
    v_prompt_text text;
begin
    select id into v_content_item_id from public.content_items
     where workspace_id = '40000000-0000-0000-0000-000000000001'
       and library_ref_catalog_prompt_id = '50000000-0000-0000-0000-000000000001';

    select prompt_text into v_prompt_text
      from public.get_referenced_library_prompt(v_content_item_id);

    insert into lib_ref_results values (
        'owner reads live referenced content',
        v_prompt_text = 'Fixture prompt text',
        'prompt_text=' || coalesce(v_prompt_text, '<null>')
    );
end $$;
reset role;

-- 4. A different user cannot read someone else's reference.
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);

do $$
declare
    v_content_item_id uuid;
    v_rejected boolean := false;
begin
    select id into v_content_item_id from public.content_items
     where workspace_id = '40000000-0000-0000-0000-000000000001'
       and library_ref_catalog_prompt_id = '50000000-0000-0000-0000-000000000001';

    begin
        perform * from public.get_referenced_library_prompt(v_content_item_id);
    exception
        when others then
            v_rejected := true;
    end;

    insert into lib_ref_results values (
        'other user cannot read someone else''s reference',
        v_rejected,
        case when v_rejected then 'rejected as expected' else 'NOT rejected -- leak' end
    );
end $$;
reset role;

-- 5. Unpublished/unknown catalog prompt is rejected.
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);

do $$
declare
    v_rejected boolean := false;
begin
    begin
        perform * from public.add_catalog_prompt_to_library(gen_random_uuid());
    exception
        when others then
            v_rejected := true;
    end;

    insert into lib_ref_results values (
        'unknown catalog prompt id is rejected',
        v_rejected,
        case when v_rejected then 'rejected as expected' else 'NOT rejected' end
    );
end $$;
reset role;

select test, ok, detail from lib_ref_results order by test;

rollback;
