-- Delad addon-yta: en workspaces-rad (type='organization', plan='start',
-- license_id=null) diskriminerad av en rad här. Helt skilt från pro_licenses.

create table if not exists public.shared_workspace_addons (
    id                     uuid primary key default gen_random_uuid(),
    workspace_id           uuid not null unique references public.workspaces(id) on delete cascade,
    owner_user_id          uuid not null references auth.users(id) on delete restrict,
    billing_owner_user_id  uuid not null references auth.users(id) on delete restrict,
    max_members            integer not null default 5  check (max_members >= 1),   -- inkl. ägare
    max_prompts            integer not null default 200 check (max_prompts >= 0),
    price_per_month        integer not null default 199 check (price_per_month >= 0),
    plan_source            text,
    plan_expires_at        timestamptz,
    status                 text not null default 'active' check (status in ('active', 'cancelled')),
    created_at             timestamptz not null default now()
);

alter table public.shared_workspace_addons enable row level security;

drop policy if exists "swa_owner_read" on public.shared_workspace_addons;
create policy "swa_owner_read"
on public.shared_workspace_addons
for select
to authenticated
using (
    owner_user_id = (select auth.uid())
    or billing_owner_user_id = (select auth.uid())
    or (select app_private.current_user_is_platform_owner())
);

drop policy if exists "swa_platform_owner_write" on public.shared_workspace_addons;
create policy "swa_platform_owner_write"
on public.shared_workspace_addons
for all
to authenticated
using ((select app_private.current_user_is_platform_owner()))
with check ((select app_private.current_user_is_platform_owner()));
