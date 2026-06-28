-- Promptbanken workspace access model.
-- Adds self-service personal workspaces and database-side guardrails for
-- private/free, organization, and platform-owned public prompts.

create or replace function public.ensure_personal_workspace()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    user_email text;
    workspace_id uuid;
    base_slug text;
    candidate_slug text;
    suffix integer := 0;
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
        name,
        slug,
        type,
        plan,
        owner_user_id,
        max_public_items,
        max_documents
    )
    values (
        'Privat workspace',
        candidate_slug,
        'personal',
        'free',
        current_user_id,
        3,
        3
    )
    returning id into workspace_id;

    insert into public.profiles (user_id, workspace_id, role)
    values (current_user_id, workspace_id, 'editor');

    return workspace_id;
end;
$$;

revoke all on function public.ensure_personal_workspace() from public;
grant execute on function public.ensure_personal_workspace() to authenticated;

create or replace function app_private.enforce_content_access_model()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record public.workspaces%rowtype;
    is_platform_owner boolean;
    prompt_count integer;
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
        if new.visibility <> 'private' then
            raise exception 'Free-läge tillåter bara privata prompts.';
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

        if workspace_record.plan = 'free' and prompt_count >= 3 then
            raise exception 'Free-läge är begränsat till 3 privata prompts.';
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

drop policy if exists "content_items_editors_insert_draft" on public.content_items;
create policy "content_items_editors_insert_draft"
on public.content_items
for insert
to authenticated
with check (
    status in ('draft', 'review')
    and created_by = (select auth.uid())
    and (
        owner_user_id is null
        or owner_user_id = (select auth.uid())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin']::public.profile_role[]
        ))
        or (select app_private.current_user_is_platform_owner())
    )
    and (
        (select app_private.current_user_is_platform_owner())
        or (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin', 'editor']::public.profile_role[]
        ))
    )
);

drop policy if exists "content_items_admins_update_published" on public.content_items;
create policy "content_items_admins_update_published"
on public.content_items
for update
to authenticated
using (
    (select app_private.current_user_is_platform_owner())
    or (
        visibility <> 'public'
        and (select app_private.current_user_has_workspace_role(
            workspace_id,
            array['workspace_owner', 'workspace_admin']::public.profile_role[]
        ))
    )
)
with check (
    status in ('draft', 'review', 'published', 'archived')
    and (
        (select app_private.current_user_is_platform_owner())
        or (
            visibility <> 'public'
            and (select app_private.current_user_has_workspace_role(
                workspace_id,
                array['workspace_owner', 'workspace_admin']::public.profile_role[]
            ))
        )
    )
);
