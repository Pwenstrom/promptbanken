-- Allow owners (and workspace/platform admins) to delete their own
-- non-published prompts. No DELETE policy existed before, so RLS
-- silently denied every delete attempt.

drop policy if exists "content_items_owners_delete_non_published" on public.content_items;
create policy "content_items_owners_delete_non_published"
on public.content_items
for delete
to authenticated
using (
    status in ('draft', 'review')
    and (
        owner_user_id = (select auth.uid())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin']::public.profile_role[]
        ))
        or (select app_private.current_user_is_platform_owner())
    )
);

grant delete on public.content_items to authenticated;
