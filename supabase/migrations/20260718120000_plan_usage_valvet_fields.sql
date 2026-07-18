-- 20260718120000_plan_usage_valvet_fields.sql
-- get_plan_usage exponerar inga Valvet-tal, så Valvets frontend hårdkodar
-- gränserna (50/1000 items, 1/3 nycklar) och kan glida isär från
-- triggrarna. Utökar RPC:n med sex kolumner som speglar den faktiska
-- räknelogiken i enforce_vault_item_limit (20260716101000),
-- save_my_item_for_key (20260717090000) och valvet_catalog_copy_quota
-- (20260718100000). null i en *_max-kolumn = obegränsat.
--
-- Postgres tillåter inte ändrad returtyp via create or replace ->
-- drop + recreate. Grants återställs identiskt nedan. De nio befintliga
-- kolumnerna är oförändrade (admin.js läser dem via namn).

drop function public.get_plan_usage(uuid);

create function public.get_plan_usage(p_workspace_id uuid)
returns table(
    has_license      boolean,
    max_prompts      integer,
    max_mcp_keys     integer,
    max_members      integer,
    max_workspaces   integer,
    used_prompts     integer,
    used_mcp_keys    integer,
    used_members     integer,
    used_workspaces  integer,
    valvet_items_used   integer,
    valvet_items_max    integer,
    monthly_saves_used  integer,
    monthly_saves_max   integer,
    catalog_copies_used integer,
    catalog_copies_max  integer
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
    v_is_pro    boolean;
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

    -- Delad addon-yta: organisation, ingen licens, gränser i
    -- shared_workspace_addons. Valvet är personligt -> 0/null.
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
            1,
            0, null::integer, 0, null::integer, 0, null::integer;
        return;
    end if;

    if v_workspace.type <> 'organization' or v_workspace.license_id is null then
        v_is_pro := app_private.has_active_pro_entitlement(v_workspace.owner_user_id);

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
            1,
            -- Valvet-items: speglar enforce_vault_item_limit (räknas per
            -- workspace-ägare, inte anroparen -- platform_owner kan inspektera).
            (select count(*)::int from public.content_items ci
              where ci.workspace_id = p_workspace_id
                and ci.module = 'valvet'
                and ci.owner_user_id = v_workspace.owner_user_id
                and ci.status <> 'archived'),
            (case when v_workspace.plan = 'free' then 50 else 1000 end),
            -- MCP-sparningar: speglar kvotspärren i save_my_item_for_key.
            (select count(*)::int from app_private.mcp_write_attempts
              where workspace_id = p_workspace_id
                and tool = 'save_my_item'
                and outcome = 'success'
                and created_at >= date_trunc('month', now())),
            (case when v_workspace.plan = 'free' then 5 else null::integer end),
            -- Katalogkopior: speglar valvet_catalog_copy_quota
            -- (Pro-check via entitlement med utgångsdatum, inte rå planflagga).
            (select count(*)::int from app_private.valvet_catalog_copies
              where workspace_id = p_workspace_id
                and created_at >= date_trunc('month', now())),
            (case when v_is_pro then null::integer else 5 end);
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
        (select count(*)::int from public.workspaces where id = any(v_ids)),
        0, null::integer, 0, null::integer, 0, null::integer;
end;
$$;

revoke all on function public.get_plan_usage(uuid) from public;
grant execute on function public.get_plan_usage(uuid) to authenticated;
