-- Mallgräns för delade addon-ytor. Org-ytor med license_id IS NULL läser
-- gränsen från shared_workspace_addons istället för pro_licenses.

create or replace function app_private.enforce_content_access_model()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record   public.workspaces%rowtype;
    license_record     public.pro_licenses%rowtype;
    addon_record       public.shared_workspace_addons%rowtype;
    is_platform_owner  boolean;
    prompt_count       integer;
    prompt_limit       integer;
begin
    select * into workspace_record from public.workspaces where id = new.workspace_id;
    if not found then
        raise exception 'Workspace saknas.';
    end if;

    select app_private.current_user_is_platform_owner() into is_platform_owner;

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
        if workspace_record.plan = 'free' and new.visibility <> 'private' then
            raise exception 'Free-läge tillåter bara privata prompts.';
        end if;
        if workspace_record.plan = 'pro' and new.visibility not in ('private', 'workspace') then
            raise exception 'Pro-läge tillåter privata eller workspace-synliga prompts.';
        end if;
        if tg_op = 'INSERT' and new.owner_user_id is distinct from auth.uid() then
            raise exception 'Privata prompts måste ägas av användaren.';
        end if;

        select count(*) into prompt_count
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

        if workspace_record.license_id is not null then
            -- Org-licensyta: summerad gräns över syskonytor.
            select * into license_record from public.pro_licenses where id = workspace_record.license_id;

            select count(*) into prompt_count
              from public.content_items ci
             where ci.workspace_id in (select app_private.license_group_workspace_ids(new.workspace_id))
               and ci.type = 'prompt'
               and ci.status <> 'archived'
               and (tg_op = 'INSERT' or ci.id <> new.id);

            prompt_limit := coalesce(license_record.max_prompts_total, workspace_record.max_prompts);

            if prompt_count >= prompt_limit then
                raise exception 'Licensen har nått gränsen på % mallar totalt.', prompt_limit;
            end if;
        else
            -- Delad addon-yta: gräns från shared_workspace_addons.
            select * into addon_record from public.shared_workspace_addons where workspace_id = workspace_record.id;
            if not found then
                raise exception 'Organisationsytan saknar addon-konfiguration.';
            end if;

            select count(*) into prompt_count
              from public.content_items ci
             where ci.workspace_id = workspace_record.id
               and ci.type = 'prompt'
               and ci.status <> 'archived'
               and (tg_op = 'INSERT' or ci.id <> new.id);

            prompt_limit := coalesce(addon_record.max_prompts, 200);

            if prompt_count >= prompt_limit then
                raise exception 'Den delade arbetsytan har nått gränsen på % mallar.', prompt_limit;
            end if;
        end if;
    end if;

    return new;
end;
$$;

revoke all on function app_private.enforce_content_access_model() from public;
