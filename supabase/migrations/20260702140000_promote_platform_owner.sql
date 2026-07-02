-- Låter en befintlig platform_owner göra en annan användare till
-- platform_owner via e-postadress, istället för att man måste redigera
-- profiles-tabellen manuellt i SQL Editor varje gång.
--
-- Första plattformsägaren måste fortfarande bootstrappas manuellt via
-- SQL Editor (service role), se kommentar på profiles_platform_owner_update
-- i 20260612121000_rls_policies.sql — det är en engångsgrej.

create or replace function public.promote_user_to_platform_owner(p_email text)
returns table(
    user_id      uuid,
    workspace_id uuid,
    role         public.profile_role
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_is_owner boolean;
    target_user_id  uuid;
    target_workspace_id uuid;
begin
    select app_private.current_user_is_platform_owner() into caller_is_owner;
    if not caller_is_owner then
        raise exception 'Endast en plattformsadmin kan göra detta.';
    end if;

    select u.id into target_user_id
      from auth.users u
     where lower(u.email) = lower(p_email)
     limit 1;

    if target_user_id is null then
        raise exception 'Hittade ingen användare med e-post %.', p_email;
    end if;

    select p.workspace_id into target_workspace_id
      from public.profiles p
      join public.workspaces w on w.id = p.workspace_id
     where p.user_id = target_user_id
       and w.type = 'personal'
     order by p.created_at
     limit 1;

    if target_workspace_id is null then
        raise exception 'Användaren har inget personligt workspace ännu. De måste logga in minst en gång först.';
    end if;

    update public.profiles
       set role = 'platform_owner'
     where user_id = target_user_id
       and workspace_id = target_workspace_id;

    return query
    select target_user_id, target_workspace_id, 'platform_owner'::public.profile_role;
end;
$$;

revoke all on function public.promote_user_to_platform_owner(text) from public;
grant execute on function public.promote_user_to_platform_owner(text) to authenticated;
