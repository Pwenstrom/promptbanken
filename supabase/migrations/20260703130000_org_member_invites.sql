-- Medlemsinbjudan till organisations-workspaces, två parallella vägar:
-- A. invite_org_member()   -- ägaren skriver in en specifik kollegas e-post
-- B. org_join_codes + redeem_org_join_code() -- delad join-länk/kod,
--    återanvändbar av flera personer upp till platsgränsen (som redan
--    sätts av enforce_org_member_limit() från föregående migration).

-- ============================================================
-- A. Direktinbjudan via e-post
-- ============================================================
create or replace function public.invite_org_member(
    p_workspace_id uuid,
    p_email        text,
    p_role         public.profile_role default 'editor'
)
returns table(user_id uuid, workspace_id uuid, role public.profile_role)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    can_manage       boolean := false;
    target_user_id   uuid;
    workspace_record public.workspaces%rowtype;
begin
    if current_user_id is null then
        raise exception 'Inloggning krävs.';
    end if;

    select * into workspace_record from public.workspaces where id = p_workspace_id;
    if not found then
        raise exception 'Workspace hittades inte.';
    end if;

    if workspace_record.type <> 'organization' then
        raise exception 'Medlemsinbjudan gäller bara organisations-workspaces.';
    end if;

    select app_private.current_user_has_workspace_role(
        p_workspace_id,
        array['workspace_owner', 'workspace_admin']::public.profile_role[]
    ) or app_private.current_user_is_platform_owner()
      into can_manage;

    if not can_manage then
        raise exception 'Du saknar behörighet att bjuda in medlemmar till det här workspacet.';
    end if;

    if p_role in ('workspace_owner', 'platform_owner') then
        raise exception 'Kan inte bjuda in med rollen %.', p_role;
    end if;

    select u.id into target_user_id
      from auth.users u
     where lower(u.email) = lower(p_email)
     limit 1;

    if target_user_id is null then
        raise exception 'Hittade inget Promptbanken-konto med e-post %. Personen måste skapa ett konto först.', p_email;
    end if;

    if exists (select 1 from public.profiles where user_id = target_user_id and workspace_id = p_workspace_id) then
        raise exception '% är redan medlem i det här workspacet.', p_email;
    end if;

    insert into public.profiles (user_id, workspace_id, role)
    values (target_user_id, p_workspace_id, p_role);

    return query select target_user_id, p_workspace_id, p_role;
end;
$$;

revoke all on function public.invite_org_member(uuid, text, public.profile_role) from public;
grant execute on function public.invite_org_member(uuid, text, public.profile_role) to authenticated;

-- ============================================================
-- B. Delad join-länk/kod
-- ============================================================
create table if not exists public.org_join_codes (
    id           uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete cascade,
    token        text not null,
    role         public.profile_role not null default 'editor',
    status       text not null default 'active' check (status in ('active', 'revoked')),
    created_by   uuid references auth.users(id) on delete set null,
    created_at   timestamptz not null default now(),
    expires_at   timestamptz,
    constraint org_join_codes_token_key unique (token),
    constraint org_join_codes_role_check check (role not in ('workspace_owner', 'platform_owner'))
);

alter table public.org_join_codes enable row level security;

drop policy if exists "org_join_codes_managers" on public.org_join_codes;
create policy "org_join_codes_managers"
on public.org_join_codes
for all
to authenticated
using (
    app_private.current_user_has_workspace_role(
        workspace_id,
        array['workspace_owner', 'workspace_admin']::public.profile_role[]
    )
    or app_private.current_user_is_platform_owner()
)
with check (
    (
        app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin']::public.profile_role[]
        )
        or app_private.current_user_is_platform_owner()
    )
    and role not in ('workspace_owner', 'platform_owner')
);

create or replace function public.redeem_org_join_code(p_token text)
returns table(workspace_id uuid, role public.profile_role)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    code_record      public.org_join_codes%rowtype;
begin
    if current_user_id is null then
        raise exception 'Inloggning krävs.';
    end if;

    select * into code_record
      from public.org_join_codes
     where token = p_token
     for update;

    if not found then
        raise exception 'Ogiltig join-länk.';
    end if;

    if code_record.status <> 'active' then
        raise exception 'Länken är inte längre aktiv.';
    end if;

    if code_record.expires_at is not null and code_record.expires_at < now() then
        raise exception 'Länken har gått ut.';
    end if;

    if code_record.role in ('workspace_owner', 'platform_owner') then
        raise exception 'Ogiltig roll för join-länk.';
    end if;

    if exists (
        select 1 from public.profiles
        where user_id = current_user_id and workspace_id = code_record.workspace_id
    ) then
        return query select code_record.workspace_id, code_record.role;
        return;
    end if;

    insert into public.profiles (user_id, workspace_id, role)
    values (current_user_id, code_record.workspace_id, code_record.role);

    return query select code_record.workspace_id, code_record.role;
end;
$$;

revoke all on function public.redeem_org_join_code(text) from public;
grant execute on function public.redeem_org_join_code(text) to authenticated;
