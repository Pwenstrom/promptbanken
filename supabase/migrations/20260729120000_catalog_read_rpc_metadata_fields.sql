-- Fix: list_published_prompts / get_published_prompt / list_published_package_prompts
-- never selected risk_level/area/tags/output_format even though catalog_prompt_variants
-- has had these columns since 20260728120000_admin_catalog_authoring.sql. Any client
-- reading via these RPCs (the mcp_promptbanken open MCP server, script.js frontend)
-- always saw them as null/empty regardless of what admin_upsert_prompt_variant stored.
-- Reported 2026-07-28 via the admin-MCP: list_package_prompts showed empty tags/
-- risk_level/output_format for package member prompts despite admin_get_prompt
-- showing the data was stored correctly.

drop function if exists public.list_published_prompts(text[]);

create function public.list_published_prompts(p_context_keys text[] default array['generell'::text])
returns table(
    id uuid,
    slug text,
    icon_key text,
    image_key text,
    color_theme text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    risk_level text,
    area text,
    tags text[],
    output_format text
)
language sql
stable security definer
set search_path to ''
as $$
    select
        cp.id,
        cp.slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        coalesce(matched.context_key, fallback.context_key) as context_key,
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(matched.example_input, fallback.example_input) as example_input,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label,
        coalesce(matched.tone_hint, fallback.tone_hint) as tone_hint,
        coalesce(matched.parameter_schema, fallback.parameter_schema) as parameter_schema,
        coalesce(matched.default_bindings, fallback.default_bindings, '{}'::jsonb) as default_bindings,
        coalesce(matched.binding_overrides, fallback.binding_overrides, '[]'::jsonb) as binding_overrides,
        coalesce(matched.risk_level, fallback.risk_level) as risk_level,
        coalesce(matched.area, fallback.area) as area,
        coalesce(matched.tags, fallback.tags) as tags,
        coalesce(matched.output_format, fallback.output_format) as output_format
    from public.catalog_prompts cp
    left join lateral (
        select v.*
          from public.catalog_prompt_variants v
         where v.prompt_id = cp.id
           and v.context_key = any(p_context_keys)
         order by array_position(p_context_keys, v.context_key)
         limit 1
    ) matched on true
    left join public.catalog_prompt_variants fallback
      on fallback.prompt_id = cp.id
     and fallback.context_key = 'generell'
    where cp.status = 'published'
    order by cp.slug;
$$;

grant execute on function public.list_published_prompts(text[]) to anon, authenticated, service_role;


drop function if exists public.get_published_prompt(text, text[]);

create function public.get_published_prompt(p_slug text, p_context_keys text[] default array['generell'::text])
returns table(
    id uuid,
    slug text,
    icon_key text,
    image_key text,
    color_theme text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    risk_level text,
    area text,
    tags text[],
    output_format text
)
language sql
stable security definer
set search_path to ''
as $$
    select
        cp.id,
        cp.slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        v.context_key,
        v.title,
        v.summary,
        v.prompt_text,
        v.example_input,
        v.audience_label,
        v.tone_hint,
        v.parameter_schema,
        coalesce(v.default_bindings, '{}'::jsonb) as default_bindings,
        coalesce(v.binding_overrides, '[]'::jsonb) as binding_overrides,
        v.risk_level,
        v.area,
        v.tags,
        v.output_format
    from public.catalog_prompts cp
    join public.catalog_prompt_variants v on v.prompt_id = cp.id
    where cp.slug = p_slug
      and cp.status = 'published'
      and (v.context_key = any(p_context_keys) or v.context_key = 'generell')
    order by
        case when v.context_key = 'generell' then 1 else 0 end,
        coalesce(array_position(p_context_keys, v.context_key), 999);
$$;

grant execute on function public.get_published_prompt(text, text[]) to anon, authenticated, service_role;


drop function if exists public.list_published_package_prompts(text, text[]);

create function public.list_published_package_prompts(p_package_slug text, p_context_keys text[] default array['generell'::text])
returns table(
    prompt_id uuid,
    prompt_slug text,
    icon_key text,
    image_key text,
    color_theme text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    sort_order integer,
    step_title text,
    step_intro text,
    is_required boolean,
    risk_level text,
    area text,
    tags text[],
    output_format text
)
language sql
stable security definer
set search_path to ''
as $$
    select
        cp.id as prompt_id,
        cp.slug as prompt_slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        coalesce(matched.context_key, fallback.context_key) as context_key,
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(matched.example_input, fallback.example_input) as example_input,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label,
        coalesce(matched.tone_hint, fallback.tone_hint) as tone_hint,
        coalesce(matched.parameter_schema, fallback.parameter_schema) as parameter_schema,
        coalesce(matched.default_bindings, fallback.default_bindings, '{}'::jsonb) as default_bindings,
        coalesce(matched.binding_overrides, fallback.binding_overrides, '[]'::jsonb) as binding_overrides,
        cpi.sort_order,
        cpi.step_title,
        cpi.step_intro,
        cpi.is_required,
        coalesce(matched.risk_level, fallback.risk_level) as risk_level,
        coalesce(matched.area, fallback.area) as area,
        coalesce(matched.tags, fallback.tags) as tags,
        coalesce(matched.output_format, fallback.output_format) as output_format
    from public.catalog_packages cpkg
    join public.catalog_package_items cpi on cpi.package_id = cpkg.id
    join public.catalog_prompts cp on cp.id = cpi.prompt_id
    left join lateral (
        select v.*
          from public.catalog_prompt_variants v
         where v.prompt_id = cp.id
           and v.context_key = any(p_context_keys)
         order by array_position(p_context_keys, v.context_key)
         limit 1
    ) matched on true
    left join public.catalog_prompt_variants fallback
      on fallback.prompt_id = cp.id
     and fallback.context_key = 'generell'
    where cpkg.status = 'published'
      and cpkg.slug = p_package_slug
      and cp.status = 'published'
    order by cpi.sort_order;
$$;

grant execute on function public.list_published_package_prompts(text, text[]) to anon, authenticated, service_role;
