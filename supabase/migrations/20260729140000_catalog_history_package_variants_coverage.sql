-- Forward-fix wave from the final whole-branch review of catalog version
-- history (design doc: mcp_promptbanken/docs/superpowers/specs/
-- 2026-07-29-catalog-version-history-design.md). Closes:
--
--   Fix 2: catalog_package_variants (a package's actual editable content --
--          title, summary, intro_text, audience_label, parameter_schema,
--          default_bindings, binding_overrides, context_key) had no history
--          trigger, so package content edits were unversioned, and
--          admin_list_package_history's summary was always null since
--          neither catalog_packages nor catalog_package_items carries
--          title/context_key/summary.
--   Fix 3: restore silently bypassed the publish gates -- a restore could
--          produce status='published' rows that would fail
--          publish_catalog_prompt/publish_catalog_package if published
--          normally. Restoring a history row whose snapshot says
--          'published' now forces status back to 'draft'; it does not
--          republish -- the admin must explicitly re-publish via the
--          normal gated path, which re-validates.
--   Fix 4: unique-constraint collisions (slug, (prompt_id, context_key),
--          (package_id, prompt_id), (package_id, context_key)) surfaced as
--          raw Postgres constraint-violation errors instead of a friendly
--          Swedish message.
--   Fix 5: created_at/created_by were dropped on delete-then-restore for
--          catalog_prompts and catalog_packages (present in the history
--          snapshot but omitted from the insert column list).
--   Fix 6: suggested_variables restored without the same coalesce guard
--          its sibling jsonb columns (default_bindings, binding_overrides)
--          already have.
--   Fix 7: app_private.catalog_history itself was missing the
--          `revoke all ... from public` its sibling app_private tables have.
--   Fix 8: history summaries only surfaced title/context_key, always null
--          for base-table (catalog_prompts/catalog_packages) rows since
--          those fields live only on variant rows. Add summary + a slug
--          fallback.
--
-- Fix 1 (audit log target_id type mismatch) was a Python-side fix in the
-- mcp_promptbanken repo (admin_catalog.py) -- no SQL change needed there.

-- --- Fix 7: lock down the history table itself, matching sibling tables ---
revoke all on table app_private.catalog_history from public;

-- --- Fix 2.1: mount the existing (unmodified) trigger function on
-- catalog_package_variants too, same shape as the other four tables ---
create trigger catalog_package_variants_history
    before update or delete on public.catalog_package_variants
    for each row execute function app_private.record_catalog_history();


-- --- Fix 2.2 + Fix 8: list_prompt_history -- add summary/slug fields ---
create or replace function app_private.list_prompt_history(p_prompt_id uuid)
returns table(
    history_id bigint,
    table_name text,
    operation text,
    changed_at timestamptz,
    summary jsonb
)
language plpgsql
security definer
set search_path to ''
as $$
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    return query
    select h.id, h.table_name, h.operation, h.changed_at,
           jsonb_build_object(
               'title', h.row_data->>'title',
               'context_key', h.row_data->>'context_key',
               'summary', h.row_data->>'summary',
               'slug', h.row_data->>'slug'
           )
      from app_private.catalog_history h
     where (h.table_name = 'catalog_prompts' and h.row_id = p_prompt_id)
        or (h.table_name = 'catalog_prompt_variants' and h.row_data->>'prompt_id' = p_prompt_id::text)
     order by h.changed_at desc;
end;
$$;


-- --- Fix 2.2 + Fix 8: list_package_history -- add catalog_package_variants
-- coverage and summary/slug fields ---
create or replace function app_private.list_package_history(p_package_id uuid)
returns table(
    history_id bigint,
    table_name text,
    operation text,
    changed_at timestamptz,
    summary jsonb
)
language plpgsql
security definer
set search_path to ''
as $$
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    return query
    select h.id, h.table_name, h.operation, h.changed_at,
           jsonb_build_object(
               'title', h.row_data->>'title',
               'context_key', h.row_data->>'context_key',
               'summary', h.row_data->>'summary',
               'slug', h.row_data->>'slug'
           )
      from app_private.catalog_history h
     where (h.table_name = 'catalog_packages' and h.row_id = p_package_id)
        or (h.table_name = 'catalog_package_items' and h.row_data->>'package_id' = p_package_id::text)
        or (h.table_name = 'catalog_package_variants' and h.row_data->>'package_id' = p_package_id::text)
     order by h.changed_at desc;
