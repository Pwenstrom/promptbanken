-- Beställningsflöde: create_pro_order() aktiverar planen direkt vid
-- beställning (fakturan hanteras utanför systemet). create_workspace_under_license()
-- låter en licensägare lägga till fler arbetsytor i efterhand (Förvaltning/Kommun).

create or replace function app_private.slugify_candidate(p_name text, p_fallback_prefix text)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
    base_slug text;
begin
    base_slug := lower(regexp_replace(coalesce(p_name, ''), '[^a-z0-9]+', '-', 'gi'));
    base_slug := trim(both '-' from base_slug);
    base_slug := trim(both '-' from substr(base_slug, 1, 48));

    if length(base_slug) < 3 then
        base_slug := p_fallback_prefix || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
    end if;

    return base_slug;
end;
$$;

create or replace function public.create_pro_order(
    p_requested_plan       public.workspace_plan,
    p_requested_workspaces integer,
    p_billing_company_name text,
    p_billing_org_number   text,
    p_billing_address      text,
    p_billing_reference    text,
    p_billing_email        text
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
    insert into public.pro_licenses (
        plan, owner_user_id, max_workspaces, max_members_total,
        max_prompts_total, max_mcp_keys_total, plan_source
    ) values (
        p_requested_plan, current_user_id,
        least(greatest(coalesce(p_requested_workspaces, 1), 1), limits.max_workspaces),
        limits.max_members, limits.max_prompts, limits.max_mcp_keys, 'invoice'
    )
    returning id into new_license_id;

    candidate_slug := app_private.slugify_candidate(p_billing_company_name, 'workspace');
    while exists (select 1 from public.workspaces where slug = candidate_slug) loop
        suffix := suffix + 1;
        candidate_slug := substr(app_private.slugify_candidate(p_billing_company_name, 'workspace'), 1, 44) || '-' || suffix::text;
    end loop;

    insert into public.workspaces (
        name, slug, type, plan, owner_user_id, license_id,
        max_prompts, api_enabled, mcp_enabled
    ) values (
        coalesce(nullif(p_billing_company_name, ''), 'Arbetsyta'), candidate_slug, 'organization',
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

revoke all on function public.create_pro_order(public.workspace_plan, integer, text, text, text, text, text) from public;
grant execute on function public.create_pro_order(public.workspace_plan, integer, text, text, text, text, text) to authenticated;

-- ============================================================
-- Fler arbetsytor under en befintlig licens (Förvaltning/Kommun)
-- ============================================================
create or replace function public.create_workspace_under_license(
    p_license_id uuid,
    p_name       text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id  uuid := auth.uid();
    license_record    public.pro_licenses%rowtype;
    can_manage        boolean := false;
    workspace_count   integer;
    new_workspace_id  uuid;
    candidate_slug    text;
    suffix            integer := 0;
begin
    if current_user_id is null then
        raise exception 'Inloggning krävs.';
    end if;

    select * into license_record from public.pro_licenses where id = p_license_id;
    if not found then
        raise exception 'Licensen hittades inte.';
    end if;

    select exists (
        select 1
          from public.profiles p
          join public.workspaces w on w.id = p.workspace_id
         where w.license_id = p_license_id
           and p.user_id = current_user_id
           and p.role in ('workspace_owner', 'workspace_admin')
    ) or license_record.owner_user_id = current_user_id
      or app_private.current_user_is_platform_owner()
      into can_manage;

    if not can_manage then
        raise exception 'Du saknar behörighet att skapa arbetsytor för den här licensen.';
    end if;

    select count(*) into workspace_count
      from public.workspaces
     where license_id = p_license_id;

    if workspace_count >= license_record.max_workspaces then
        raise exception 'Licensen har nått gränsen på % arbetsytor.', license_record.max_workspaces;
    end if;

    candidate_slug := app_private.slugify_candidate(p_name, 'workspace');
    while exists (select 1 from public.workspaces where slug = candidate_slug) loop
        suffix := suffix + 1;
        candidate_slug := substr(app_private.slugify_candidate(p_name, 'workspace'), 1, 44) || '-' || suffix::text;
    end loop;

    insert into public.workspaces (
        name, slug, type, plan, owner_user_id, license_id,
        max_prompts, api_enabled, mcp_enabled
    )
    select
        coalesce(nullif(p_name, ''), 'Arbetsyta'), candidate_slug, 'organization',
        license_record.plan, current_user_id, p_license_id,
        limits.max_prompts, true, true
    from app_private.plan_limits(license_record.plan) as limits
    returning id into new_workspace_id;

    insert into public.profiles (user_id, workspace_id, role)
    values (current_user_id, new_workspace_id, 'workspace_owner');

    return new_workspace_id;
end;
$$;

revoke all on function public.create_workspace_under_license(uuid, text) from public;
grant execute on function public.create_workspace_under_license(uuid, text) to authenticated;
