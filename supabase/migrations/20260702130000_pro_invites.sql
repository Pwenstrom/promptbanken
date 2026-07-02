-- Pro-test via invite-länk (MVP innan Stripe är på plats).
--
-- Idé: platform_owner skapar en engångstoken i pro_invites. Länken
-- (invite.html?token=...) skickas till en användare, som efter inloggning
-- anropar redeem_pro_invite(token) och får Pro i N dagar. Ett dagligt
-- pg_cron-jobb nedgraderar automatiskt workspaces vars Pro-period gått ut
-- tillbaka till free, så att plan_expires_at faktiskt respekteras och inte
-- bara är ett värde ingen läser.

-- 1. Plan-expiry-fält på workspaces. Källan ('invite', 'stripe', 'admin', ...)
--    gör att framtida betalflöden kan sätta samma fält utan att kollidera.
alter table public.workspaces
    add column if not exists plan_source text,
    add column if not exists plan_expires_at timestamptz;

-- 2. Invite-tabell.
create table if not exists public.pro_invites (
    id          uuid primary key default gen_random_uuid(),
    token       text not null,
    email       text,
    plan        public.workspace_plan not null default 'pro',
    days        integer not null default 30 check (days > 0),
    status      text not null default 'unused' check (status in ('unused', 'used', 'revoked')),
    note        text,
    created_at  timestamptz not null default now(),
    expires_at  timestamptz not null default (now() + interval '14 days'),
    used_at     timestamptz,
    used_by     uuid references auth.users(id) on delete set null,
    constraint pro_invites_token_key unique (token)
);

alter table public.pro_invites enable row level security;

-- Bara plattformsägaren får se/hantera invites direkt (skapas idag manuellt
-- via SQL Editor för MVP). redeem_pro_invite() nedan körs SECURITY DEFINER
-- och kringgår RLS, så vanliga användare behöver ingen egen policy här.
drop policy if exists "pro_invites_platform_owner_all" on public.pro_invites;
create policy "pro_invites_platform_owner_all"
on public.pro_invites
for all
to authenticated
using (app_private.current_user_is_platform_owner())
with check (app_private.current_user_is_platform_owner());

-- 3. Inlösen av en invite. SECURITY DEFINER så att en vanlig inloggad
--    användare kan uppdatera workspaces/pro_invites (annars blockerat av RLS)
--    men bara på det egna, personliga workspacet.
create or replace function public.redeem_pro_invite(p_token text)
returns table(
    plan             public.workspace_plan,
    plan_expires_at  timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    invite_record   public.pro_invites%rowtype;
    target_workspace_id uuid;
begin
    if current_user_id is null then
        raise exception 'Inloggning krävs.';
    end if;

    select * into invite_record
      from public.pro_invites
     where token = p_token
     for update;

    if not found then
        raise exception 'Ogiltig invite-länk.';
    end if;

    if invite_record.status <> 'unused' then
        raise exception 'Länken är redan använd eller har återkallats.';
    end if;

    if invite_record.expires_at < now() then
        raise exception 'Länken har gått ut.';
    end if;

    select p.workspace_id into target_workspace_id
      from public.profiles p
      join public.workspaces w on w.id = p.workspace_id
     where p.user_id = current_user_id
       and w.type = 'personal'
     order by p.created_at
     limit 1;

    if target_workspace_id is null then
        raise exception 'Inget personligt workspace hittades för användaren.';
    end if;

    update public.workspaces
       set plan             = invite_record.plan,
           plan_source       = 'invite',
           plan_expires_at   = now() + make_interval(days => invite_record.days),
           max_prompts       = case when invite_record.plan = 'pro' then 100 else max_prompts end,
           api_enabled       = case when invite_record.plan = 'pro' then true else api_enabled end,
           mcp_enabled       = true
     where id = target_workspace_id;

    update public.pro_invites
       set status  = 'used',
           used_at = now(),
           used_by = current_user_id
     where id = invite_record.id;

    return query
    select w.plan, w.plan_expires_at
      from public.workspaces w
     where w.id = target_workspace_id;
end;
$$;

revoke all on function public.redeem_pro_invite(text) from public;
grant execute on function public.redeem_pro_invite(text) to authenticated;

-- 4. Dagligt pg_cron-jobb: nedgradera utgångna invite-baserade Pro-workspaces.
--    Kräver att pg_cron-tillägget är aktiverat i Supabase Dashboard
--    (Database → Extensions → pg_cron) innan denna migration körs.
create extension if not exists pg_cron with schema extensions;

create or replace function app_private.downgrade_expired_pro_workspaces()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.workspaces
       set plan            = 'free',
           plan_source      = 'expired',
           max_prompts      = 3,
           api_enabled      = false
     where plan_source = 'invite'
       and plan_expires_at is not null
       and plan_expires_at < now()
       and plan <> 'free';
end;
$$;

revoke all on function app_private.downgrade_expired_pro_workspaces() from public;

-- cron.schedule() uppdaterar jobbet om ett med samma namn redan finns,
-- så denna migration kan köras om utan att skapa dubbletter.
select cron.schedule(
    'downgrade-expired-pro-workspaces',
    '0 3 * * *',
    $$select app_private.downgrade_expired_pro_workspaces();$$
);