end;
$$;


-- --- Fixes 3/4/5/6: restore_prompt_version ---
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
    v_status text;
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

        -- Fix 4: friendly error instead of a raw unique-constraint violation.
        -- Excludes the row's own id since `on conflict (id)` already
        -- correctly handles restoring a row that still exists.
        if exists (
            select 1 from public.catalog_prompt_variants
             where prompt_id = (v_history.row_data->>'prompt_id')::uuid
               and context_key = v_history.row_data->>'context_key'
               and id <> (v_history.row_data->>'id')::uuid
        ) then
            raise exception 'Kan inte återställa: en variant med kontext "%" finns redan för denna prompt.', v_history.row_data->>'context_key';
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
            -- Fix 6: matching coalesce to its sibling jsonb columns below.
            coalesce(v_history.row_data->'suggested_variables', '{}'::jsonb),
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
        -- Fix 4: friendly error instead of a raw unique-constraint violation.
        if exists (
            select 1 from public.catalog_prompts
             where slug = v_history.row_data->>'slug'
               and id <> (v_history.row_data->>'id')::uuid
        ) then
            raise exception 'Kan inte återställa: slug "%" används redan av en annan prompt.', v_history.row_data->>'slug';
        end if;

        -- Fix 3: restoring a history row that was published does not
        -- republish it -- it comes back as a draft so the normal publish
        -- gate (publish_catalog_prompt's risk_level/area/tags/output_format
        -- checks) re-validates it before it can go live again.
        v_status := v_history.row_data->>'status';
        if v_status = 'published' then
            v_status := 'draft';
        end if;

        insert into public.catalog_prompts (
            id, slug, status, prompt_kind, icon_key, image_key, color_theme, updated_by,
            created_at, created_by
        )
        select
            (v_history.row_data->>'id')::uuid,
            v_history.row_data->>'slug',
            v_status,
            coalesce(v_history.row_data->>'prompt_kind', 'prompt'),
            v_history.row_data->>'icon_key',
            v_history.row_data->>'image_key',
            v_history.row_data->>'color_theme',
            auth.uid(),
            -- Fix 5: reproduce the original created_at/created_by on an
            -- insert-after-delete restore instead of stamping fresh values.
            -- Deliberately excluded from the `on conflict do update` set
            -- clause below -- they must not change when restoring onto a
            -- still-existing row.
            (v_history.row_data->>'created_at')::timestamptz,
            (v_history.row_data->>'created_by')::uuid
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


