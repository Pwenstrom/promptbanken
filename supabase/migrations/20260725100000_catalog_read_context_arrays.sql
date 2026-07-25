-- 20260725100000_catalog_read_context_arrays.sql
-- Byter read-RPC:erna från en enskild p_context_key till en kombinerbar
-- p_context_keys text[]. Listfunktioner dedupar till en rad per post;
-- detaljfunktioner returnerar en rad per matchande variant plus generell.

drop function if exists public.list_published_prompts(text);
drop function if exists public.get_published_prompt(text, text);
drop function if exists public.list_published_packages(text, text);
drop function if exists public.get_published_package(text, text);
drop function if exists public.list_published_package_prompts(text, text);

create or replace function public.list_published_prompts(
    p_context_keys text[] default array['generell']
)
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
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(matched.example_input, fallback.example_input) as example_input,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label,
        coalesce(matched.tone_hint, fallback.tone_hint) as tone_hint
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

revoke all on function public.list_published_prompts(text[]) from public;
grant execute on function public.list_published_prompts(text[]) to anon, authenticated;

create or replace function public.get_published_prompt(
    p_slug text,
    p_context_keys text[] default array['generell']
)
returns table (
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
        v.context_key,
        v.title,
        v.summary,
        v.prompt_text,
        v.example_input,
        v.audience_label,
        v.tone_hint
    from public.catalog_prompts cp
    join public.catalog_prompt_variants v on v.prompt_id = cp.id
    where cp.slug = p_slug
      and cp.status = 'published'
      and (v.context_key = any(p_context_keys) or v.context_key = 'generell')
    order by
        case when v.context_key = 'generell' then 1 else 0 end,
        coalesce(array_position(p_context_keys, v.context_key), 999);
$$;

revoke all on function public.get_published_prompt(text, text[]) from public;
grant execute on function public.get_published_prompt(text, text[]) to anon, authenticated;

create or replace function public.list_published_packages(
    p_context_keys text[] default array['generell'],
    p_package_type text default null
)
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
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.intro_text, fallback.intro_text) as intro_text,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label
    from public.catalog_packages cpkg
    left join lateral (
        select v.*
          from public.catalog_package_variants v
         where v.package_id = cpkg.id
           and v.context_key = any(p_context_keys)
         order by array_position(p_context_keys, v.context_key)
         limit 1
    ) matched on true
    left join public.catalog_package_variants fallback
      on fallback.package_id = cpkg.id
     and fallback.context_key = 'generell'
    where cpkg.status = 'published'
      and (p_package_type is null or cpkg.package_type = p_package_type)
    order by cpkg.slug;
$$;

revoke all on function public.list_published_packages(text[], text) from public;
grant execute on function public.list_published_packages(text[], text) to anon, authenticated;

create or replace function public.get_published_package(
    p_slug text,
    p_context_keys text[] default array['generell']
)
returns table (
    id uuid,
    slug text,
    package_type text,
    icon_key text,
    image_key text,
    color_theme text,
    context_key text,
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
        v.context_key,
        v.title,
        v.summary,
        v.intro_text,
        v.audience_label
    from public.catalog_packages cpkg
    join public.catalog_package_variants v on v.package_id = cpkg.id
    where cpkg.slug = p_slug
      and cpkg.status = 'published'
      and (v.context_key = any(p_context_keys) or v.context_key = 'generell')
    order by
        case when v.context_key = 'generell' then 1 else 0 end,
        coalesce(array_position(p_context_keys, v.context_key), 999);
$$;

revoke all on function public.get_published_package(text, text[]) from public;
grant execute on function public.get_published_package(text, text[]) to anon, authenticated;

create or replace function public.list_published_package_prompts(
    p_package_slug text,
    p_context_keys text[] default array['generell']
)
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
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(matched.example_input, fallback.example_input) as example_input,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label,
        coalesce(matched.tone_hint, fallback.tone_hint) as tone_hint,
        cpi.sort_order,
        cpi.step_title,
        cpi.step_intro,
        cpi.is_required
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

revoke all on function public.list_published_package_prompts(text, text[]) from public;
grant execute on function public.list_published_package_prompts(text, text[]) to anon, authenticated;
