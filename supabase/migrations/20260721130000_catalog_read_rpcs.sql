-- 20260721130000_catalog_read_rpcs.sql
-- Läs-RPC:er för publicerad katalog med kontextfallback. Dessa funktioner
-- exponerar redan-publicerat kataloginnehål för både webb och MCP, med
-- automatisk fallback till 'generell'-varianten när en specifik kontext saknas.

create or replace function public.list_published_prompts(p_context_key text)
returns table (
    id uuid,
    slug text,
    icon_key text,
    image_key text,
    color_theme text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cp.id,
        cp.slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        coalesce(requested.title, fallback.title) as title,
        coalesce(requested.summary, fallback.summary) as summary,
        coalesce(requested.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(requested.example_input, fallback.example_input) as example_input,
        coalesce(requested.audience_label, fallback.audience_label) as audience_label,
        coalesce(requested.tone_hint, fallback.tone_hint) as tone_hint
    from public.catalog_prompts cp
    left join public.catalog_prompt_variants requested
      on requested.prompt_id = cp.id
     and requested.context_key = p_context_key
    left join public.catalog_prompt_variants fallback
      on fallback.prompt_id = cp.id
     and fallback.context_key = 'generell'
    where cp.status = 'published'
    order by cp.slug;
$$;

revoke all on function public.list_published_prompts(text) from public;
grant execute on function public.list_published_prompts(text) to anon, authenticated;

create or replace function public.get_published_prompt(p_slug text, p_context_key text)
returns table (
    id uuid,
    slug text,
    icon_key text,
    image_key text,
    color_theme text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cp.id,
        cp.slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        coalesce(requested.title, fallback.title) as title,
        coalesce(requested.summary, fallback.summary) as summary,
        coalesce(requested.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(requested.example_input, fallback.example_input) as example_input,
        coalesce(requested.audience_label, fallback.audience_label) as audience_label,
        coalesce(requested.tone_hint, fallback.tone_hint) as tone_hint
    from public.catalog_prompts cp
    left join public.catalog_prompt_variants requested
      on requested.prompt_id = cp.id
     and requested.context_key = p_context_key
    left join public.catalog_prompt_variants fallback
      on fallback.prompt_id = cp.id
     and fallback.context_key = 'generell'
    where cp.status = 'published'
      and cp.slug = p_slug;
$$;

revoke all on function public.get_published_prompt(text, text) from public;
grant execute on function public.get_published_prompt(text, text) to anon, authenticated;

create or replace function public.list_published_packages(p_context_key text, p_package_type text default null)
returns table (
    id uuid,
    slug text,
    package_type text,
    icon_key text,
    image_key text,
    color_theme text,
    title text,
    summary text,
    intro_text text,
    audience_label text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cpkg.id,
        cpkg.slug,
        cpkg.package_type,
        cpkg.icon_key,
        cpkg.image_key,
        cpkg.color_theme,
        coalesce(requested.title, fallback.title) as title,
        coalesce(requested.summary, fallback.summary) as summary,
        coalesce(requested.intro_text, fallback.intro_text) as intro_text,
        coalesce(requested.audience_label, fallback.audience_label) as audience_label
    from public.catalog_packages cpkg
    left join public.catalog_package_variants requested
      on requested.package_id = cpkg.id
     and requested.context_key = p_context_key
    left join public.catalog_package_variants fallback
      on fallback.package_id = cpkg.id
     and fallback.context_key = 'generell'
    where cpkg.status = 'published'
      and (p_package_type is null or cpkg.package_type = p_package_type)
    order by cpkg.slug;
$$;

revoke all on function public.list_published_packages(text, text) from public;
grant execute on function public.list_published_packages(text, text) to anon, authenticated;

create or replace function public.get_published_package(p_slug text, p_context_key text)
returns table (
    id uuid,
    slug text,
    package_type text,
    icon_key text,
    image_key text,
    color_theme text,
    title text,
    summary text,
    intro_text text,
    audience_label text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cpkg.id,
        cpkg.slug,
        cpkg.package_type,
        cpkg.icon_key,
        cpkg.image_key,
        cpkg.color_theme,
        coalesce(requested.title, fallback.title) as title,
        coalesce(requested.summary, fallback.summary) as summary,
        coalesce(requested.intro_text, fallback.intro_text) as intro_text,
        coalesce(requested.audience_label, fallback.audience_label) as audience_label
    from public.catalog_packages cpkg
    left join public.catalog_package_variants requested
      on requested.package_id = cpkg.id
     and requested.context_key = p_context_key
    left join public.catalog_package_variants fallback
      on fallback.package_id = cpkg.id
     and fallback.context_key = 'generell'
    where cpkg.status = 'published'
      and cpkg.slug = p_slug;
$$;

revoke all on function public.get_published_package(text, text) from public;
grant execute on function public.get_published_package(text, text) to anon, authenticated;

create or replace function public.list_published_package_prompts(p_package_slug text, p_context_key text)
returns table (
    prompt_id uuid,
    prompt_slug text,
    icon_key text,
    image_key text,
    color_theme text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text,
    sort_order integer,
    step_title text,
    step_intro text,
    is_required boolean
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cp.id as prompt_id,
        cp.slug as prompt_slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        coalesce(requested.title, fallback.title) as title,
        coalesce(requested.summary, fallback.summary) as summary,
        coalesce(requested.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(requested.example_input, fallback.example_input) as example_input,
        coalesce(requested.audience_label, fallback.audience_label) as audience_label,
        coalesce(requested.tone_hint, fallback.tone_hint) as tone_hint,
        cpi.sort_order,
        cpi.step_title,
        cpi.step_intro,
        cpi.is_required
    from public.catalog_packages cpkg
    join public.catalog_package_items cpi on cpi.package_id = cpkg.id
    join public.catalog_prompts cp on cp.id = cpi.prompt_id
    left join public.catalog_prompt_variants requested
      on requested.prompt_id = cp.id
     and requested.context_key = p_context_key
    left join public.catalog_prompt_variants fallback
      on fallback.prompt_id = cp.id
     and fallback.context_key = 'generell'
    where cpkg.status = 'published'
      and cpkg.slug = p_package_slug
      and cp.status = 'published'
    order by cpi.sort_order;
$$;

revoke all on function public.list_published_package_prompts(text, text) from public;
grant execute on function public.list_published_package_prompts(text, text) to anon, authenticated;
