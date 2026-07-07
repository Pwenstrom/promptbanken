-- get_plan_usage() predates shared_workspace_addons and was never updated
-- for it. A "start" (Delad arbetsyta) workspace is type='organization'
-- with license_id null, so it fell into the *personal*-workspace branch:
--   - max_members returned as hardcoded 1 (real cap lives in
--     shared_workspace_addons.max_members, default 5)
--   - max_mcp_keys returned as case-when-pro-then-5 (wrong on two counts:
--     personal Pro is 3 per enforce_mcp_key_limit, and addon workspaces
--     have ZERO own MCP keys per that same trigger)
--   - used_prompts counted only owner_user_id = caller, but the real
--     200-prompt cap in enforce_content_access_model is pooled across
--     the whole addon workspace, not per member
--
-- This splits the non-license branch in two: true personal workspaces
-- (unchanged behaviour, just the mcp_keys number corrected to match
-- enforce_mcp_key_limit's 3/1 split) and organization+addon workspaces
-- (numbers read from shared_workspace_addons, matching
-- enforce_org_member_limit/enforce_content_access_model/enforce_mcp_key_limit).

create or replace function public.get_plan_usage(p_workspace_id uuid)
returns table(
    has_license      boolean,
    max_prompts      integer,
    max_mcp_keys     integer,
    max_members      integer,
    max_workspaces   integer,
    used_prompts     integer,
    used_mcp_keys    integer,
    used_members     integer,
    used_workspaces  integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_workspace public.workspaces%rowtype;
    v_license   public.pro_licenses%rowtype;
    v_addon     public.shared_workspace_addons%rowtype;
    v_ids       uuid[];
begin
    select * into v_workspace from public.workspaces where id = p_workspace_id;
    if not found then
        raise exception 'Workspace saknas.';
    end if;

    if not exists (
        select 1 from public.profiles
         where user_id = (select auth.uid()) and workspace_id = p_workspace_id
    ) and not app_private.current_user_is_platform_owner() then
        raise exception 'Åtkomst nekad.';
    end if;

    -- Delad addon-yta: organisation, ingen licens, gränser i shared_workspace_addons.
    if v_workspace.type = 'organization' and v_workspace.license_id is null then
        select * into v_addon from public.shared_workspace_addons where workspace_id = p_workspace_id;

        return query
        select
            false,
            coalesce(v_addon.max_prompts, 200),
            0,  -- delade addon-ytor har inga egna MCP-nycklar (enforce_mcp_key_limit)
            coalesce(v_addon.max_members, 5),
            1,
            (select count(*)::int from public.content_items
              where workspace_id = p_workspace_id and type = 'prompt' and status <> 'archived'),
            0,
            (select count(*)::int from public.profiles where workspace_id = p_workspace_id),
            1;
        return;
    end if;

    if v_workspace.type <> 'organization' or v_workspace.license_id is null then
        return query
        select
            false,
            v_workspace.max_prompts,
            (case when v_workspace.plan = 'pro' then 3 else 1 end),
            1,
            1,
            (select count(*)::int from public.content_items
              where workspace_id = p_workspace_id and type = 'prompt' and owner_user_id = (select auth.uid()) and status <> 'archived'),
            (select count(*)::int from public.api_keys
              where workspace_id = p_workspace_id and scopes @> array['mcp']::text[] and revoked_at is null),
            1,
            1;
        return;
    end if;

    select * into v_license from public.pro_licenses where id = v_workspace.license_id;
    select array_agg(id) into v_ids from public.workspaces w where w.id in (select app_private.license_group_workspace_ids(p_workspace_id));

    return query
    select
        true,
        v_license.max_prompts_total,
        v_license.max_mcp_keys_total,
        v_license.max_members_total,
        v_license.max_workspaces,
        (select count(*)::int from public.content_items
          where workspace_id = any(v_ids) and type = 'prompt' and status <> 'archived'),
        (select count(*)::int from public.api_keys
          where workspace_id = any(v_ids) and scopes @> array['mcp']::text[] and revoked_at is null),
        (select count(*)::int from public.profiles where workspace_id = any(v_ids)),
        (select count(*)::int from public.workspaces where id = any(v_ids));
end;
$$;

revoke all on function public.get_plan_usage(uuid) from public;
grant execute on function public.get_plan_usage(uuid) to authenticated;
