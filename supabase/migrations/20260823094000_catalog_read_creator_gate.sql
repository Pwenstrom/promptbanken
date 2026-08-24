-- Distributionsgate: creator-innehåll når inte Promptbanken Open/MCP.
-- Se docs/superpowers/specs/2026-08-23-creator-review-flow-design.md.
--
-- Webben (script.js, promptbanken.html) och scripts/generate-catalog-pages.mjs
-- skickar p_include_creator_content => true. Den hostade MCP:n i repot
-- mcp_promptbanken skickar ingenting och får filtrerat resultat utan att en
-- rad ändras där. Defaultens riktning är hela poängen: en glömd kodrad kan
-- bara utesluta för mycket, aldrig läcka.
--
-- Delprojekt 7 byter predikatet till att kräva creator_consent_distribution
-- och creator_rights_attested, utan ny migration på innehållet.
--
-- OBS: drop före create krävs. En trailing default-parameter skapar en
-- ANDRA överlagring, inte en ersättning, och PostgREST-anrop med namngivna
-- argument ger då "function is not unique".
--
-- Funktionskropparna nedan är hämtade ordagrant ur produktionen med
-- pg_get_functiondef 2026-08-23. Enda ändringen är den nya parametern och
-- ett tillägg i where-satsen.
--
-- Sidoärende: list_published_package_prompts hade execute för PUBLIC, till
-- skillnad från de fyra andra. Rättas här till samma mönster.

-- 1. list_published_prompts ----------------------------------------------

drop function if exists public.list_published_prompts(text[]);

create or replace function public.list_published_prompts(
    p_context_keys text[] default array['generell'::text],
    p_include_creator_content boolean default false
)
returns table (
    id uuid, slug text, icon_key text, image_key text, color_theme text,
    context_key text, title text, summary text, prompt_text text,
    example_input text, audience_label text, tone_hint text,
    parameter_schema jsonb, default_bindings jsonb, binding_overrides jsonb,
    risk_level text, area text, tags text[], output_format text,
    security_examples text[]
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
        coalesce(matched.output_format, fallback.output_format) as output_format,
        coalesce(matched.security_examples, fallback.security_examples) as security_examples
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
      and (p_include_creator_content or cp.creator_profile_id is null)
    order by cp.slug;
$$;

revoke all on function public.list_published_prompts(text[], boolean) from public;
grant execute on function public.list_published_prompts(text[], boolean) to anon, authenticated, service_role;

-- 2. get_published_prompt -------------------------------------------------

drop function if exists public.get_published_prompt(text, text[]);

create or replace function public.get_published_prompt(
    p_slug text,
    p_context_keys text[] default array['generell'::text],
    p_include_creator_content boolean default false
)
returns table (
    id uuid, slug text, icon_key text, image_key text, color_theme text,
    context_key text, title text, summary text, prompt_text text,
    example_input text, audience_label text, tone_hint text,
    parameter_schema jsonb, default_bindings jsonb, binding_overrides jsonb,
    risk_level text, area text, tags text[], output_format text,
    security_examples text[]
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
        v.tone_hint,
        v.parameter_schema,
        coalesce(v.default_bindings, '{}'::jsonb) as default_bindings,
        coalesce(v.binding_overrides, '[]'::jsonb) as binding_overrides,
        v.risk_level,
        v.area,
        v.tags,
        v.output_format,
        v.security_examples
    from public.catalog_prompts cp
    join public.catalog_prompt_variants v on v.prompt_id = cp.id
    where cp.slug = p_slug
      and cp.status = 'published'
      and (p_include_creator_content or cp.creator_profile_id is null)
      and (v.context_key = any(p_context_keys) or v.context_key = 'generell')
    order by
        case when v.context_key = 'generell' then 1 else 0 end,
        coalesce(array_position(p_context_keys, v.context_key), 999);
$$;

revoke all on function public.get_published_prompt(text, text[], boolean) from public;
grant execute on function public.get_published_prompt(text, text[], boolean) to anon, authenticated, service_role;

-- 3. list_published_packages ----------------------------------------------

drop function if exists public.list_published_packages(text[], text);

create or replace function public.list_published_packages(
    p_context_keys text[] default array['generell'::text],
    p_package_type text default null::text,
    p_include_creator_content boolean default false
)
returns table (
    id uuid, slug text, package_type text, icon_key text, image_key text,
    color_theme text, title text, summary text, intro_text text,
    audience_label text, problem_text text, when_to_use text,
    outcome_text text, area text, tags text[], is_indexable boolean
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
      and (p_include_creator_content or cpkg.creator_profile_id is null)
      and (p_package_type is null or cpkg.package_type = p_package_type)
    order by cpkg.slug;
$$;

revoke all on function public.list_published_packages(text[], text, boolean) from public;
grant execute on function public.list_published_packages(text[], text, boolean) to anon, authenticated, service_role;

-- 4. get_published_package ------------------------------------------------

drop function if exists public.get_published_package(text, text[]);

create or replace function public.get_published_package(
    p_slug text,
    p_context_keys text[] default array['generell'::text],
    p_include_creator_content boolean default false
)
returns table (
    id uuid, slug text, package_type text, icon_key text, image_key text,
    color_theme text, context_key text, title text, summary text,
    intro_text text, audience_label text, parameter_schema jsonb,
    default_bindings jsonb, binding_overrides jsonb, problem_text text,
    when_to_use text, outcome_text text, area text, tags text[],
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
      and (p_include_creator_content or cpkg.creator_profile_id is null)
      and (v.context_key = any(p_context_keys) or v.context_key = 'generell')
    order by
        case when v.context_key = 'generell' then 1 else 0 end,
        coalesce(array_position(p_context_keys, v.context_key), 999);
$$;

revoke all on function public.get_published_package(text, text[], boolean) from public;
grant execute on function public.get_published_package(text, text[], boolean) to anon, authenticated, service_role;

-- 5. list_published_package_prompts ---------------------------------------
--
-- Gatar på både paketet och den enskilda prompten. Ett kurerat paket ska
-- inte kunna bli en bakväg för en creator-prompt.

drop function if exists public.list_published_package_prompts(text, text[]);

create or replace function public.list_published_package_prompts(
    p_package_slug text,
    p_context_keys text[] default array['generell'::text],
    p_include_creator_content boolean default false
)
returns table (
    prompt_id uuid, prompt_slug text, icon_key text, image_key text,
    color_theme text, context_key text, title text, summary text,
    prompt_text text, example_input text, audience_label text,
    tone_hint text, parameter_schema jsonb, default_bindings jsonb,
    binding_overrides jsonb, sort_order integer, step_title text,
    step_intro text, is_required boolean, risk_level text, area text,
    tags text[], output_format text
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
      and (p_include_creator_content
           or (cpkg.creator_profile_id is null and cp.creator_profile_id is null))
    order by cpi.sort_order;
$$;

revoke all on function public.list_published_package_prompts(text, text[], boolean) from public;
grant execute on function public.list_published_package_prompts(text, text[], boolean) to anon, authenticated, service_role;