-- --- Fixes 2.3/3/4/5: restore_package_version ---
create or replace function app_private.restore_package_version(p_history_id bigint, p_confirm boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
    v_history app_private.catalog_history;
    v_parent_exists boolean;
    v_restored jsonb;
    v_status text;
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
    if v_history.table_name not in ('catalog_packages', 'catalog_package_items', 'catalog_package_variants') then
        raise exception 'Historikpost % tillhör inte ett paket (table_name=%).', p_history_id, v_history.table_name;
    end if;

    if v_history.table_name = 'catalog_package_items' then
        select exists(
            select 1 from public.catalog_packages
             where id = (v_history.row_data->>'package_id')::uuid
        ) into v_parent_exists;
        if not v_parent_exists then
            raise exception 'Paketet som raden hör till finns inte längre -- återställ paketet (catalog_packages-historikposten) först.';
        end if;

        -- Fix 4: friendly error instead of a raw unique-constraint violation.
        if exists (
            select 1 from public.catalog_package_items
             where package_id = (v_history.row_data->>'package_id')::uuid
               and prompt_id = (v_history.row_data->>'prompt_id')::uuid
               and id <> (v_history.row_data->>'id')::uuid
        ) then
            raise exception 'Kan inte återställa: prompten ingår redan i paketet.';
        end if;

        insert into public.catalog_package_items (id, package_id, prompt_id, sort_order, step_title, step_intro, is_required)
        select
            (v_history.row_data->>'id')::uuid,
            (v_history.row_data->>'package_id')::uuid,
            (v_history.row_data->>'prompt_id')::uuid,
            (v_history.row_data->>'sort_order')::int,
            v_history.row_data->>'step_title',
            v_history.row_data->>'step_intro',
            (v_history.row_data->>'is_required')::boolean
        on conflict (id) do update set
            sort_order = excluded.sort_order,
            step_title = excluded.step_title,
            step_intro = excluded.step_intro,
            is_required = excluded.is_required
        returning to_jsonb(catalog_package_items.*) into v_restored;
    elsif v_history.table_name = 'catalog_package_variants' then
        -- Fix 2.3: package_variants restore branch (mirrors the
        -- catalog_package_items parent check above).
        select exists(
            select 1 from public.catalog_packages
             where id = (v_history.row_data->>'package_id')::uuid
        ) into v_parent_exists;
        if not v_parent_exists then
            raise exception 'Paketet som varianten hör till finns inte längre -- återställ paketet (catalog_packages-historikposten) först.';
        end if;

        -- Fix 4: friendly error instead of a raw unique-constraint violation.
        if exists (
            select 1 from public.catalog_package_variants
             where package_id = (v_history.row_data->>'package_id')::uuid
               and context_key = v_history.row_data->>'context_key'
               and id <> (v_history.row_data->>'id')::uuid
        ) then
            raise exception 'Kan inte återställa: en variant med kontext "%" finns redan för detta paket.', v_history.row_data->>'context_key';
        end if;

        insert into public.catalog_package_variants (
            id, package_id, context_key, title, summary, intro_text, audience_label,
            parameter_schema, default_bindings, binding_overrides
        )
        select
            (v_history.row_data->>'id')::uuid,
            (v_history.row_data->>'package_id')::uuid,
            v_history.row_data->>'context_key',
            v_history.row_data->>'title',
            v_history.row_data->>'summary',
            v_history.row_data->>'intro_text',
            v_history.row_data->>'audience_label',
            v_history.row_data->'parameter_schema',
            coalesce(v_history.row_data->'default_bindings', '{}'::jsonb),
            coalesce(v_history.row_data->'binding_overrides', '[]'::jsonb)
        on conflict (id) do update set
            context_key = excluded.context_key,
            title = excluded.title,
            summary = excluded.summary,
            intro_text = excluded.intro_text,
            audience_label = excluded.audience_label,
            parameter_schema = excluded.parameter_schema,
            default_bindings = excluded.default_bindings,
            binding_overrides = excluded.binding_overrides
        returning to_jsonb(catalog_package_variants.*) into v_restored;
    else
        -- Fix 4: friendly error instead of a raw unique-constraint violation.
        if exists (
            select 1 from public.catalog_packages
             where slug = v_history.row_data->>'slug'
               and id <> (v_history.row_data->>'id')::uuid
        ) then
            raise exception 'Kan inte återställa: slug "%" används redan av ett annat paket.', v_history.row_data->>'slug';
        end if;

        -- Fix 3: restoring a history row that was published does not
        -- republish it -- it comes back as a draft so the normal publish
        -- gate (publish_catalog_package's generell-variant/items/all-
        -- members-published checks) re-validates it before it can go live
        -- again.
        v_status := v_history.row_data->>'status';
        if v_status = 'published' then
            v_status := 'draft';
        end if;

        insert into public.catalog_packages (
            id, slug, package_type, status, icon_key, image_key, color_theme, updated_by,
            created_at, created_by
        )
        select
            (v_history.row_data->>'id')::uuid,
            v_history.row_data->>'slug',
            v_history.row_data->>'package_type',
            v_status,
            v_history.row_data->>'icon_key',
            v_history.row_data->>'image_key',
            v_history.row_data->>'color_theme',
            auth.uid(),
            -- Fix 5: reproduce the original created_at/created_by on an
            -- insert-after-delete restore instead of stamping fresh values.
            -- Deliberately excluded from the `on conflict do update` set
            -- clause below -- they must not change when restoring onto a
            -- still-existing row.
            (v_history.row_data->>'created_at')::timestamptz,
            (v_history.row_data->>'created_by')::uuid
        on conflict (id) do update set
            slug = excluded.slug,
            package_type = excluded.package_type,
            status = excluded.status,
            icon_key = excluded.icon_key,
            image_key = excluded.image_key,
            color_theme = excluded.color_theme,
            updated_by = excluded.updated_by
        returning to_jsonb(catalog_packages.*) into v_restored;
    end if;

    return v_restored;
end;
$$;
