-- supabase/tests/verify_library_reference_packages.sql
-- Self-contained, rollback-wrapped. Skapar ett publicerat katalogpaket
-- med två prompts, testar referens- och kopieringsvägen.

begin;

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
    if v_draft.title <> 'Fixture package' or v_draft.library_ref_catalog_package_id is null then
        raise exception 'add_catalog_package_to_library gave wrong data: %', v_draft;
    end if;

    for v_rows in select * from public.get_referenced_library_package(v_draft.id) loop
        v_count := v_count + 1;
    end loop;
    if v_count <> 2 then
        raise exception 'Expected 2 live-read steps, got %', v_count;
    end if;

    raise notice 'package reference: draft created, live read returns 2 steps -- OK';
end $$;

-- 2. Full copy: creates a real draft with 2 real content_items via the
-- existing prompt-copy RPC, in order.
do $$
declare
    v_draft public.creator_package_drafts;
    v_item_count integer;
begin
    v_draft := public.copy_published_package_to_valvet('93000000-0000-0000-0000-000000000001');
    if v_draft.library_ref_catalog_package_id is not null then
        raise exception 'Full copy should NOT set library_ref_catalog_package_id: %', v_draft;
    end if;

    select count(*) into v_item_count
      from public.creator_package_items
     where draft_id = v_draft.id;
    if v_item_count <> 2 then
        raise exception 'Expected 2 copied items in the new draft, got %', v_item_count;
    end if;

    raise notice 'package copy: real draft with 2 real content_items -- OK';
end $$;
reset role;

rollback;
