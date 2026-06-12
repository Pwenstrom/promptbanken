-- Promptbanken MVP RLS policies.
-- Review before running: this enables RLS and creates helper functions and policies.
-- No destructive changes. Existing policies with the same names are replaced via drop/create.

create schema if not exists app_private;

create or replace function app_private.current_user_has_workspace_role(
    target_workspace_id uuid,
    allowed_roles public.profile_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.profiles p
        where p.workspace_id = target_workspace_id
          and p.user_id = (select auth.uid())
          and p.role = any(allowed_roles)
    );
$$;

create or replace function app_private.current_user_is_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.profiles p
        where p.user_id = (select auth.uid())
          and p.role = 'platform_owner'
    );
$$;

revoke all on schema app_private from public;
grant usage on schema app_private to anon, authenticated;
revoke all on function app_private.current_user_has_workspace_role(uuid, public.profile_role[]) from public;
revoke all on function app_private.current_user_is_platform_owner() from public;
grant execute on function app_private.current_user_has_workspace_role(uuid, public.profile_role[]) to anon, authenticated;
grant execute on function app_private.current_user_is_platform_owner() to authenticated;

alter table public.workspaces enable row level security;
alter table public.profiles enable row level security;
alter table public.content_items enable row level security;
alter table public.files enable row level security;
alter table public.api_keys enable row level security;

-- Public read access is only for published public content.
drop policy if exists "content_items_public_read_published_public" on public.content_items;
create policy "content_items_public_read_published_public"
on public.content_items
for select
to anon, authenticated
using (
    status = 'published'
    and visibility = 'public'
);

-- Authenticated workspace members can read content in their workspace.
drop policy if exists "content_items_workspace_members_read" on public.content_items;
create policy "content_items_workspace_members_read"
on public.content_items
for select
to authenticated
using (
    (select app_private.current_user_is_platform_owner())
    or (
        visibility in ('workspace', 'public')
        and (select app_private.current_user_has_workspace_role(
            workspace_id,
            array[
                'workspace_owner',
                'workspace_admin',
                'editor',
                'viewer'
            ]::public.profile_role[]
        ))
    )
    or (
        visibility = 'private'
        and owner_user_id = (select auth.uid())
    )
);

-- Editors/admins/owners can create drafts or review items in their workspace.
drop policy if exists "content_items_editors_insert_draft" on public.content_items;
create policy "content_items_editors_insert_draft"
on public.content_items
for insert
to authenticated
with check (
    status in ('draft', 'review')
    and created_by = (select auth.uid())
    and (
        owner_user_id is null
        or owner_user_id = (select auth.uid())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin']::public.profile_role[]
        ))
        or (select app_private.current_user_is_platform_owner())
    )
    and (
        (select app_private.current_user_is_platform_owner())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin', 'editor']::public.profile_role[]
        ))
    )
);

-- Editors/admins/owners can edit non-published content, but this policy cannot publish.
drop policy if exists "content_items_editors_update_non_published" on public.content_items;
create policy "content_items_editors_update_non_published"
on public.content_items
for update
to authenticated
using (
    status in ('draft', 'review')
    and (
        owner_user_id is null
        or owner_user_id = (select auth.uid())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin']::public.profile_role[]
        ))
        or (select app_private.current_user_is_platform_owner())
    )
    and (
        (select app_private.current_user_is_platform_owner())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin', 'editor']::public.profile_role[]
        ))
    )
)
with check (
    status in ('draft', 'review')
    and (
        (select app_private.current_user_is_platform_owner())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin', 'editor']::public.profile_role[]
        ))
    )
);

-- Only workspace admins/owners/platform owners can publish or maintain published items.
drop policy if exists "content_items_admins_update_published" on public.content_items;
create policy "content_items_admins_update_published"
on public.content_items
for update
to authenticated
using (
    (select app_private.current_user_is_platform_owner())
    or (select app_private.current_user_has_workspace_role(
        workspace_id,
        array['workspace_owner', 'workspace_admin']::public.profile_role[]
    ))
)
with check (
    (
        status in ('draft', 'review', 'published', 'archived')
    )
    and (
        (select app_private.current_user_is_platform_owner())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin']::public.profile_role[]
        ))
    )
);

