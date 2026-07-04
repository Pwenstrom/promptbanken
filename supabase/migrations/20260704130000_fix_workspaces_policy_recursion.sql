-- Bugfix: "infinite recursion detected in policy for relation workspaces".
--
-- workspaces_license_siblings_read (20260704120000) queried public.workspaces
-- from inside its own USING clause to find sibling license_ids. Evaluating
-- that subquery re-applies RLS on workspaces (including this same policy),
-- which re-runs the subquery, forever. Fix: move the lookup into a
-- SECURITY DEFINER helper function, which executes with RLS bypassed for
-- its internal query (same pattern as app_private.license_group_workspace_ids),
-- so the policy itself never re-reads workspaces under RLS.

create or replace function app_private.my_license_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
    select distinct w.license_id
      from public.workspaces w
      join public.profiles p on p.workspace_id = w.id
     where p.user_id = (select auth.uid())
       and w.license_id is not null;
$$;

revoke all on function app_private.my_license_ids() from public;
grant execute on function app_private.my_license_ids() to authenticated;

drop policy if exists "workspaces_license_siblings_read" on public.workspaces;
create policy "workspaces_license_siblings_read"
on public.workspaces
for select
to authenticated
using (
    license_id is not null
    and license_id in (select app_private.my_license_ids())
);
