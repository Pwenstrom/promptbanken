-- Admin-MCP katalogförfattande: metadata-kolumner, parametriska RPC-parametrar,
-- skärpt publiceringsspärr, samt en admin-audit-tabell.
-- Se docs/superpowers/specs/2026-07-28-admin-mcp-catalog-authoring-design.md
-- i mcp_promptbanken-repot.

-- 1. Metadata-kolumner på catalog_prompt_variants (nullable -- krav vid
--    publicering hanteras i publish_catalog_prompt nedan, inte via NOT NULL,
--    så befintliga admin.js-anrop som inte sätter dem fortsätter fungera).
alter table public.catalog_prompt_variants
    add column if not exists risk_level text,
    add column if not exists area text,
    add column if not exists tags text[],
    add column if not exists output_format text;

-- 2. upsert_catalog_prompt_variant: lägg till parametrisk rendering +
--    metadata-parametrar. Signaturen ändras (nya obligatoriska positioner
--    för PostgREST-anrop med defaults) -- drop+recreate, samma mönster som
--    20260726184226_improve_catalog_prompt_quality.sql använde för
--    get_published_prompt.
drop function if exists public.upsert_catalog_prompt_variant(uuid, text, text, text, text, text, text, text, text, jsonb);
drop function if exists app_private.upsert_catalog_prompt_variant(uuid, text, text, text, text, text, text, text, text, jsonb);

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
    p_suggested_variables jsonb default '{}'::jsonb,
    p_risk_level text default null,
    p_area text default null,
    p_tags text[] default null,
    p_output_format text default null,
    p_parameter_schema jsonb default null,
    p_default_bindings jsonb default '{}'::jsonb,
    p_binding_overrides jsonb default '[]'::jsonb
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
    if jsonb_typeof(coalesce(p_default_bindings, '{}'::jsonb)) <> 'object' then
        raise exception 'default_bindings måste vara ett jsonb-objekt.';
    end if;
    if jsonb_typeof(coalesce(p_binding_overrides, '[]'::jsonb)) <> 'array' then
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
        example_input = excluded.example_input,
        audience_label = excluded.audience_label,
        tone_hint = excluded.tone_hint,
        context_notes = excluded.context_notes,
        suggested_variables = excluded.suggested_variables,
        risk_level = excluded.risk_level,
        area = excluded.area,
        tags = excluded.tags,
        output_format = excluded.output_format,
        parameter_schema = excluded.parameter_schema,
        default_bindings = excluded.default_bindings,
        binding_overrides = excluded.binding_overrides
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
    p_suggested_variables jsonb default '{}'::jsonb,
    p_risk_level text default null,
    p_area text default null,
    p_tags text[] default null,
    p_output_format text default null,
    p_parameter_schema jsonb default null,
    p_default_bindings jsonb default '{}'::jsonb,
    p_binding_overrides jsonb default '[]'::jsonb
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

revoke all on function public.upsert_catalog_prompt_variant(
    uuid, text, text, text, text, text, text, text, text, jsonb,
    text, text, text[], text, jsonb, jsonb, jsonb
) from public;
grant execute on function public.upsert_catalog_prompt_variant(
    uuid, text, text, text, text, text, text, text, text, jsonb,
    text, text, text[], text, jsonb, jsonb, jsonb
) to authenticated;

-- 3. upsert_catalog_package_variant: samma parametriska tillägg (packages
--    fick parameter_schema/default_bindings/binding_overrides-kolumner i
--    20260725133000_catalog_parameter_schemas.sql men ingen RPC skriver dem).
drop function if exists public.upsert_catalog_package_variant(uuid, text, text, text, text, text);
drop function if exists app_private.upsert_catalog_package_variant(uuid, text, text, text, text, text);