-- Users can read their own profile rows; platform owners can read all profile rows.
drop policy if exists "profiles_read_own_or_platform_owner" on public.profiles;
create policy "profiles_read_own_or_platform_owner"
on public.profiles
for select
to authenticated
using (
    user_id = (select auth.uid())
    or (select app_private.current_user_is_platform_owner())
);

-- Platform owners administer profiles. Initial bootstrap must be done by service role.
drop policy if exists "profiles_platform_owner_insert" on public.profiles;
create policy "profiles_platform_owner_insert"
on public.profiles
for insert
to authenticated
with check ((select app_private.current_user_is_platform_owner()));

drop policy if exists "profiles_platform_owner_update" on public.profiles;
create policy "profiles_platform_owner_update"
on public.profiles
for update
to authenticated
using ((select app_private.current_user_is_platform_owner()))
with check ((select app_private.current_user_is_platform_owner()));

-- Workspace owners/admins can read workspace metadata for their workspace; platform owners can read all.
drop policy if exists "workspaces_members_read" on public.workspaces;
create policy "workspaces_members_read"
on public.workspaces
for select
to authenticated
using (
    (select app_private.current_user_is_platform_owner())
    or owner_user_id = (select auth.uid())
    or (select app_private.current_user_has_workspace_role(
        id,
        array['workspace_owner', 'workspace_admin', 'editor', 'viewer']::public.profile_role[]
    ))
);

drop policy if exists "workspaces_platform_owner_insert" on public.workspaces;
create policy "workspaces_platform_owner_insert"
on public.workspaces
for insert
to authenticated
with check ((select app_private.current_user_is_platform_owner()));

drop policy if exists "workspaces_platform_owner_update" on public.workspaces;
create policy "workspaces_platform_owner_update"
on public.workspaces
for update
to authenticated
using ((select app_private.current_user_is_platform_owner()))
with check ((select app_private.current_user_is_platform_owner()));

-- Files are visible to workspace members and platform owners.
drop policy if exists "files_workspace_members_read" on public.files;
create policy "files_workspace_members_read"
on public.files
for select
to authenticated
using (
    (select app_private.current_user_is_platform_owner())
    or (select app_private.current_user_has_workspace_role(
        workspace_id,
        array['workspace_owner', 'workspace_admin', 'editor', 'viewer']::public.profile_role[]
    ))
);

drop policy if exists "files_editors_insert" on public.files;
create policy "files_editors_insert"
on public.files
for insert
to authenticated
with check (
    uploaded_by = (select auth.uid())
    and (
        (select app_private.current_user_is_platform_owner())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin', 'editor']::public.profile_role[]
        ))
    )
);

-- API keys are admin-only. API/MCP runtime should validate hashes server-side and read published views only.
drop policy if exists "api_keys_admins_read" on public.api_keys;
create policy "api_keys_admins_read"
on public.api_keys
for select
to authenticated
using (
    (select app_private.current_user_is_platform_owner())
    or (select app_private.current_user_has_workspace_role(
        workspace_id,
        array['workspace_owner', 'workspace_admin']::public.profile_role[]
    ))
);

drop policy if exists "api_keys_admins_insert" on public.api_keys;
create policy "api_keys_admins_insert"
on public.api_keys
for insert
to authenticated
with check (
    created_by = (select auth.uid())
    and (
        (select app_private.current_user_is_platform_owner())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin']::public.profile_role[]
        ))
    )
);

drop policy if exists "api_keys_admins_update" on public.api_keys;
create policy "api_keys_admins_update"
on public.api_keys
for update
to authenticated
using (
    (select app_private.current_user_is_platform_owner())
    or (select app_private.current_user_has_workspace_role(
        workspace_id,
        array['workspace_owner', 'workspace_admin']::public.profile_role[]
    ))
)
with check (
    (select app_private.current_user_is_platform_owner())
    or (select app_private.current_user_has_workspace_role(
        workspace_id,
        array['workspace_owner', 'workspace_admin']::public.profile_role[]
    ))
);

grant select on public.content_items to anon, authenticated;
grant select on public.workspaces to authenticated;
grant select on public.profiles to authenticated;
grant select on public.files to authenticated;
grant select, insert, update on public.content_items to authenticated;
grant insert, update on public.workspaces to authenticated;
grant insert, update on public.profiles to authenticated;
grant insert on public.files to authenticated;
grant select, insert, update on public.api_keys to authenticated;
