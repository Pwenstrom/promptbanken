-- Pro-köp via faktura: licenser med flera arbetsytor (Team/Förvaltning/Kommun)
-- och beställningsspårning (pro_orders).
--
-- Modell: en licens (pro_licenses) äger en eller flera workspaces (arbetsytor).
-- Free/Pro-workspaces har ingen licens (license_id null) -- oförändrat beteende.
-- Team/Förvaltning/Kommun har alltid en licens; Förvaltning/Kommun kan ha flera
-- arbetsytor under samma licens. Gränser (mallar/medlemmar/MCP-nycklar) gäller
-- summerat över alla arbetsytor med samma license_id, inte per arbetsyta.

-- ============================================================
-- 1. Nivå -> gräns-mappning (återanvänds av flera funktioner nedan)
-- ============================================================
create or replace function app_private.plan_limits(p_plan public.workspace_plan)
returns table(
    max_prompts     integer,
    max_mcp_keys    integer,
    max_members     integer,
    max_workspaces  integer
)
language sql
immutable
set search_path = ''
as $$
    select
        case p_plan
            when 'free'       then 3
            when 'pro'        then 100
            when 'start'      then 200
            when 'plus'       then 500
            when 'enterprise' then 1000
            else 3
        end as max_prompts,
        case p_plan
            when 'free'       then 1
            when 'pro'        then 5
            when 'start'      then 2
            when 'plus'       then 5
            when 'enterprise' then 10
            else 1
        end as max_mcp_keys,
        case p_plan
            when 'free'       then 1
            when 'pro'        then 1
            when 'start'      then 10
            when 'plus'       then 50
            when 'enterprise' then 250
            else 1
        end as max_members,
        case p_plan
            when 'free'       then 1
            when 'pro'        then 1
            when 'start'      then 1
            when 'plus'       then 5
            when 'enterprise' then 999999
            else 1
        end as max_workspaces;
$$;

-- ============================================================
-- 2. Licens-tabell
-- ============================================================
create table if not exists public.pro_licenses (
    id                  uuid primary key default gen_random_uuid(),
    plan                public.workspace_plan not null,
    owner_user_id       uuid not null references auth.users(id) on delete restrict,
    max_workspaces      integer not null default 1 check (max_workspaces >= 1),
    max_members_total   integer not null default 1 check (max_members_total >= 1),
    max_prompts_total   integer not null default 3 check (max_prompts_total >= 0),
    max_mcp_keys_total  integer not null default 1 check (max_mcp_keys_total >= 0),
    plan_source         text,
    plan_expires_at     timestamptz,
    status              text not null default 'active' check (status in ('active', 'cancelled')),
    created_at          timestamptz not null default now()
);

alter table public.pro_licenses enable row level security;

drop policy if exists "pro_licenses_owner_read" on public.pro_licenses;
create policy "pro_licenses_owner_read"
on public.pro_licenses
for select
to authenticated
using (owner_user_id = (select auth.uid()) or app_private.current_user_is_platform_owner());

drop policy if exists "pro_licenses_platform_owner_write" on public.pro_licenses;
create policy "pro_licenses_platform_owner_write"
on public.pro_licenses
for all
to authenticated
using (app_private.current_user_is_platform_owner())
with check (app_private.current_user_is_platform_owner());

-- ============================================================
-- 3. workspaces.license_id -- kopplar en arbetsyta till en licens
-- ============================================================
alter table public.workspaces
    add column if not exists license_id uuid references public.pro_licenses(id) on delete set null;

