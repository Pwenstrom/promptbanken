-- 20260716101000_valvet_item_limit_trigger.sql
create or replace function app_private.enforce_vault_item_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record public.workspaces%rowtype;
    item_count        integer;
    item_limit         integer;
    becomes_active     boolean;
begin
    if new.module <> 'valvet' then
        return new;
    end if;

    if new.visibility <> 'private' then
        raise exception 'Valvet stödjer bara privata insättningar i denna version.';
    end if;

    if tg_op = 'INSERT' and new.created_by is distinct from auth.uid() then
        raise exception 'Insättningar måste skapas av inloggad användare.';
    end if;

    if tg_op = 'INSERT' and new.owner_user_id is null then
        new.owner_user_id := auth.uid();
    end if;

    if tg_op = 'INSERT' and new.owner_user_id is distinct from auth.uid() then
        raise exception 'Insättningar måste ägas av användaren som skapar dem.';
    end if;

    becomes_active := (tg_op = 'INSERT' and new.status <> 'archived')
        or (tg_op = 'UPDATE' and old.status = 'archived' and new.status <> 'archived');

    if becomes_active then
        select * into workspace_record from public.workspaces where id = new.workspace_id;
        if not found then
            raise exception 'Workspace saknas.';
        end if;

        item_limit := case when workspace_record.plan = 'free' then 50 else 1000 end;

        select count(*) into item_count
          from public.content_items ci
         where ci.workspace_id = new.workspace_id
           and ci.module = 'valvet'
           and ci.owner_user_id = new.owner_user_id
           and ci.status <> 'archived'
           and (tg_op = 'INSERT' or ci.id <> new.id);

        if item_count >= item_limit then
            raise exception 'Du har nått gränsen på % insättningar i Valvet.', item_limit;
        end if;
    end if;

    return new;
end;
$$;

revoke all on function app_private.enforce_vault_item_limit() from public;

drop trigger if exists enforce_vault_item_limit on public.content_items;
create trigger enforce_vault_item_limit
before insert or update on public.content_items
for each row execute function app_private.enforce_vault_item_limit();
