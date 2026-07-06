-- Abstraktion: "har användaren en aktiv Pro-rättighet?". MVP-källa =
-- egen aktiv personlig Pro-yta. Framtida källor (ägar-/org-/avtalstilldelad
-- Pro) utökar BARA denna funktion; anropande kod ändras inte.

create or replace function app_private.has_active_pro_entitlement(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
          from public.workspaces w
         where w.owner_user_id = p_user_id
           and w.type = 'personal'
           and w.plan = 'pro'
           and w.status = 'active'
           and (w.plan_expires_at is null or w.plan_expires_at > now())
    );
$$;

revoke all on function app_private.has_active_pro_entitlement(uuid) from public;
grant execute on function app_private.has_active_pro_entitlement(uuid) to authenticated;
