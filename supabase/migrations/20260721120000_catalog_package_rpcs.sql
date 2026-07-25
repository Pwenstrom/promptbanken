-- Write-RPC:er för katalogpaket: create, upsert variant, add prompt, update item, remove prompt, publish.
-- Publika wrappers är intentionellt okonfigurerade (revoke all) då auth/admin-MCP
-- ligger utanför denna plans omfattning — config:ing av grant för anon/authenticated
-- kommer i en framtida uppgift tillsammans med auktorisering.

create or replace function app_private.create_catalog_package(
    p_slug text,
    p_package_type text,
    p_title text,
    p_summary text,
    p_intro_text text default null,
    p_icon_key text default null,
    p_image_key text default null,
    p_color_theme text default null
)
returns public.catalog_packages
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_package public.catalog_packages;
begin
    insert into public.catalog_packages (
        slug, status, package_type, icon_key, image_key, color_theme, created_by, updated_by
    ) values (
        p_slug, 'draft', p_package_type, p_icon_key, p_image_key, p_color_theme, auth.uid(), auth.uid()
    )
    returning * into v_package;

    insert into public.catalog_package_variants (
        package_id, context_key, title, summary, intro_text
    ) values (
        v_package.id, 'generell', p_title, p_summary, p_intro_text
    );

    return v_package;
end;
$$;

create or replace function public.create_catalog_package(
    p_slug text,
    p_package_type text,
    p_title text,
    p_summary text,
    p_intro_text text default null,
    p_icon_key text default null,
    p_image_key text default null,
    p_color_theme text default null
) returns public.catalog_packages
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.create_catalog_package(
        p_slug, p_package_type, p_title, p_summary, p_intro_text, p_icon_key, p_image_key, p_color_theme
    );
$$;

revoke all on function public.create_catalog_package(text, text, text, text, text, text, text, text) from public;

create or replace function app_private.upsert_catalog_package_variant(
    p_package_id uuid,
    p_context_key text,
    p_title text,
    p_summary text,
    p_intro_text text default null,
    p_audience_label text default null
)
returns public.catalog_package_variants
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_variant public.catalog_package_variants;
begin
    insert into public.catalog_package_variants (
        package_id, context_key, title, summary, intro_text, audience_label
    ) values (
        p_package_id, p_context_key, p_title, p_summary, p_intro_text, p_audience_label
    )
    on conflict (package_id, context_key) do update
    set title = excluded.title,
        summary = excluded.summary,
        intro_text = excluded.intro_text,
        audience_label = excluded.audience_label
    returning * into v_variant;

    update public.catalog_packages
       set updated_by = auth.uid()
     where id = p_package_id;

    return v_variant;
end;
$$;

create or replace function public.upsert_catalog_package_variant(
    p_package_id uuid,
    p_context_key text,
    p_title text,
    p_summary text,
    p_intro_text text default null,
    p_audience_label text default null
) returns public.catalog_package_variants
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.upsert_catalog_package_variant(
        p_package_id, p_context_key, p_title, p_summary, p_intro_text, p_audience_label
    );
$$;

revoke all on function public.upsert_catalog_package_variant(uuid, text, text, text, text, text) from public;

create or replace function app_private.add_prompt_to_catalog_package(
    p_package_id uuid,
    p_prompt_id uuid,
    p_sort_order integer,
    p_step_title text default null,
    p_step_intro text default null,
    p_is_required boolean default true
)
returns public.catalog_package_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_item public.catalog_package_items;
begin
    insert into public.catalog_package_items (
        package_id, prompt_id, sort_order, step_title, step_intro, is_required
    ) values (
        p_package_id, p_prompt_id, p_sort_order, p_step_title, p_step_intro, p_is_required
    )
    returning * into v_item;

    return v_item;
end;
$$;

create or replace function public.add_prompt_to_catalog_package(
    p_package_id uuid,
    p_prompt_id uuid,
    p_sort_order integer,
    p_step_title text default null,
    p_step_intro text default null,
    p_is_required boolean default true
) returns public.catalog_package_items
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.add_prompt_to_catalog_package(
        p_package_id, p_prompt_id, p_sort_order, p_step_title, p_step_intro, p_is_required
    );
$$;

revoke all on function public.add_prompt_to_catalog_package(uuid, uuid, integer, text, text, boolean) from public;

create or replace function app_private.update_catalog_package_item(
    p_package_id uuid,
    p_prompt_id uuid,
    p_sort_order integer,
    p_step_title text default null,
    p_step_intro text default null,
    p_is_required boolean default true
)
returns public.catalog_package_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_item public.catalog_package_items;
begin
    update public.catalog_package_items
       set sort_order = p_sort_order,
           step_title = p_step_title,
           step_intro = p_step_intro,
           is_required = p_is_required
     where package_id = p_package_id
       and prompt_id = p_prompt_id
     returning * into v_item;

    return v_item;
end;
$$;

create or replace function public.update_catalog_package_item(
    p_package_id uuid,
    p_prompt_id uuid,
    p_sort_order integer,
    p_step_title text default null,
    p_step_intro text default null,
    p_is_required boolean default true
) returns public.catalog_package_items
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.update_catalog_package_item(
        p_package_id, p_prompt_id, p_sort_order, p_step_title, p_step_intro, p_is_required
    );
$$;

revoke all on function public.update_catalog_package_item(uuid, uuid, integer, text, text, boolean) from public;

create or replace function app_private.remove_prompt_from_catalog_package(
    p_package_id uuid,
    p_prompt_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    delete from public.catalog_package_items
     where package_id = p_package_id
       and prompt_id = p_prompt_id;
end;
$$;

create or replace function public.remove_prompt_from_catalog_package(
    p_package_id uuid,
    p_prompt_id uuid
) returns void
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select app_private.remove_prompt_from_catalog_package(p_package_id, p_prompt_id);
$$;

revoke all on function public.remove_prompt_from_catalog_package(uuid, uuid) from public;

create or replace function app_private.publish_catalog_package(p_package_id uuid)
returns public.catalog_packages
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_package public.catalog_packages;
begin
    if not exists (
        select 1 from public.catalog_package_variants
         where package_id = p_package_id and context_key = 'generell'
    ) then
        raise exception 'Paketet måste ha en generell variant innan publicering.';
    end if;

    if not exists (
        select 1 from public.catalog_package_items where package_id = p_package_id
    ) then
        raise exception 'Paketet måste innehålla minst en prompt innan publicering.';
    end if;

    if exists (
        select 1
          from public.catalog_package_items cpi
          join public.catalog_prompts cp on cp.id = cpi.prompt_id
         where cpi.package_id = p_package_id
           and cp.status <> 'published'
    ) then
        raise exception 'Alla prompts i paketet måste vara publicerade innan paketet kan publiceras.';
    end if;

    update public.catalog_packages
       set status = 'published',
           updated_by = auth.uid()
     where id = p_package_id
     returning * into v_package;

    return v_package;
end;
$$;

create or replace function public.publish_catalog_package(p_package_id uuid)
returns public.catalog_packages
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.publish_catalog_package(p_package_id);
$$;

revoke all on function public.publish_catalog_package(uuid) from public;
