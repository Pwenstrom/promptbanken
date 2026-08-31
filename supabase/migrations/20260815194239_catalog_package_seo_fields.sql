-- 20260815090000_catalog_package_seo_fields.sql
-- Redaktionella fält för statiska, indexerbara paketsidor.
-- Se docs/superpowers/specs/2026-08-15-statiska-paketsidor-seo-design.md.
-- Additiv: alla kolumner nullable, RPC-fält läggs sist i returtabellen.

alter table public.catalog_package_variants
    add column if not exists problem_text text,
    add column if not exists when_to_use text,
    add column if not exists outcome_text text;

alter table public.catalog_packages
    add column if not exists area text,
    add column if not exists tags text[],
    add column if not exists is_indexable boolean;

comment on column public.catalog_packages.is_indexable is
    'null = använd innehållströskeln (intro_text ifyllt och minst tre prompts), true/false = tvinga.';

drop function if exists public.list_published_packages(text[], text);

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
    audience_label text,
    problem_text text,
    when_to_use text,
    outcome_text text,
    area text,
    tags text[],
    is_indexable boolean
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
        coalesce(matched.audience_label, fallback.audience_label) as audience_label,
        coalesce(matched.problem_text, fallback.problem_text) as problem_text,
        coalesce(matched.when_to_use, fallback.when_to_use) as when_to_use,
        coalesce(matched.outcome_text, fallback.outcome_text) as outcome_text,
        cpkg.area,
        cpkg.tags,
        cpkg.is_indexable
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

drop function if exists public.get_published_package(text, text[]);

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
    audience_label text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    problem_text text,
    when_to_use text,
    outcome_text text,
    area text,
    tags text[],
    is_indexable boolean
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
        v.audience_label,
        v.parameter_schema,
        coalesce(v.default_bindings, '{}'::jsonb) as default_bindings,
        coalesce(v.binding_overrides, '[]'::jsonb) as binding_overrides,
        v.problem_text,
        v.when_to_use,
        v.outcome_text,
        cpkg.area,
        cpkg.tags,
        cpkg.is_indexable
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
