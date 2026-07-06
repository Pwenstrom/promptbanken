-- create_pro_order hanterar bara pro (direkt) och plus/enterprise (förfrågan).
-- start hör nu till create_shared_workspace och avvisas här. Den gamla
-- start-grenen (som skapade pro_licenses + org-workspace) tas bort helt.
--
-- Droppa först: PostgreSQL tillåter inte att en funktions returtyp ändras via
-- create or replace, och den utplacerade versionen kan ha en annan returtyp
-- (t.ex. utan kolumnen activated). Drop + create ger rätt sluttillstånd oavsett.
drop function if exists public.create_pro_order(public.workspace_plan, integer, text, text, text, text, text, text);

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
    workspace_id uuid,
    activated    boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id  uuid := auth.uid();
    limits           record;
    new_order_id     uuid;
    personal_ws_id   uuid;
    open_requests    integer;
begin
    if current_user_id is null then
        raise exception 'Inloggning krävs.';
    end if;

    -- start = delad arbetsyta -> egen väg.
    if p_requested_plan = 'start' then
        raise exception 'Delade arbetsytor skapas via create_shared_workspace(), inte create_pro_order().';
    end if;

    select * into limits from app_private.plan_limits(p_requested_plan);

    -- Personligt Pro: aktivera direkt på anroparens egna personliga workspace.
    if p_requested_plan = 'pro' then
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

        return query select new_order_id, null::uuid, personal_ws_id, true;
        return;
    end if;

    -- Förvaltning/Kommun (plus/enterprise): skapa BARA en väntande förfrågan.
    if p_requested_plan in ('plus', 'enterprise') then
        select count(*) into open_requests
          from public.pro_orders
         where user_id = current_user_id
           and license_id is null
           and workspace_id is null
           and status = 'pending';

        if open_requests >= 3 then
            raise exception 'Du har redan flera öppna förfrågningar. Vänta tills vi kontaktat dig innan du skickar fler.';
        end if;

        insert into public.pro_orders (
            license_id, workspace_id, user_id, requested_plan, requested_workspaces,
            status, billing_company_name, billing_org_number, billing_address,
            billing_reference, billing_email, note
        ) values (
            null, null, current_user_id, p_requested_plan,
            least(greatest(coalesce(p_requested_workspaces, 1), 1), limits.max_workspaces),
            'pending', p_billing_company_name, p_billing_org_number, p_billing_address,
            p_billing_reference, p_billing_email,
            nullif(trim(p_workspace_name), '')
        )
        returning id into new_order_id;

        return query select new_order_id, null::uuid, null::uuid, false;
        return;
    end if;

    -- Övriga planer (t.ex. free) beställs inte via create_pro_order.
    raise exception 'Ogiltig plan för create_pro_order: %.', p_requested_plan;
end;
$$;

revoke all on function public.create_pro_order(public.workspace_plan, integer, text, text, text, text, text, text) from public;
grant execute on function public.create_pro_order(public.workspace_plan, integer, text, text, text, text, text, text) to authenticated;
