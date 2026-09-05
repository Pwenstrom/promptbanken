-- Self-contained, rollback-wrapped verification of the narrow Connect read RPC.
-- It proves owner-only access for Creator prompts and Valvet copies, plus the
-- existing live-reference path used by Connect after reading the record.

begin;

create temp table connect_read_results (
  test text primary key,
  ok boolean not null,
  detail text not null
);
grant select, insert, update, delete on table connect_read_results to anon, authenticated;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('c1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'connect.owner@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('c1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'connect.other@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.workspaces (id, name, slug, type, plan, owner_user_id, max_prompts, mcp_enabled)
values
  ('c1100000-0000-0000-0000-000000000001', 'Connect owner', 'connect-owner', 'personal', 'free', 'c1000000-0000-0000-0000-000000000001', 100, true),
  ('c1100000-0000-0000-0000-000000000002', 'Connect other', 'connect-other', 'personal', 'free', 'c1000000-0000-0000-0000-000000000002', 100, true);

insert into public.profiles (user_id, workspace_id, role)
values
  ('c1000000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'editor'),
  ('c1000000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000002', 'editor');

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

insert into public.content_items (
  id, workspace_id, owner_user_id, created_by, type, module,
  title, slug, summary, content, category, status, visibility
) values
  ('c1200000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'prompt', 'kommun', 'Creator-prompt', 'creator-prompt', 'Creator-sammanfattning', 'Creator-text', 'Test', 'draft', 'private'),
  ('c1200000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'prompt', 'valvet', 'Egen kopia', 'egen-kopia', 'Kopierad sammanfattning', 'Kopierad text', 'Test', 'draft', 'private');

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
insert into public.content_items (
  id, workspace_id, owner_user_id, created_by, type, module,
  title, slug, summary, content, category, status, visibility
) values
  ('c1200000-0000-0000-0000-000000000003', 'c1100000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000002', 'prompt', 'kommun', 'Främmande prompt', 'frammande-prompt', 'Hemlig sammanfattning', 'Hemlig text', 'Test', 'draft', 'private');
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

insert into public.catalog_prompts (id, slug, status)
values ('c1300000-0000-0000-0000-000000000001', 'connect-live-reference', 'published');
insert into public.catalog_prompt_variants (prompt_id, context_key, title, summary, prompt_text, area)
values ('c1300000-0000-0000-0000-000000000001', 'generell', 'Levande titel', 'Levande sammanfattning', 'Levande prompttext', 'Test');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

do $$
declare v_row record;
begin
  select * into v_row from public.get_my_connect_library_prompt('c1200000-0000-0000-0000-000000000001');
  insert into connect_read_results values (
    'owner reads own Creator prompt',
    found and v_row.module = 'kommun' and v_row.content = 'Creator-text' and not v_row.is_library_reference,
    'module=' || coalesce(v_row.module, '<none>') || ' content=' || coalesce(v_row.content, '<none>')
  );
end $$;

do $$
declare v_row record;
begin
  select * into v_row from public.get_my_connect_library_prompt('c1200000-0000-0000-0000-000000000002');
  insert into connect_read_results values (
    'owner reads own Valvet copy',
    found and v_row.module = 'valvet' and v_row.content = 'Kopierad text' and not v_row.is_library_reference,
    'module=' || coalesce(v_row.module, '<none>') || ' content=' || coalesce(v_row.content, '<none>')
  );
end $$;

do $$
declare v_ref public.content_items; v_row record; v_live text;
begin
  select * into v_ref from public.add_catalog_prompt_to_library('c1300000-0000-0000-0000-000000000001');
  select * into v_row from public.get_my_connect_library_prompt(v_ref.id);
  select prompt_text into v_live from public.get_referenced_library_prompt(v_ref.id);
  insert into connect_read_results values (
    'owner reads reference identity and live content separately',
    found and v_row.is_library_reference and v_row.content = '' and v_live = 'Levande prompttext',
    'is_reference=' || coalesce(v_row.is_library_reference::text, '<none>') || ' live=' || coalesce(v_live, '<none>')
  );
end $$;

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);

do $$
begin
  perform * from public.get_my_connect_library_prompt('c1200000-0000-0000-0000-000000000001');
  insert into connect_read_results values (
    'other user cannot read owner prompt',
    not found,
    case when found then 'foreign row leaked' else 'no row as expected' end
  );
end $$;

reset role;
select test, ok, detail from connect_read_results order by test;
rollback;