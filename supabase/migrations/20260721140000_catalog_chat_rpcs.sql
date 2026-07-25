-- Chat-driven draft creation RPC:er för prompts och paket.
-- Dessa wrappar kombinerar Task 2 och Task 3:s write-RPC:er för att möjliggöra
-- en-anropsskapandet av prompts eller hela paket-med-prompts från en chat.
-- Publika wrappers är intentionellt okonfigurerade (revoke all) då auth/admin-MCP
-- ligger utanför denna plans omfattning — config:ing av grant för anon/authenticated
-- kommer i en framtida uppgift tillsammans med auktorisering.

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

create or replace function public.create_prompt_draft_from_chat(
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
) returns public.catalog_prompts
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.create_prompt_draft_from_chat(
        p_slug, p_title, p_summary, p_prompt_text, p_icon_key, p_image_key, p_color_theme,
        p_example_input, p_audience_label, p_tone_hint, p_suggested_variables
    );
$$;

revoke all on function public.create_prompt_draft_from_chat(text, text, text, text, text, text, text, text, text, text, jsonb) from public;

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

create or replace function public.create_package_draft_from_chat(
    p_slug text,
    p_package_type text,
    p_title text,
    p_summary text,
    p_intro_text text default null,
    p_icon_key text default null,
    p_image_key text default null,
    p_color_theme text default null,
    p_prompts jsonb default '[]'::jsonb
) returns public.catalog_packages
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.create_package_draft_from_chat(
        p_slug, p_package_type, p_title, p_summary, p_intro_text, p_icon_key, p_image_key, p_color_theme, p_prompts
    );
$$;

revoke all on function public.create_package_draft_from_chat(text, text, text, text, text, text, text, text, jsonb) from public;
