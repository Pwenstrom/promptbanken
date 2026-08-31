-- supabase/tests/verify_library_reference_packages.sql
-- Self-contained, rollback-wrapped. Skapar ett publicerat katalogpaket
-- med två prompts, testar referens- och kopieringsvägen, samt att
-- paketkopiering dedupar mot en redan enskilt kopierad prompt.

begin;

create temp table pkg_lib_results (
  test text primary key,
  ok boolean not null,
  detail text not null
);

grant select, insert, update, delete on table pkg_lib_results to anon, authenticated;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('90000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'pkg.lib.owner@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.workspaces (id, name, slug, type, plan, owner_user_id, max_prompts, mcp_enabled)
values ('91000000-0000-0000-0000-000000000001', 'Pkg lib ws', 'pkg-lib-ws', 'personal', 'free', '90000000-0000-0000-0000-000000000001', 3, true);

insert into public.profiles (user_id, workspace_id, role)
values ('90000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'editor');

insert into public.catalog_prompts (id, slug, status)
values
  ('92000000-0000-0000-0000-000000000001', 'pkg-lib-fixture-prompt-1', 'published'),
  ('92000000-0000-0000-0000-000000000002', 'pkg-lib-fixture-prompt-2', 'published');
insert into public.catalog_prompt_variants (prompt_id, context_key, title, summary, prompt_text)
values
  ('92000000-0000-0000-0000-000000000001', 'generell', 'Fixture prompt 1', 'Summary 1', 'Prompt text 1'),
  ('92000000-0000-0000-0000-000000000002', 'generell', 'Fixture prompt 2', 'Summary 2', 'Prompt text 2');

insert into public.catalog_packages (id, slug, status, package_type)
values ('93000000-0000-0000-0000-000000000001', 'pkg-lib-fixture-package', 'published', 'collection');
insert into public.catalog_package_variants (package_id, context_key, title, summary, intro_text)
values ('93000000-0000-0000-0000-000000000001', 'generell', 'Fixture package', 'Package summary', 'Intro text');
insert into public.catalog_package_items (package_id, prompt_id, sort_order)
values
  ('93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', 0),
  ('93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000002', 1);

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

-- 1. Referens: skapar utkast, inga items, live-läsning ger båda stegen.
do $$
declare
    v_draft public.creator_package_drafts;
    v_rows record;
    v_count integer := 0;
begin
    v_draft := public.add_catalog_package_to_library('93000000-0000-0000-0000-000000000001');
    insert into pkg_lib_results values (
        '1a - add_catalog_package_to_library creates reference draft',
        v_draft.title = 'Fixture package' and v_draft.library_ref_catalog_package_id = '93000000-0000-0000-0000-000000000001',
        'title=' || v_draft.title || ' ref=' || coalesce(v_draft.library_ref_catalog_package_id::text, '<null>')
    );

    for v_rows in select * from public.get_referenced_library_package(v_draft.id) loop
        v_count := v_count + 1;
    end loop;
    insert into pkg_lib_results values (
        '1b - get_referenced_library_package returns 2 live steps',
        v_count = 2,
        'count=' || v_count
    );
end $$;

-- 2. Full copy: creates a real draft with 2 real content_items, owned by
-- the caller, via the existing prompt-copy RPC, in order.
do $$
declare
    v_draft public.creator_package_drafts;
    v_item_count integer;
    v_owned_count integer;
begin
    v_draft := public.copy_published_package_to_valvet('93000000-0000-0000-0000-000000000001');
    insert into pkg_lib_results values (
        '2a - copy_published_package_to_valvet does not set a reference',
        v_draft.library_ref_catalog_package_id is null,
        'ref=' || coalesce(v_draft.library_ref_catalog_package_id::text, '<null>')
    );

    select count(*) into v_item_count
      from public.creator_package_items
     where draft_id = v_draft.id;
    insert into pkg_lib_results values (
        '2b - full copy has 2 real content_items',
        v_item_count = 2,
        'item_count=' || v_item_count
    );

    select count(*) into v_owned_count
      from public.creator_package_items cpi
      join public.content_items ci on ci.id = cpi.content_item_id
     where cpi.draft_id = v_draft.id
       and ci.owner_user_id = '90000000-0000-0000-0000-000000000001'
       and ci.module = 'valvet';
    insert into pkg_lib_results values (
        '2c - both copied items are owned Valvet content_items',
        v_owned_count = 2,
        'owned_count=' || v_owned_count
    );
end $$;

-- 3. Dedup: copying a prompt individually first, then the whole package,
-- must not create a second content_items row for that same prompt.
do $$
declare
    v_direct_copy public.content_items;
    v_draft public.creator_package_drafts;
    v_dup_count integer;
begin
    v_direct_copy := public.copy_published_prompt_to_valvet('92000000-0000-0000-0000-000000000001');
    v_draft := public.copy_published_package_to_valvet('93000000-0000-0000-0000-000000000001');

    select count(*) into v_dup_count
      from public.content_items
     where owner_user_id = '90000000-0000-0000-0000-000000000001'
       and source_template_id = '92000000-0000-0000-0000-000000000001';

    insert into pkg_lib_results values (
        '3 - package copy dedupes against an already individually-copied prompt',
        v_dup_count = 1,
        'rows_for_that_prompt=' || v_dup_count
    );
end $$;
reset role;

select test, ok, detail from pkg_lib_results order by test;

rollback;