-- ============================================================
-- 4. Hjälpfunktion: alla arbetsytor som delar samma licens som ett
--    givet workspace (eller bara sig själv om ingen licens finns).
-- ============================================================
create or replace function app_private.license_group_workspace_ids(p_workspace_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
    select distinct w2.id
      from public.workspaces w1
      join public.workspaces w2
        on (w1.license_id is not null and w2.license_id = w1.license_id)
        or w2.id = w1.id
     where w1.id = p_workspace_id;
$$;

revoke all on function app_private.license_group_workspace_ids(uuid) from public;
grant execute on function app_private.license_group_workspace_ids(uuid) to authenticated;

-- ============================================================
-- 5. Bredda "har premiumåtkomst" och mallgränsen till licens-medvetna
--    org-nivåer (start/plus/enterprise), inte bara 'pro'.
-- ============================================================
create or replace function app_private.enforce_content_access_model()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record   public.workspaces%rowtype;
    license_record     public.pro_licenses%rowtype;
    is_platform_owner  boolean;
    prompt_count       integer;
    prompt_limit       integer;
begin
    select * into workspace_record
      from public.workspaces
     where id = new.workspace_id;

    if not found then
        raise exception 'Workspace saknas.';
    end if;

    select app_private.current_user_is_platform_owner()
      into is_platform_owner;

    if new.type <> 'prompt' then
        return new;
    end if;

    if tg_op = 'INSERT' and new.created_by is distinct from auth.uid() then
        raise exception 'Prompts måste skapas av inloggad användare.';
    end if;

    if tg_op = 'INSERT' and new.owner_user_id is null then
        new.owner_user_id := auth.uid();
    end if;

    if new.visibility = 'public' and not is_platform_owner then
        raise exception 'Endast plattformsadmin kan skapa publika prompts.';
    end if;

    if workspace_record.type = 'personal' then
        -- Free: private only. Pro: private eller workspace.
        if workspace_record.plan = 'free' and new.visibility <> 'private' then
            raise exception 'Free-läge tillåter bara privata prompts.';
        end if;

        if workspace_record.plan = 'pro' and new.visibility not in ('private', 'workspace') then
            raise exception 'Pro-läge tillåter privata eller workspace-synliga prompts.';
        end if;

        if tg_op = 'INSERT' and new.owner_user_id is distinct from auth.uid() then
            raise exception 'Privata prompts måste ägas av användaren.';
        end if;

        select count(*)
          into prompt_count
          from public.content_items ci
         where ci.workspace_id = new.workspace_id
           and ci.type = 'prompt'
           and ci.owner_user_id = auth.uid()
           and ci.status <> 'archived'
           and (tg_op = 'INSERT' or ci.id <> new.id);

        if prompt_count >= workspace_record.max_prompts then
            raise exception 'Du har nått gränsen på % prompts för %-planen.', workspace_record.max_prompts, workspace_record.plan;
        end if;

    elsif workspace_record.type = 'organization' and not is_platform_owner then
        if new.visibility <> 'workspace' then
            raise exception 'Organisationsprompts måste vara synliga inom organisationen.';
        end if;

        -- Mallgräns summerad över alla arbetsytor under samma licens.
        if workspace_record.license_id is not null then
            select * into license_record
              from public.pro_licenses
             where id = workspace_record.license_id;

            select count(*)
              into prompt_count
              from public.content_items ci
             where ci.workspace_id in (select app_private.license_group_workspace_ids(new.workspace_id))
               and ci.type = 'prompt'
               and ci.status <> 'archived'
               and (tg_op = 'INSERT' or ci.id <> new.id);

            prompt_limit := coalesce(license_record.max_prompts_total, workspace_record.max_prompts);

            if prompt_count >= prompt_limit then
                raise exception 'Licensen har nått gränsen på % mallar totalt.', prompt_limit;
            end if;
        end if;
    end if;

    return new;
end;
$$;

revoke all on function app_private.enforce_content_access_model() from public;

-- ============================================================
-- 6. MCP-nyckelgräns: licens-medveten (workspace-nycklar summeras
--    över hela licensen), personliga workspaces oförändrade.
-- ============================================================
create or replace function app_private.enforce_mcp_key_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record public.workspaces%rowtype;
    license_record   public.pro_licenses%rowtype;
    existing_count   integer;
    key_limit        integer;
begin
    if not (new.scopes @> array['mcp']::text[]) then
        return new;
    end if;

    select * into workspace_record
      from public.workspaces
     where id = new.workspace_id;

    if workspace_record.type = 'personal' then
        key_limit := case when workspace_record.plan = 'pro' then 5 else 1 end;

        select count(*) into existing_count
          from public.api_keys
         where workspace_id = new.workspace_id
           and scopes @> array['mcp']::text[]
           and revoked_at is null;

        if existing_count >= key_limit then
            raise exception 'Personliga konton på %-planen kan ha max % aktiva MCP-nycklar.', workspace_record.plan, key_limit;
        end if;

    elsif workspace_record.type = 'organization' and workspace_record.license_id is not null then
        select * into license_record
          from public.pro_licenses
         where id = workspace_record.license_id;

        select count(*) into existing_count
          from public.api_keys k
         where k.workspace_id in (select app_private.license_group_workspace_ids(new.workspace_id))
           and k.scopes @> array['mcp']::text[]
           and k.revoked_at is null;

        key_limit := coalesce(license_record.max_mcp_keys_total, 1);

        if existing_count >= key_limit then
            raise exception 'Licensen har nått gränsen på % MCP-nycklar totalt.', key_limit;
        end if;
    end if;

    return new;
end;
$$;

revoke all on function app_private.enforce_mcp_key_limit() from public;

-- ============================================================
-- 7. Medlemsgräns per licens (Team/Förvaltning/Kommun), summerad
--    över alla arbetsytor under samma licens.
-- ============================================================
create or replace function app_private.enforce_org_member_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record public.workspaces%rowtype;
    license_record   public.pro_licenses%rowtype;
    existing_count   integer;
begin
    select * into workspace_record
      from public.workspaces
     where id = new.workspace_id;

    if workspace_record.type <> 'organization' or workspace_record.license_id is null then
        return new;
    end if;

    select * into license_record
      from public.pro_licenses
     where id = workspace_record.license_id;

    select count(*) into existing_count
      from public.profiles p
     where p.workspace_id in (select app_private.license_group_workspace_ids(new.workspace_id));

    if existing_count >= coalesce(license_record.max_members_total, 1) then
        raise exception 'Licensen har nått gränsen på % medlemmar totalt.', license_record.max_members_total;
    end if;

    return new;
end;
$$;

revoke all on function app_private.enforce_org_member_limit() from public;

drop trigger if exists enforce_org_member_limit on public.profiles;
create trigger enforce_org_member_limit
before insert on public.profiles
for each row execute function app_private.enforce_org_member_limit();

-- ============================================================
-- 8. Bredda premiummallar-åtkomst (list_pro_templates /
--    get_pro_templates_for_mcp_key) till start/plus/enterprise.
-- ============================================================
create or replace function public.list_pro_templates()
returns table(
    id                uuid,
    area              text,
    area_label        text,
    title             text,
    syfte             text,
    output_format     text,
    prompt_text       text,
    tags              text[],
    risk_level        public.content_risk_level,
    security_examples text[],
    sort_order        integer,
    is_unlocked       boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    has_pro         boolean := false;
begin
    if current_user_id is not null then
        select exists (
            select 1
              from public.profiles p
              join public.workspaces w on w.id = p.workspace_id
             where p.user_id = current_user_id
               and w.plan in ('pro', 'start', 'plus', 'enterprise')
               and w.status = 'active'
               and (w.plan_expires_at is null or w.plan_expires_at > now())
        ) into has_pro;
    end if;

    return query
    select
        t.id,
        t.area,
        t.area_label,
        t.title,
        t.syfte,
        t.output_format,
        case when has_pro then t.prompt_text else null end,
        t.tags,
        t.risk_level,
        t.security_examples,
        t.sort_order,
        has_pro
    from public.pro_prompt_templates t
    order by t.sort_order;
end;
$$;

create or replace function public.get_pro_templates_for_mcp_key(p_key_hash text)
returns table(
    id                uuid,
    area              text,
    area_label        text,
    title             text,
    syfte             text,
    output_format     text,
    prompt_text       text,
    tags              text[],
    risk_level        public.content_risk_level,
    security_examples text[],
    sort_order        integer,
    is_unlocked       boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    has_pro boolean := false;
begin
    select exists (
        select 1
          from public.api_keys k
          join public.workspaces w on w.id = k.workspace_id
         where k.key_hash    = p_key_hash
           and k.revoked_at  is null
           and k.scopes      @> array['mcp']::text[]
           and w.mcp_enabled = true
           and w.status      = 'active'
           and w.plan        in ('pro', 'start', 'plus', 'enterprise')
           and (w.plan_expires_at is null or w.plan_expires_at > now())
    ) into has_pro;

    return query
    select
        t.id,
        t.area,
        t.area_label,
        t.title,
        t.syfte,
        t.output_format,
        case when has_pro then t.prompt_text else null end,
        t.tags,
        t.risk_level,
        t.security_examples,
        t.sort_order,
        has_pro
    from public.pro_prompt_templates t
    order by t.sort_order;
end;
$$;

-- ============================================================
-- 9. Beställningar (pro_orders)
-- ============================================================
create table if not exists public.pro_orders (
    id                    uuid primary key default gen_random_uuid(),
    license_id            uuid references public.pro_licenses(id) on delete set null,
    workspace_id          uuid references public.workspaces(id) on delete set null,
    user_id               uuid not null references auth.users(id) on delete restrict,
    requested_plan        public.workspace_plan not null,
    requested_workspaces  integer not null default 1 check (requested_workspaces >= 1),
    status                text not null default 'pending' check (status in ('pending', 'invoiced', 'paid', 'overdue', 'cancelled')),
    billing_company_name  text,
    billing_org_number    text,
    billing_address       text,
    billing_reference     text,
    billing_email         text,
    note                  text,
    created_at            timestamptz not null default now(),
    due_date              timestamptz
);

alter table public.pro_orders enable row level security;

drop policy if exists "pro_orders_owner_read" on public.pro_orders;
create policy "pro_orders_owner_read"
on public.pro_orders
for select
to authenticated
using (user_id = (select auth.uid()) or app_private.current_user_is_platform_owner());

drop policy if exists "pro_orders_platform_owner_write" on public.pro_orders;
create policy "pro_orders_platform_owner_write"
on public.pro_orders
for all
to authenticated
using (app_private.current_user_is_platform_owner())
with check (app_private.current_user_is_platform_owner());

-- Beställaren får skapa sin egen order (create_pro_order() nedan gör
-- själva jobbet som SECURITY DEFINER, men RLS måste ändå tillåta insert
-- eftersom PostgREST/policyn kollas även för SECURITY DEFINER-funktionens
-- ägare om den inte är superuser -- håll det permissivt här och lita på
-- att create_pro_order() validerar allt innan den skriver).
drop policy if exists "pro_orders_owner_insert" on public.pro_orders;
create policy "pro_orders_owner_insert"
on public.pro_orders
for insert
to authenticated
with check (user_id = (select auth.uid()));
