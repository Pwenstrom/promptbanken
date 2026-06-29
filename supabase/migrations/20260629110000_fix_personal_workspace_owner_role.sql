-- Fix: personal workspace owners should have workspace_owner role, not editor.
-- This is required so that owners can create and revoke MCP/API keys
-- (api_keys RLS requires workspace_owner or workspace_admin).

-- 1. Backfill existing personal workspace owners to workspace_owner role.
update public.profiles p
   set role = 'workspace_owner'
  from public.workspaces w
 where w.id = p.workspace_id
   and w.type = 'personal'
   and w.owner_user_id = p.user_id
   and p.role = 'editor';

-- 2. Fix ensure_personal_workspace() to assign workspace_owner role.
create or replace function public.ensure_personal_workspace()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    user_email      text;
    workspace_id    uuid;
    base_slug       text;
    candidate_slug  text;
    suffix          integer := 0;
begin
    if current_user_id is null then
        raise exception 'Authentication required';
    end if;

    select p.workspace_id
      into workspace_id
      from public.profiles p
      join public.workspaces w on w.id = p.workspace_id
     where p.user_id = current_user_id
       and w.type = 'personal'
     order by p.created_at
     limit 1;

    if workspace_id is not null then
        return workspace_id;
    end if;

    select u.email into user_email
      from auth.users u
     where u.id = current_user_id;

    base_slug := lower(regexp_replace(coalesce(split_part(user_email, '@', 1), 'user'), '[^a-z0-9]+', '-', 'g'));
    base_slug := trim(both '-' from base_slug);
    if length(base_slug) < 3 then
        base_slug := 'user-' || substr(replace(current_user_id::text, '-', ''), 1, 8);
    end if;
    base_slug := substr(base_slug, 1, 48);
    candidate_slug := base_slug;

    while exists (select 1 from public.workspaces where slug = candidate_slug) loop
        suffix := suffix + 1;
        candidate_slug := substr(base_slug, 1, 48) || '-' || suffix::text;
    end loop;

    insert into public.workspaces (
        name, slug, type, plan, owner_user_id,
        max_prompts, max_public_items, max_documents,
        api_enabled, mcp_enabled
    )
    values (
        'Privat workspace', candidate_slug, 'personal', 'free', current_user_id,
        3, 3, 3,
        false, true
    )
    returning id into workspace_id;

    insert into public.profiles (user_id, workspace_id, role)
    values (current_user_id, workspace_id, 'workspace_owner');

    return workspace_id;
end;
$$;

revoke all on function public.ensure_personal_workspace() from public;
grant execute on function public.ensure_personal_workspace() to authenticated;
