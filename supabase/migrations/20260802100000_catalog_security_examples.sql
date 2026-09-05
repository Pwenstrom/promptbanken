-- 20260802100000_catalog_security_examples.sql
-- Lägger till security_examples (GDPR-anonymiseringsvarningar) på
-- catalog_prompt_variants, backfyllar från pro_prompt_templates för de
-- legacy-migrerade raderna, och utökar upsert_catalog_prompt_variant så
-- admin-MCP kan skriva fältet. Se docs/superpowers/plans/
-- 2026-08-01-unify-catalog-template-source.md.

alter table public.catalog_prompt_variants
    add column if not exists security_examples text[];

-- Backfill: matcha via den redan existerande legacy-slug-konventionen
-- ('legacy-' || area || '-' || lpad(sort_order, 2, '0')) som seedmigrationen
-- 20260725120000_seed_catalog_from_existing_templates.sql byggde sluggarna
-- med. Sätter samma security_examples-array på alla context-varianter av
-- respektive prompt (fältet är inte context-specifikt i källtabellen).
update public.catalog_prompt_variants v
   set security_examples = t.security_examples
  from public.catalog_prompts cp
  join public.pro_prompt_templates t
    on cp.slug = 'legacy-' || t.area || '-' || lpad(t.sort_order::text, 2, '0')
 where v.prompt_id = cp.id
   and t.security_examples is not null
   and array_length(t.security_examples, 1) > 0;

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
    p_suggested_variables jsonb default null,
    p_risk_level text default null,
    p_area text default null,
    p_tags text[] default null,
    p_output_format text default null,
    p_parameter_schema jsonb default null,
    p_default_bindings jsonb default null,
    p_binding_overrides jsonb default null,
    p_security_examples text[] default null
)
returns catalog_prompt_variants
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

    if p_parameter_schema is not null and jsonb_typeof(p_parameter_schema) <> 'object' then
        raise exception 'parameter_schema måste vara ett jsonb-objekt.';
    end if;
    if p_default_bindings is not null and jsonb_typeof(p_default_bindings) <> 'object' then
        raise exception 'default_bindings måste vara ett jsonb-objekt.';
    end if;
    if p_binding_overrides is not null and jsonb_typeof(p_binding_overrides) <> 'array' then
        raise exception 'binding_overrides måste vara en jsonb-array.';
    end if;

    insert into public.catalog_prompt_variants (
        prompt_id, context_key, title, summary, prompt_text, example_input,
        audience_label, tone_hint, context_notes, suggested_variables,
        risk_level, area, tags, output_format,
        parameter_schema, default_bindings, binding_overrides, security_examples
    ) values (
        p_prompt_id, p_context_key, p_title, p_summary, p_prompt_text, p_example_input,
        p_audience_label, p_tone_hint, p_context_notes, coalesce(p_suggested_variables, '{}'::jsonb),
        p_risk_level, p_area, p_tags, p_output_format,
        p_parameter_schema, coalesce(p_default_bindings, '{}'::jsonb), coalesce(p_binding_overrides, '[]'::jsonb),
        p_security_examples
    )
    on conflict (prompt_id, context_key) do update
    set title = excluded.title,
        summary = excluded.summary,
        prompt_text = excluded.prompt_text,
        example_input = coalesce(p_example_input, catalog_prompt_variants.example_input),
        audience_label = coalesce(p_audience_label, catalog_prompt_variants.audience_label),
        tone_hint = coalesce(p_tone_hint, catalog_prompt_variants.tone_hint),
        context_notes = coalesce(p_context_notes, catalog_prompt_variants.context_notes),
        suggested_variables = coalesce(p_suggested_variables, catalog_prompt_variants.suggested_variables),
        risk_level = coalesce(p_risk_level, catalog_prompt_variants.risk_level),
        area = coalesce(p_area, catalog_prompt_variants.area),
        tags = coalesce(p_tags, catalog_prompt_variants.tags),
        output_format = coalesce(p_output_format, catalog_prompt_variants.output_format),
        parameter_schema = coalesce(p_parameter_schema, catalog_prompt_variants.parameter_schema),
        default_bindings = coalesce(p_default_bindings, catalog_prompt_variants.default_bindings),
        binding_overrides = coalesce(p_binding_overrides, catalog_prompt_variants.binding_overrides),
        security_examples = coalesce(p_security_examples, catalog_prompt_variants.security_examples)
    returning * into v_variant;

    update public.catalog_prompts
       set updated_by = auth.uid()
     where id = p_prompt_id;

    return v_variant;
