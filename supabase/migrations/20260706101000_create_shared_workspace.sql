-- Enda vägen till en ny delad addon-yta. Kräver att anroparen själv har
-- en aktiv Pro-rättighet. Skapar ALDRIG en pro_licenses-rad.

create or replace function public.create_shared_workspace(p_name text)
returns table(workspace_id uuid, addon_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id  uuid := auth.uid();
    new_workspace_id uuid;
    new_addon_id     uuid;
    resolved_name    text;
    candidate_slug   text;
    suffix           integer := 0;
begin
    if current_user_id is null then
        raise exception 'Inloggning krävs.';
    end if;

    if not app_private.has_active_pro_entitlement(current_user_id) then
        raise exception 'Du behöver en aktiv Pro-plan för att skapa en delad arbetsyta.';
    end if;

    resolved_name := coalesce(nullif(trim(p_name), ''), 'Delad arbetsyta');

    candidate_slug := app_private.slugify_candidate(resolved_name, 'arbetsyta');
    while exists (select 1 from public.workspaces where slug = candidate_slug) loop
        suffix := suffix + 1;
        candidate_slug := substr(app_private.slugify_candidate(resolved_name, 'arbetsyta'), 1, 44) || '-' || suffix::text;
    end loop;

    insert into public.workspaces (
        name, slug, type, plan, owner_user_id, license_id,
        max_prompts, api_enabled, mcp_enabled
    ) values (
        resolved_name, candidate_slug, 'organization', 'start', current_user_id, null,
        200, false, true
    )
    returning id into new_workspace_id;

    insert into public.shared_workspace_addons (
        workspace_id, owner_user_id, billing_owner_user_id,
        max_members, max_prompts, price_per_month, plan_source
    ) values (
        new_workspace_id, current_user_id, current_user_id,
        5, 200, 199, 'invoice'
    )
    returning id into new_addon_id;

    insert into public.profiles (user_id, workspace_id, role)
    values (current_user_id, new_workspace_id, 'workspace_owner');

    return query select new_workspace_id, new_addon_id;
end;
$$;

revoke all on function public.create_shared_workspace(text) from public;
grant execute on function public.create_shared_workspace(text) to authenticated;
