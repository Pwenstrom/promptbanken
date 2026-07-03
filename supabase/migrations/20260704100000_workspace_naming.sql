-- Låt Team/Förvaltning/Kommun-beställningar döpa sin arbetsyta direkt
-- (skiljt från fakturans företagsnamn -- samma kommun kan köpa flera
-- team med olika namn, t.ex. "IT-teamet" och "HR-teamet"), samt en
-- enkel funktion för att döpa om en arbetsyta i efterhand.

-- create_pro_order() får en ny, valfri p_workspace_name-parameter.
-- Signaturen ändras (ny parameter), så vi tar bort den gamla funktionen
-- explicit innan vi skapar den nya -- CREATE OR REPLACE kan inte byta
-- parameterlista.
drop function if exists public.create_pro_order(public.workspace_plan, integer, text, text, text, text, text);

create or replace function public.create_pro_order(
    p_requested_plan       public.workspace_plan,
    p_requested_workspaces integer,
    p_billing_company_name text,
    p_billing_org_number   text,
    p_billing_address      text,
    p_billing_reference    text,
    p_billing_email        text,
    p_workspace_name       text default null
)
returns table(
    order_id     uuid,
    license_id   uuid,
    workspace_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id  uuid := auth.uid();
    limits           record;
    new_license_id   uuid;
    new_workspace_id uuid;
    new_order_id     uuid;
    candidate_slug   text;
    suffix           integer := 0;
    personal_ws_id   uuid;
    resolved_name    text;
begin
    if current_user_id is null then
        raise exception 'Inloggning krävs.';
    end if;

    select * into limits from app_private.plan_limits(p_requested_plan);

    if p_requested_plan = 'pro' then
        -- Personligt Pro: aktivera direkt på anroparens egna personliga workspace.
        select p.workspace_id into personal_ws_id
          from public.profiles p
          join public.workspaces w on w.id = p.workspace_id
         where p.user_id = current_user_id
           and w.type = 'personal'
         order by p.created_at
         limit 1;

        if personal_ws_id is null then
            raise exception 'Inget personligt workspace hittades.';
        end if;

        update public.workspaces
           set plan        = 'pro',
               plan_source  = 'invoice',
               max_prompts  = limits.max_prompts,
               api_enabled  = true,
               mcp_enabled  = true
         where id = personal_ws_id;

        insert into public.pro_orders (
            license_id, workspace_id, user_id, requested_plan, requested_workspaces,
            status, billing_company_name, billing_org_number, billing_address,
            billing_reference, billing_email
        ) values (
            null, personal_ws_id, current_user_id, p_requested_plan, 1,
            'pending', p_billing_company_name, p_billing_org_number, p_billing_address,
            p_billing_reference, p_billing_email
        )
        returning id into new_order_id;

        return query select new_order_id, null::uuid, personal_ws_id;
        return;
    end if;

    -- Team/Förvaltning/Kommun: skapa en ny licens + första arbetsytan.
    -- Arbetsytans namn kommer i första hand från p_workspace_name
    -- (döpt av beställaren, t.ex. "IT-teamet"), annars faller vi
    -- tillbaka på fakturans företagsnamn.
    resolved_name := coalesce(nullif(trim(p_workspace_name), ''), p_billing_company_name);

    insert into public.pro_licenses (
        plan, owner_user_id, max_workspaces, max_members_total,
        max_prompts_total, max_mcp_keys_total, plan_source
    ) values (
        p_requested_plan, current_user_id,
        least(greatest(coalesce(p_requested_workspaces, 1), 1), limits.max_workspaces),
        limits.max_members, limits.max_prompts, limits.max_mcp_keys, 'invoice'
    )
    returning id into new_license_id;

    candidate_slug := app_private.slugify_candidate(resolved_name, 'workspace');
    while exists (select 1 from public.workspaces where slug = candidate_slug) loop
        suffix := suffix + 1;
        candidate_slug := substr(app_private.slugify_candidate(resolved_name, 'workspace'), 1, 44) || '-' || suffix::text;
    end loop;

    insert into public.workspaces (
        name, slug, type, plan, owner_user_id, license_id,
        max_prompts, api_enabled, mcp_enabled
    ) values (
        coalesce(nullif(resolved_name, ''), 'Arbetsyta'), candidate_slug, 'organization',
        p_requested_plan, current_user_id, new_license_id,
        limits.max_prompts, true, true
    )
    returning id into new_workspace_id;

    insert into public.profiles (user_id, workspace_id, role)
    values (current_user_id, new_workspace_id, 'workspace_owner');

    insert into public.pro_orders (
        license_id, workspace_id, user_id, requested_plan, requested_workspaces,
        status, billing_company_name, billing_org_number, billing_address,
        billing_reference, billing_email
    ) values (
        new_license_id, new_workspace_id, current_user_id, p_requested_plan, p_requested_workspaces,
        'pending', p_billing_company_name, p_billing_org_number, p_billing_address,
        p_billing_reference, p_billing_email
    )
    returning id into new_order_id;

    return query select new_order_id, new_license_id, new_workspace_id;
end;
$$;

revoke all on function public.create_pro_order(public.workspace_plan, integer, text, text, text, text, text, text) from public;
grant execute on function public.create_pro_order(public.workspace_plan, integer, text, text, text, text, text, text) to authenticated;

-- ============================================================
-- Byt namn på en arbetsyta i efterhand (workspace_owner/admin eller
-- platform_owner). En smal RPC istället för en bred RLS UPDATE-policy
-- på hela workspaces-tabellen, så bara namnet kan ändras via klienten.
-- ============================================================
create or replace function public.rename_workspace(
    p_workspace_id uuid,
    p_name         text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    can_manage boolean := false;
    trimmed_name text := trim(coalesce(p_name, ''));
begin
    if trimmed_name = '' then
        raise exception 'Namnet får inte vara tomt.';
    end if;

    select app_private.current_user_has_workspace_role(
        p_workspace_id,
        array['workspace_owner', 'workspace_admin']::public.profile_role[]
    ) or app_private.current_user_is_platform_owner()
      into can_manage;

    if not can_manage then
        raise exception 'Du saknar behörighet att döpa om det här workspacet.';
    end if;

    update public.workspaces
       set name = trimmed_name
     where id = p_workspace_id;
end;
$$;

revoke all on function public.rename_workspace(uuid, text) from public;
grant execute on function public.rename_workspace(uuid, text) to authenticated;
