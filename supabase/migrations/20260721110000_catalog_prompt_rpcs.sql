-- Write-RPC:er för katalogprompts: create, upsert variant, publish.
-- Publika wrappers är intentionellt okonfigurerade (revoke all) då auth/admin-MCP
-- ligger utanför denna plans omfattning — config:ing av grant för anon/authenticated
-- kommer i en framtida uppgift tillsammans med auktorisering.

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

create or replace function public.create_catalog_prompt(
    p_slug text,
    p_title text,
    p_summary text,
    p_prompt_text text,
    p_icon_key text default null,
    p_image_key text default null,
    p_color_theme text default null
) returns public.catalog_prompts
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.create_catalog_prompt(
        p_slug, p_title, p_summary, p_prompt_text, p_icon_key, p_image_key, p_color_theme
    );
$$;

revoke all on function public.create_catalog_prompt(text, text, text, text, text, text, text) from public;

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
    p_suggested_variables jsonb default '{}'::jsonb
) returns public.catalog_prompt_variants
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.upsert_catalog_prompt_variant(
        p_prompt_id, p_context_key, p_title, p_summary, p_prompt_text,
        p_example_input, p_audience_label, p_tone_hint, p_context_notes, p_suggested_variables
    );
$$;

revoke all on function public.upsert_catalog_prompt_variant(uuid, text, text, text, text, text, text, text, text, jsonb) from public;

create or replace function app_private.publish_catalog_prompt(p_prompt_id uuid)
returns public.catalog_prompts
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_prompt public.catalog_prompts;
begin
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

create or replace function public.publish_catalog_prompt(p_prompt_id uuid)
returns public.catalog_prompts
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.publish_catalog_prompt(p_prompt_id);
$$;

revoke all on function public.publish_catalog_prompt(uuid) from public;
