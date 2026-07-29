-- Admin-MCP gap reported 2026-07-28: no way to unpublish/delete a catalog
-- prompt or package via the admin route -- slug is permanent after create,
-- test content (e.g. the vardagspaket-test package) could only be cleaned
-- up with direct Supabase access. Adds the missing write path, mirroring
-- publish_catalog_prompt's two-layer app_private/public pattern and
-- platform_owner-only authorization from 20260721150000_catalog_write_rpc_authorization.sql.

create function app_private.unpublish_catalog_prompt(p_prompt_id uuid)
returns public.catalog_prompts
language plpgsql
security definer
set search_path to ''
as $$
declare
    v_prompt public.catalog_prompts;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    update public.catalog_prompts
       set status = 'draft',
           updated_by = auth.uid()
     where id = p_prompt_id
     returning * into v_prompt;

    if not found then
        raise exception 'Ingen prompt hittades med id %', p_prompt_id;
    end if;

    return v_prompt;
end;
$$;

create function public.unpublish_catalog_prompt(p_prompt_id uuid)
returns public.catalog_prompts
language sql
security definer
set search_path to 'public', 'app_private', 'pg_temp'
as $$
    select * from app_private.unpublish_catalog_prompt(p_prompt_id);
$$;

grant execute on function public.unpublish_catalog_prompt(uuid) to anon, authenticated, service_role;


create function app_private.delete_draft_catalog_prompt(p_prompt_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
    v_status text;
    v_blocking_package text;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    select status into v_status from public.catalog_prompts where id = p_prompt_id;
    if v_status is null then
        raise exception 'Ingen prompt hittades med id %', p_prompt_id;
    end if;
    if v_status <> 'draft' then
        raise exception 'Bara draft-prompts kan tas bort. Kör unpublish_catalog_prompt först.';
    end if;

    select cpkg.slug into v_blocking_package
      from public.catalog_package_items cpi
      join public.catalog_packages cpkg on cpkg.id = cpi.package_id
     where cpi.prompt_id = p_prompt_id
     limit 1;
    if v_blocking_package is not null then
        raise exception 'Prompten ligger fortfarande i paketet %. Ta bort den därifrån först.', v_blocking_package;
    end if;

    delete from public.catalog_prompts where id = p_prompt_id;
end;
$$;

create function public.delete_draft_catalog_prompt(p_prompt_id uuid)
returns void
language sql
security definer
set search_path to 'public', 'app_private', 'pg_temp'
as $$
    select app_private.delete_draft_catalog_prompt(p_prompt_id);
$$;

grant execute on function public.delete_draft_catalog_prompt(uuid) to anon, authenticated, service_role;


create function app_private.unpublish_catalog_package(p_package_id uuid)
returns public.catalog_packages
language plpgsql
security definer
set search_path to ''
as $$
declare
    v_package public.catalog_packages;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    update public.catalog_packages
       set status = 'draft',
           updated_by = auth.uid()
     where id = p_package_id
     returning * into v_package;

    if not found then
        raise exception 'Inget paket hittades med id %', p_package_id;
    end if;

    return v_package;
end;
$$;

create function public.unpublish_catalog_package(p_package_id uuid)
returns public.catalog_packages
language sql
security definer
set search_path to 'public', 'app_private', 'pg_temp'
as $$
    select * from app_private.unpublish_catalog_package(p_package_id);
$$;

grant execute on function public.unpublish_catalog_package(uuid) to anon, authenticated, service_role;


create function app_private.delete_draft_catalog_package(p_package_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
    v_status text;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    select status into v_status from public.catalog_packages where id = p_package_id;
    if v_status is null then
        raise exception 'Inget paket hittades med id %', p_package_id;
    end if;
    if v_status <> 'draft' then
        raise exception 'Bara draft-paket kan tas bort. Kör unpublish_catalog_package först.';
    end if;

    -- catalog_package_variants och catalog_package_items har ON DELETE CASCADE
    -- på package_id, medlemsprompterna (catalog_prompts) själva berörs inte.
    delete from public.catalog_packages where id = p_package_id;
end;
$$;

create function public.delete_draft_catalog_package(p_package_id uuid)
returns void
language sql
security definer
set search_path to 'public', 'app_private', 'pg_temp'
as $$
    select app_private.delete_draft_catalog_package(p_package_id);
$$;

grant execute on function public.delete_draft_catalog_package(uuid) to anon, authenticated, service_role;
