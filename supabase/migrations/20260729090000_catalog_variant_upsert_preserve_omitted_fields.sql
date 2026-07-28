-- Fix: upsert_catalog_prompt_variant/upsert_catalog_package_variant's
-- "on conflict do update set x = excluded.x" unconditionally overwrote EVERY
-- column with whatever the caller passed (or its default), even columns the
-- caller never intended to touch. admin-MCP's admin_upsert_prompt_variant
-- tool only exposes a subset of columns (not audience_label/example_input/
-- context_notes/tone_hint/suggested_variables) -- any edit through it
-- silently nulled those out on the *documented* edit path
-- ("editing an already-published prompt goes through this same tool").
-- Found in final whole-branch review of the 2026-07-28 admin-MCP work
-- (docs/superpowers/specs/2026-07-28-admin-mcp-catalog-authoring-design.md
-- in the mcp_promptbanken repo), deliberately parked as a follow-up rather
-- than blocking that branch since it needs this separate migration.
--
-- Fix: every column the caller CAN omit now preserves its existing value
-- when the corresponding parameter is null (coalesce against the current
-- row, referencing the plpgsql parameter directly -- not `excluded.x`,
-- since `excluded` reflects the INSERT-branch's already-coalesced value,
-- not "did the caller actually pass this"). title/summary/prompt_text (or
-- title/summary/intro_text for packages) stay hard overwrites -- they are
-- required on every call, never optional.
--
-- default_bindings/binding_overrides/suggested_variables are `not null`
-- columns with DB-level '{}'/'[]' defaults, so their RPC parameter default
-- changes from '{}'::jsonb/'[]'::jsonb to null too -- otherwise "omitted"
-- and "explicitly empty" would be indistinguishable and the coalesce-preserve
-- fix would never trigger for them. A brand-new variant with these omitted
-- still gets '{}'/'[]' via the INSERT-branch fallback.

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
    p_binding_overrides jsonb default null
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
        parameter_schema, default_bindings, binding_overrides
    ) values (
        p_prompt_id, p_context_key, p_title, p_summary, p_prompt_text, p_example_input,
        p_audience_label, p_tone_hint, p_context_notes, coalesce(p_suggested_variables, '{}'::jsonb),
        p_risk_level, p_area, p_tags, p_output_format,
        p_parameter_schema, coalesce(p_default_bindings, '{}'::jsonb), coalesce(p_binding_overrides, '[]'::jsonb)
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
        binding_overrides = coalesce(p_binding_overrides, catalog_prompt_variants.binding_overrides)
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
    p_binding_overrides jsonb default null
) returns public.catalog_prompt_variants
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.upsert_catalog_prompt_variant(
        p_prompt_id, p_context_key, p_title, p_summary, p_prompt_text,
        p_example_input, p_audience_label, p_tone_hint, p_context_notes, p_suggested_variables,
        p_risk_level, p_area, p_tags, p_output_format,
        p_parameter_schema, p_default_bindings, p_binding_overrides
    );
$$;

-- Same preserve-on-omit treatment for packages (intro_text/audience_label/
-- parameter_schema/default_bindings/binding_overrides). Not currently
-- reachable via any admin-MCP tool (no admin_upsert_package_variant exists
-- yet) but admin.js can call it directly, and the same bug class applies.

create or replace function app_private.upsert_catalog_package_variant(
    p_package_id uuid,
    p_context_key text,
    p_title text,
    p_summary text,
    p_intro_text text default null,
    p_audience_label text default null,
    p_parameter_schema jsonb default null,
    p_default_bindings jsonb default null,
    p_binding_overrides jsonb default null
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

    if p_parameter_schema is not null and jsonb_typeof(p_parameter_schema) <> 'object' then
        raise exception 'parameter_schema måste vara ett jsonb-objekt.';
    end if;
    if p_default_bindings is not null and jsonb_typeof(p_default_bindings) <> 'object' then
        raise exception 'default_bindings måste vara ett jsonb-objekt.';
    end if;
    if p_binding_overrides is not null and jsonb_typeof(p_binding_overrides) <> 'array' then
        raise exception 'binding_overrides måste vara en jsonb-array.';
    end if;

    insert into public.catalog_package_variants (
        package_id, context_key, title, summary, intro_text, audience_label,
        parameter_schema, default_bindings, binding_overrides
    ) values (
        p_package_id, p_context_key, p_title, p_summary, p_intro_text, p_audience_label,
        p_parameter_schema, coalesce(p_default_bindings, '{}'::jsonb), coalesce(p_binding_overrides, '[]'::jsonb)
    )
    on conflict (package_id, context_key) do update
    set title = excluded.title,
        summary = excluded.summary,
        intro_text = coalesce(p_intro_text, catalog_package_variants.intro_text),
        audience_label = coalesce(p_audience_label, catalog_package_variants.audience_label),
        parameter_schema = coalesce(p_parameter_schema, catalog_package_variants.parameter_schema),
        default_bindings = coalesce(p_default_bindings, catalog_package_variants.default_bindings),
        binding_overrides = coalesce(p_binding_overrides, catalog_package_variants.binding_overrides)
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
    p_audience_label text default null,
    p_parameter_schema jsonb default null,
    p_default_bindings jsonb default null,
    p_binding_overrides jsonb default null
) returns public.catalog_package_variants
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.upsert_catalog_package_variant(
        p_package_id, p_context_key, p_title, p_summary, p_intro_text, p_audience_label,
        p_parameter_schema, p_default_bindings, p_binding_overrides
    );
$$;
