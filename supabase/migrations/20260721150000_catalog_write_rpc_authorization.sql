-- Auktorisering för katalogens write-RPC:er (Task 2/3/5), inför Task 6:s admin-UI.
-- Task 2/3/5:s publika wrappers lämnades medvetet orgranterade (revoke all,
-- ingen grant) eftersom funktionerna saknade egen behörighetskontroll och
-- admin-MCP-auth låg utanför planens ursprungliga omfattning. Task 6 bygger en
-- admin-UI som anropar dessa RPC:er direkt från klienten (supabase.rpc), vilket
-- kräver att de faktiskt går att anropa. Beslut (Peter, 2026-07-25): återanvänd
-- den redan existerande `app_private.current_user_is_platform_owner()`-kollen
-- (samma modell som redan skyddar t.ex. synlighetsfältet i admin.js) i varje
-- app_private-funktion, och bevilja execute på motsvarande publika wrapper till
-- `authenticated`. Frontend-döljning (data-platform-only) är UX, inte skydd --
-- skyddet sitter i app_private-funktionerna själva och gäller alla anropsvägar.

-- Task 2: promptflödet

create or replace function app_private.create_catalog_prompt(
    p_slug text,
    p_title text,
    p_summary text,
    p_prompt_text text,
    p_icon_key text default null,
    p_image_key text default null,
    p_color_theme text default null
)
returns public.catalog_prompts
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_prompt public.catalog_prompts;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    insert into public.catalog_prompts (
        slug, status, prompt_kind, icon_key, image_key, color_theme, created_by, updated_by
    ) values (
        p_slug, 'draft', 'prompt', p_icon_key, p_image_key, p_color_theme, auth.uid(), auth.uid()
    )
    returning * into v_prompt;

    insert into public.catalog_prompt_variants (
        prompt_id, context_key, title, summary, prompt_text
    ) values (
        v_prompt.id, 'generell', p_title, p_summary, p_prompt_text
    );

    return v_prompt;
end;
$$;

grant execute on function public.create_catalog_prompt(text, text, text, text, text, text, text) to authenticated;

create or replace function app_private.upsert_catalog_prompt_variant(
    p_prompt_id uuid,
    p_context_key text,
    p_title text,
    p_summary text,
    p_prompt_text text,
    p_example_input text default null,
    p_audience_label text default null,
    p_tone_hint text default null,
    p_context_notes text default null,
    p_suggested_variables jsonb default '{}'::jsonb
)
returns public.catalog_prompt_variants
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_variant public.catalog_prompt_variants;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    insert into public.catalog_prompt_variants (
        prompt_id, context_key, title, summary, prompt_text, example_input,
        audience_label, tone_hint, context_notes, suggested_variables
    ) values (
        p_prompt_id, p_context_key, p_title, p_summary, p_prompt_text, p_example_input,
        p_audience_label, p_tone_hint, p_context_notes, coalesce(p_suggested_variables, '{}'::jsonb)
    )
    on conflict (prompt_id, context_key) do update
    set title = excluded.title,
        summary = excluded.summary,
        prompt_text = excluded.prompt_text,
        example_input = excluded.example_input,
        audience_label = excluded.audience_label,
        tone_hint = excluded.tone_hint,
        context_notes = excluded.context_notes,
        suggested_variables = excluded.suggested_variables
    returning * into v_variant;

    update public.catalog_prompts
       set updated_by = auth.uid()
     where id = p_prompt_id;

    return v_variant;
end;
$$;

grant execute on function public.upsert_catalog_prompt_variant(uuid, text, text, text, text, text, text, text, text, jsonb) to authenticated;

create or replace function app_private.publish_catalog_prompt(p_prompt_id uuid)
returns public.catalog_prompts
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_prompt public.catalog_prompts;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    if not exists (
        select 1
          from public.catalog_prompt_variants
         where prompt_id = p_prompt_id
           and context_key = 'generell'
    ) then
        raise exception 'Prompten måste ha en generell variant innan publicering.';
    end if;

    update public.catalog_prompts
       set status = 'published',
           updated_by = auth.uid()
     where id = p_prompt_id
     returning * into v_prompt;

    return v_prompt;
