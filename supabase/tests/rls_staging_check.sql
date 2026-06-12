begin;

create temp table rls_results (
  test text primary key,
  ok boolean not null,
  detail text not null
);

grant select, insert, update, delete on table rls_results to anon, authenticated;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'platform.owner@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'workspace.a.admin@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'workspace.a.editor@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'workspace.a.viewer@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'workspace.b.admin@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.workspaces (id, name, slug, owner_user_id)
values
  ('10000000-0000-0000-0000-000000000001', 'Workspace A', 'workspace-a', '00000000-0000-0000-0000-000000000002'),
  ('10000000-0000-0000-0000-000000000002', 'Workspace B', 'workspace-b', '00000000-0000-0000-0000-000000000005');

insert into public.profiles (user_id, workspace_id, role)
values
  ('00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'platform_owner'),
  ('00000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'workspace_admin'),
  ('00000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'editor'),
  ('00000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', 'viewer'),
  ('00000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000002', 'workspace_admin');

insert into public.content_items (id, workspace_id, owner_user_id, type, title, slug, content, status, visibility, created_by, published_at)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'prompt', 'A public published', 'a-public-published', 'content', 'published', 'public', '00000000-0000-0000-0000-000000000002', now()),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'prompt', 'A public draft', 'a-public-draft', 'content', 'draft', 'public', '00000000-0000-0000-0000-000000000002', null),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'prompt', 'A public archived', 'a-public-archived', 'content', 'archived', 'public', '00000000-0000-0000-0000-000000000002', now()),
  ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000005', 'prompt', 'B workspace published', 'b-workspace-published', 'content', 'published', 'workspace', '00000000-0000-0000-0000-000000000005', now());

set local role anon;
insert into rls_results
select 'anon reads only published public', count(*) = 1 and bool_and(id = '20000000-0000-0000-0000-000000000001'), 'count=' || count(*)
from public.content_items;
insert into rls_results
select 'anon view reads only published public', count(*) = 1 and bool_and(id = '20000000-0000-0000-0000-000000000001'), 'count=' || count(*)
from public.published_public_content;
insert into rls_results
select 'draft not public', count(*) = 0, 'count=' || count(*)
from public.content_items where id = '20000000-0000-0000-0000-000000000002';
insert into rls_results
select 'archived not public', count(*) = 0, 'count=' || count(*)
from public.content_items where id = '20000000-0000-0000-0000-000000000003';
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
insert into rls_results
select 'workspace A viewer cannot read workspace B item', count(*) = 0, 'count=' || count(*)
from public.content_items where id = '20000000-0000-0000-0000-000000000004';
insert into rls_results
select 'workspace A viewer cannot read workspace B view', count(*) = 0, 'count=' || count(*)
from public.published_workspace_content where workspace_id = '10000000-0000-0000-0000-000000000002';
insert into rls_results
select 'workspace A viewer sees only own profile in workspace A', count(*) = 1 and bool_and(user_id = '00000000-0000-0000-0000-000000000004'), 'count=' || count(*)
from public.profiles where workspace_id = '10000000-0000-0000-0000-000000000001';
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
insert into public.content_items (id, workspace_id, owner_user_id, type, title, slug, content, status, visibility, created_by)
values ('20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'prompt', 'Draft test', 'draft-test', 'Test content', 'draft', 'workspace', '00000000-0000-0000-0000-000000000003');
insert into rls_results values ('editor can create draft', true, 'insert succeeded');
update public.content_items set title = 'Draft test updated' where id = '20000000-0000-0000-0000-000000000005';
insert into rls_results values ('editor can update draft', true, 'update succeeded');
do $$
begin
  update public.content_items set status = 'published' where id = '20000000-0000-0000-0000-000000000005';
  insert into rls_results
  select 'editor cannot publish', status <> 'published', 'status=' || status
  from public.content_items where id = '20000000-0000-0000-0000-000000000005';
exception
  when insufficient_privilege then
    insert into rls_results values ('editor cannot publish', true, 'rejected by RLS');
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
update public.content_items set status = 'published' where id = '20000000-0000-0000-0000-000000000005';
insert into rls_results
select 'workspace admin can publish', status = 'published' and published_at is not null, 'status=' || status || ', published_at=' || published_at::text
from public.content_items where id = '20000000-0000-0000-0000-000000000005';
insert into rls_results
select 'workspace admin reads own workspace profiles', count(*) = 4, 'count=' || count(*)
from public.profiles where workspace_id = '10000000-0000-0000-0000-000000000001';
insert into rls_results
select 'workspace admin cannot read other workspace profiles', count(*) = 0, 'count=' || count(*)
from public.profiles where workspace_id = '10000000-0000-0000-0000-000000000002';
reset role;

set local role anon;
insert into rls_results
select 'public view excludes api key fields', count(*) = 0, 'api_key_like_columns=' || count(*)
from information_schema.columns
where table_schema = 'public'
  and table_name = 'published_public_content'
  and column_name in ('key_hash','key_prefix','scopes');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
insert into rls_results
select 'workspace view excludes api key fields', count(*) = 0, 'api_key_like_columns=' || count(*)
from information_schema.columns
where table_schema = 'public'
  and table_name = 'published_workspace_content'
  and column_name in ('key_hash','key_prefix','scopes');
reset role;

select test, ok, detail from rls_results order by test;

rollback;