end;
$$;

create or replace function public.upsert_catalog_prompt_variant(
    p_prompt_id uuid,
    p_context_key text,
    p_title text,
    p_summary text,
    p_prompt_text text,
    p_example_input text default null,
    p_audience_label text default null,
    p_tone_hint text default null,
    p_context_notes text default null,
    p_suggested_variables jsonb default null,
    p_risk_level text default null,
    p_area text default null,
    p_tags text[] default null,
    p_output_format text default null,
    p_parameter_schema jsonb default null,
    p_default_bindings jsonb default null,
    p_binding_overrides jsonb default null,
    p_security_examples text[] default null
)
returns catalog_prompt_variants
language sql
security definer
set search_path = 'public', 'app_private', 'pg_temp'
as $$
    select * from app_private.upsert_catalog_prompt_variant(
        p_prompt_id, p_context_key, p_title, p_summary, p_prompt_text,
        p_example_input, p_audience_label, p_tone_hint, p_context_notes, p_suggested_variables,
        p_risk_level, p_area, p_tags, p_output_format,
        p_parameter_schema, p_default_bindings, p_binding_overrides, p_security_examples
    );
$$;

revoke all on function public.upsert_catalog_prompt_variant(
    uuid, text, text, text, text, text, text, text, text, jsonb,
    text, text, text[], text, jsonb, jsonb, jsonb, text[]
) from public;
grant execute on function public.upsert_catalog_prompt_variant(
    uuid, text, text, text, text, text, text, text, text, jsonb,
    text, text, text[], text, jsonb, jsonb, jsonb, text[]
) to authenticated;

-- PostgreSQL cannot change a table function's OUT columns with CREATE OR
-- REPLACE. This migration adds security_examples to the result, so remove
-- the preceding signature before defining the expanded return type.
drop function if exists public.list_published_prompts(text[]);

create or replace function public.list_published_prompts(
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
    tone_hint text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    risk_level text,
    area text,
    tags text[],
    output_format text,
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
    order by cp.slug;
$$;

revoke all on function public.list_published_prompts(text[]) from public;
grant execute on function public.list_published_prompts(text[]) to anon, authenticated;

drop function if exists public.get_published_prompt(text, text[]);

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
    tone_hint text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    risk_level text,
    area text,
    tags text[],
    output_format text,
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
      and (v.context_key = any(p_context_keys) or v.context_key = 'generell')
    order by
        case when v.context_key = 'generell' then 1 else 0 end,
        coalesce(array_position(p_context_keys, v.context_key), 999);
$$;

revoke all on function public.get_published_prompt(text, text[]) from public;
grant execute on function public.get_published_prompt(text, text[]) to anon, authenticated;

-- Drop the public wrapper first because it depends on the private function.
drop function if exists public.get_catalog_prompt_by_id(uuid);
drop function if exists app_private.get_catalog_prompt_by_id(uuid);

create or replace function app_private.get_catalog_prompt_by_id(p_prompt_id uuid)
returns table (
    id uuid,
    slug text,
    status text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    risk_level text,
    area text,
    tags text[],
    output_format text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    security_examples text[]
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa en katalogprompt.';
    end if;

    return query
    select cp.id, cp.slug, cp.status, v.context_key, v.title, v.summary, v.prompt_text,
           v.risk_level, v.area, v.tags, v.output_format,
           v.parameter_schema, v.default_bindings, v.binding_overrides, v.security_examples
      from public.catalog_prompts cp
      join public.catalog_prompt_variants v on v.prompt_id = cp.id
     where cp.id = p_prompt_id
     order by case when v.context_key = 'generell' then 0 else 1 end;
end;
$$;

create or replace function public.get_catalog_prompt_by_id(p_prompt_id uuid)
returns table (
    id uuid,
    slug text,
    status text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    risk_level text,
    area text,
    tags text[],
    output_format text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    security_examples text[]
)
language sql
security definer
set search_path = 'public', 'app_private', 'pg_temp'
as $$
    select * from app_private.get_catalog_prompt_by_id(p_prompt_id);
$$;

revoke all on function public.get_catalog_prompt_by_id(uuid) from public;
grant execute on function public.get_catalog_prompt_by_id(uuid) to authenticated;