end;
$$;

grant execute on function public.publish_catalog_prompt(uuid) to authenticated;

-- Task 3: paketflödet

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
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

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

grant execute on function public.create_catalog_package(text, text, text, text, text, text, text, text) to authenticated;

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
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

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

grant execute on function public.upsert_catalog_package_variant(uuid, text, text, text, text, text) to authenticated;

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
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    insert into public.catalog_package_items (
        package_id, prompt_id, sort_order, step_title, step_intro, is_required
    ) values (
        p_package_id, p_prompt_id, p_sort_order, p_step_title, p_step_intro, p_is_required
    )
    returning * into v_item;

    return v_item;
end;
$$;

grant execute on function public.add_prompt_to_catalog_package(uuid, uuid, integer, text, text, boolean) to authenticated;

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
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

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

grant execute on function public.update_catalog_package_item(uuid, uuid, integer, text, text, boolean) to authenticated;

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
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    delete from public.catalog_package_items
     where package_id = p_package_id
       and prompt_id = p_prompt_id;
end;
$$;

grant execute on function public.remove_prompt_from_catalog_package(uuid, uuid) to authenticated;

create or replace function app_private.publish_catalog_package(p_package_id uuid)
returns public.catalog_packages
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_package public.catalog_packages;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

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

grant execute on function public.publish_catalog_package(uuid) to authenticated;

-- Task 5: chattskapande

create or replace function app_private.create_prompt_draft_from_chat(
    p_slug text,
    p_title text,
    p_summary text,
    p_prompt_text text,
    p_icon_key text default null,
    p_image_key text default null,
    p_color_theme text default null,
    p_example_input text default null,
    p_audience_label text default null,
    p_tone_hint text default null,
    p_suggested_variables jsonb default '{}'::jsonb
)
returns public.catalog_prompts
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_prompt public.catalog_prompts;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    v_prompt := app_private.create_catalog_prompt(
        p_slug, p_title, p_summary, p_prompt_text, p_icon_key, p_image_key, p_color_theme
    );

    perform app_private.upsert_catalog_prompt_variant(
        v_prompt.id, 'generell', p_title, p_summary, p_prompt_text,
        p_example_input, p_audience_label, p_tone_hint, null, p_suggested_variables
    );

    return v_prompt;
end;
$$;

grant execute on function public.create_prompt_draft_from_chat(text, text, text, text, text, text, text, text, text, text, jsonb) to authenticated;

create or replace function app_private.create_package_draft_from_chat(
    p_slug text,
    p_package_type text,
    p_title text,
    p_summary text,
    p_intro_text text default null,
    p_icon_key text default null,
    p_image_key text default null,
    p_color_theme text default null,
    p_prompts jsonb default '[]'::jsonb
)
returns public.catalog_packages
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_package public.catalog_packages;
    v_prompt public.catalog_prompts;
    v_item jsonb;
    v_sort_order integer := 0;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    v_package := app_private.create_catalog_package(
        p_slug, p_package_type, p_title, p_summary, p_intro_text, p_icon_key, p_image_key, p_color_theme
    );

    for v_item in select * from jsonb_array_elements(p_prompts)
    loop
        v_sort_order := v_sort_order + 1;

        v_prompt := app_private.create_catalog_prompt(
            v_item->>'slug',
            v_item->>'title',
            v_item->>'summary',
            v_item->>'prompt_text'
        );

        perform app_private.add_prompt_to_catalog_package(
            v_package.id, v_prompt.id, v_sort_order
        );
    end loop;

    return v_package;
end;
$$;

grant execute on function public.create_package_draft_from_chat(text, text, text, text, text, text, text, text, jsonb) to authenticated;