create or replace function app_private.upsert_catalog_package_variant(
    p_package_id uuid,
    p_context_key text,
    p_title text,
    p_summary text,
    p_intro_text text default null,
    p_audience_label text default null,
    p_parameter_schema jsonb default null,
    p_default_bindings jsonb default '{}'::jsonb,
    p_binding_overrides jsonb default '[]'::jsonb
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
    if jsonb_typeof(coalesce(p_default_bindings, '{}'::jsonb)) <> 'object' then
        raise exception 'default_bindings måste vara ett jsonb-objekt.';
    end if;
    if jsonb_typeof(coalesce(p_binding_overrides, '[]'::jsonb)) <> 'array' then
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
        intro_text = excluded.intro_text,
        audience_label = excluded.audience_label,
        parameter_schema = excluded.parameter_schema,
        default_bindings = excluded.default_bindings,
        binding_overrides = excluded.binding_overrides
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
    p_default_bindings jsonb default '{}'::jsonb,
    p_binding_overrides jsonb default '[]'::jsonb
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

revoke all on function public.upsert_catalog_package_variant(
    uuid, text, text, text, text, text, jsonb, jsonb, jsonb
) from public;
grant execute on function public.upsert_catalog_package_variant(
    uuid, text, text, text, text, text, jsonb, jsonb, jsonb
) to authenticated;

-- 4. Skärpt publiceringsspärr: kräv risk_level/area/tags/output_format på
--    generell-varianten, utöver den redan befintliga kravet att den finns.
create or replace function app_private.publish_catalog_prompt(p_prompt_id uuid)
returns public.catalog_prompts
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_prompt public.catalog_prompts;
    v_generell public.catalog_prompt_variants;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    select * into v_generell
      from public.catalog_prompt_variants
     where prompt_id = p_prompt_id
       and context_key = 'generell';

    if not found then
        raise exception 'Prompten måste ha en generell variant innan publicering.';
    end if;

    if v_generell.risk_level is null or v_generell.area is null
       or v_generell.tags is null or v_generell.output_format is null then
        raise exception 'risk_level, area, tags och output_format måste vara satta innan publicering.';
    end if;

    update public.catalog_prompts
       set status = 'published',
           updated_by = auth.uid()
     where id = p_prompt_id
     returning * into v_prompt;

    return v_prompt;
end;
$$;

-- Signaturen är oförändrad (uuid) -- ingen ny grant behövs, public.publish_catalog_prompt
-- pekar redan mot app_private.publish_catalog_prompt.

-- 5. Nya read-RPC:er för admin-granskning (drafts syns idag ingenstans --
--    RLS på catalog_prompts har ingen policy, se 20260721160000_catalog_core_rls.sql,
--    så det finns ingen annan väg att läsa en draft än en ny security-definer-RPC).
create or replace function app_private.list_draft_catalog_prompts()
returns table (
    id uuid,
    slug text,
    status text,
    title text,
    summary text,
    risk_level text,
    area text,
    tags text[],
    output_format text,
    created_at timestamptz,
    updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan lista katalog-drafts.';
    end if;

    return query
    select cp.id, cp.slug, cp.status, v.title, v.summary,
           v.risk_level, v.area, v.tags, v.output_format,
           cp.created_at, cp.updated_at
      from public.catalog_prompts cp
      left join public.catalog_prompt_variants v
        on v.prompt_id = cp.id and v.context_key = 'generell'
     where cp.status = 'draft'
     order by cp.created_at desc;
end;
$$;

create or replace function public.list_draft_catalog_prompts()
returns table (
    id uuid, slug text, status text, title text, summary text,
    risk_level text, area text, tags text[], output_format text,
    created_at timestamptz, updated_at timestamptz
)
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.list_draft_catalog_prompts();
$$;

revoke all on function public.list_draft_catalog_prompts() from public;
grant execute on function public.list_draft_catalog_prompts() to authenticated;

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
    binding_overrides jsonb
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
           v.parameter_schema, v.default_bindings, v.binding_overrides
      from public.catalog_prompts cp
      join public.catalog_prompt_variants v on v.prompt_id = cp.id
     where cp.id = p_prompt_id
     order by case when v.context_key = 'generell' then 0 else 1 end;
end;
$$;

create or replace function public.get_catalog_prompt_by_id(p_prompt_id uuid)
returns table (
    id uuid, slug text, status text, context_key text, title text, summary text, prompt_text text,
    risk_level text, area text, tags text[], output_format text,
    parameter_schema jsonb, default_bindings jsonb, binding_overrides jsonb
)
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.get_catalog_prompt_by_id(p_prompt_id);
$$;

revoke all on function public.get_catalog_prompt_by_id(uuid) from public;
grant execute on function public.get_catalog_prompt_by_id(uuid) to authenticated;

-- 6. Admin-audit: loggar VARJE admin-skrivning (inte bara avvisade, till
--    skillnad från mcp_write_attempts), egen tabell eftersom ett
--    komprometterat PROMPTBANKEN_ADMIN_KEY är en helt annan risknivå än en
--    enskild användarnyckel.
create table if not exists app_private.admin_write_attempts (
    id uuid primary key default gen_random_uuid(),
    tool text not null,
    target_id uuid,
    outcome text not null,
    detail jsonb,
    created_at timestamptz not null default now()
);

create or replace function app_private.log_admin_write_attempt(
    p_tool text,
    p_target_id uuid,
    p_outcome text,
    p_detail jsonb default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan logga admin-skrivningar.';
    end if;

    insert into app_private.admin_write_attempts (tool, target_id, outcome, detail)
    values (p_tool, p_target_id, p_outcome, p_detail);
end;
$$;

create or replace function public.log_admin_write_attempt(
    p_tool text,
    p_target_id uuid,
    p_outcome text,
    p_detail jsonb default null
)
returns void
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select app_private.log_admin_write_attempt(p_tool, p_target_id, p_outcome, p_detail);
$$;

revoke all on function public.log_admin_write_attempt(text, uuid, text, jsonb) from public;
grant execute on function public.log_admin_write_attempt(text, uuid, text, jsonb) to authenticated;
