-- Define concrete Free and Pro plan limits.
-- Free:  3 prompts, mcp_enabled, no api_enabled, private visibility only.
-- Pro:  100 prompts, mcp_enabled, api_enabled, private + workspace visibility.

-- 1. Add max_prompts column (drives the prompt cap in the trigger).
alter table public.workspaces
    add column if not exists max_prompts integer not null default 3
        check (max_prompts >= 0);

-- 2. Backfill: pro workspaces get 100 prompts and api access.
update public.workspaces
   set max_prompts  = 100,
       api_enabled  = true,
       mcp_enabled  = true
 where plan = 'pro';

-- 3. Free personal workspaces get mcp access.
update public.workspaces
   set mcp_enabled = true
 where plan = 'free' and type = 'personal';

-- 4. Rebuild ensure_personal_workspace() with explicit plan defaults.
create or replace function public.ensure_personal_workspace()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    user_email      text;
    workspace_id    uuid;
    base_slug       text;
    candidate_slug  text;
    suffix          integer := 0;
begin
    if current_user_id is null then
        raise exception 'Authentication required';
    end if;

    select p.workspace_id
      into workspace_id
      from public.profiles p
      join public.workspaces w on w.id = p.workspace_id
     where p.user_id = current_user_id
       and w.type = 'personal'
     order by p.created_at
     limit 1;

    if workspace_id is not null then
        return workspace_id;
    end if;

    select u.email into user_email
      from auth.users u
     where u.id = current_user_id;

    base_slug := lower(regexp_replace(coalesce(split_part(user_email, '@', 1), 'user'), '[^a-z0-9]+', '-', 'g'));
    base_slug := trim(both '-' from base_slug);
    if length(base_slug) < 3 then
        base_slug := 'user-' || substr(replace(current_user_id::text, '-', ''), 1, 8);
    end if;
    base_slug := substr(base_slug, 1, 48);
    candidate_slug := base_slug;

    while exists (select 1 from public.workspaces where slug = candidate_slug) loop
        suffix := suffix + 1;
        candidate_slug := substr(base_slug, 1, 48) || '-' || suffix::text;
    end loop;

    insert into public.workspaces (
        name, slug, type, plan, owner_user_id,
        max_prompts, max_public_items, max_documents,
        api_enabled, mcp_enabled
    )
    values (
        'Privat workspace', candidate_slug, 'personal', 'free', current_user_id,
        3, 3, 3,
        false, true
    )
    returning id into workspace_id;

    insert into public.profiles (user_id, workspace_id, role)
    values (current_user_id, workspace_id, 'editor');

    return workspace_id;
end;
$$;

revoke all on function public.ensure_personal_workspace() from public;
grant execute on function public.ensure_personal_workspace() to authenticated;

-- 5. Rebuild enforce_content_access_model() using max_prompts and plan-aware visibility.
create or replace function app_private.enforce_content_access_model()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record   public.workspaces%rowtype;
    is_platform_owner  boolean;
    prompt_count       integer;
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
        -- Free: private only. Pro: private or workspace.
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
    end if;

    return new;
end;
$$;

revoke all on function app_private.enforce_content_access_model() from public;

drop trigger if exists enforce_content_access_model on public.content_items;
create trigger enforce_content_access_model
before insert or update on public.content_items
for each row execute function app_private.enforce_content_access_model();

-- 6. MCP-nyckel: max 1 per personligt workspace.
--    MCP-nycklar identifieras genom scopes = '{mcp}'.
create or replace function app_private.enforce_mcp_key_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record public.workspaces%rowtype;
    existing_count   integer;
begin
    if new.scopes @> array['mcp']::text[] then
        select * into workspace_record
          from public.workspaces
         where id = new.workspace_id;

        if workspace_record.type = 'personal' then
            select count(*) into existing_count
              from public.api_keys
             where workspace_id = new.workspace_id
               and scopes @> array['mcp']::text[]
               and revoked_at is null;

            if existing_count >= 1 then
                raise exception 'Personliga konton kan bara ha en aktiv MCP-nyckel.';
            end if;
        end if;
    end if;
    return new;
end;
$$;

revoke all on function app_private.enforce_mcp_key_limit() from public;

drop trigger if exists enforce_mcp_key_limit on public.api_keys;
create trigger enforce_mcp_key_limit
before insert on public.api_keys
for each row execute function app_private.enforce_mcp_key_limit();
