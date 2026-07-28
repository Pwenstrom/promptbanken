-- Follow-up to 20260729131500_catalog_history_restore_rpcs.sql: the original
-- apply_migration call for that file ran BEFORE the tags-null bug in
-- app_private.restore_prompt_version was discovered and fixed (Step 3
-- verification of Task 3), so Supabase's migration ledger
-- (supabase_migrations.schema_migrations) still has the buggy
-- `v_history.row_data ? 'tags'` check baked into its recorded statements for
-- that version, even though the live function and the committed source file
-- were both hotfixed in place afterward. A future migration replay
-- (`supabase db push` against a fresh database, or a branch rebuild) would
-- otherwise resurrect the exact bug that was just fixed.
--
-- This migration re-asserts the corrected function body under its own
-- ledger entry so replay-from-migrations reproduces the fixed behavior. It
-- is a pure `create or replace function` with no other side effects -- the
-- function body is identical to the one now live in production and to the
-- (already fixed) copy in 20260729131500_catalog_history_restore_rpcs.sql.

create or replace function app_private.restore_prompt_version(p_history_id bigint, p_confirm boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
    v_history app_private.catalog_history;
    v_parent_exists boolean;
    v_restored jsonb;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;
    if p_confirm is not true then
        raise exception 'confirm måste vara true för att återställa en version.';
    end if;

    select * into v_history from app_private.catalog_history where id = p_history_id;
    if not found then
        raise exception 'Ingen historikpost hittades med id %', p_history_id;
    end if;
    if v_history.table_name not in ('catalog_prompts', 'catalog_prompt_variants') then
        raise exception 'Historikpost % tillhör inte en prompt (table_name=%).', p_history_id, v_history.table_name;
    end if;

    if v_history.table_name = 'catalog_prompt_variants' then
        select exists(
            select 1 from public.catalog_prompts
             where id = (v_history.row_data->>'prompt_id')::uuid
        ) into v_parent_exists;
        if not v_parent_exists then
            raise exception 'Prompten som varianten hör till finns inte längre -- återställ prompten (catalog_prompts-historikposten) först.';
        end if;

        insert into public.catalog_prompt_variants (
            id, prompt_id, context_key, title, summary, prompt_text, example_input,
            audience_label, tone_hint, context_notes, suggested_variables,
            parameter_schema, default_bindings, binding_overrides,
            risk_level, area, tags, output_format
        )
        select
            (v_history.row_data->>'id')::uuid,
            (v_history.row_data->>'prompt_id')::uuid,
            v_history.row_data->>'context_key',
            v_history.row_data->>'title',
            v_history.row_data->>'summary',
            v_history.row_data->>'prompt_text',
            v_history.row_data->>'example_input',
            v_history.row_data->>'audience_label',
            v_history.row_data->>'tone_hint',
            v_history.row_data->>'context_notes',
            v_history.row_data->'suggested_variables',
            v_history.row_data->'parameter_schema',
            coalesce(v_history.row_data->'default_bindings', '{}'::jsonb),
            coalesce(v_history.row_data->'binding_overrides', '[]'::jsonb),
            v_history.row_data->>'risk_level',
            v_history.row_data->>'area',
            case when jsonb_typeof(v_history.row_data->'tags') = 'array'
                 then array(select jsonb_array_elements_text(v_history.row_data->'tags'))
                 else null end,
            v_history.row_data->>'output_format'
        on conflict (id) do update set
            context_key = excluded.context_key,
            title = excluded.title,
            summary = excluded.summary,
            prompt_text = excluded.prompt_text,
            example_input = excluded.example_input,
            audience_label = excluded.audience_label,
            tone_hint = excluded.tone_hint,
            context_notes = excluded.context_notes,
            suggested_variables = excluded.suggested_variables,
            parameter_schema = excluded.parameter_schema,
            default_bindings = excluded.default_bindings,
            binding_overrides = excluded.binding_overrides,
            risk_level = excluded.risk_level,
            area = excluded.area,
            tags = excluded.tags,
            output_format = excluded.output_format
        returning to_jsonb(catalog_prompt_variants.*) into v_restored;
    else
        insert into public.catalog_prompts (id, slug, status, prompt_kind, icon_key, image_key, color_theme, updated_by)
        select
            (v_history.row_data->>'id')::uuid,
            v_history.row_data->>'slug',
            v_history.row_data->>'status',
            coalesce(v_history.row_data->>'prompt_kind', 'prompt'),
            v_history.row_data->>'icon_key',
            v_history.row_data->>'image_key',
            v_history.row_data->>'color_theme',
            auth.uid()
        on conflict (id) do update set
            slug = excluded.slug,
            status = excluded.status,
            prompt_kind = excluded.prompt_kind,
            icon_key = excluded.icon_key,
            image_key = excluded.image_key,
            color_theme = excluded.color_theme,
            updated_by = excluded.updated_by
        returning to_jsonb(catalog_prompts.*) into v_restored;
    end if;

    return v_restored;
end;
$$;
