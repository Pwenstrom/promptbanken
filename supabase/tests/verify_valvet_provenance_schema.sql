-- Körbart kontrakt för migrationen som spårar Valvet-kopiors mallursprung
-- och validerar paket-id. Skriptet är read-only och kan köras mot produktion.
do $$
declare
    v_missing text[] := '{}'::text[];
begin
    if not exists (
        select 1
          from information_schema.columns
         where table_schema = 'public'
           and table_name = 'content_items'
           and column_name = 'source_template_id'
    ) then
        v_missing := array_append(v_missing, 'content_items.source_template_id');
    end if;

    if not exists (
        select 1
          from information_schema.columns
         where table_schema = 'public'
           and table_name = 'content_items'
           and column_name = 'source_version'
    ) then
        v_missing := array_append(v_missing, 'content_items.source_version');
    end if;

    if not exists (
        select 1
          from information_schema.columns
         where table_schema = 'public'
           and table_name = 'content_items'
           and column_name = 'source_copied_at'
    ) then
        v_missing := array_append(v_missing, 'content_items.source_copied_at');
    end if;

    if to_regprocedure(
        'app_private.pro_prompt_template_source_version(public.pro_prompt_templates)'
    ) is null then
        v_missing := array_append(v_missing, 'pro_prompt_template_source_version');
    end if;

    if to_regprocedure('app_private.prompt_package_area_exists(text)') is null then
        v_missing := array_append(v_missing, 'prompt_package_area_exists');
    end if;

    if to_regprocedure('app_private.enforce_known_prompt_package_area()') is null then
        v_missing := array_append(v_missing, 'enforce_known_prompt_package_area');
    end if;

    if not exists (
        select 1
          from pg_trigger t
          join pg_class c on c.oid = t.tgrelid
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public'
           and c.relname = 'valvet_package_activations'
           and t.tgname = 'enforce_known_prompt_package_area'
           and not t.tgisinternal
    ) then
        v_missing := array_append(v_missing, 'enforce_known_prompt_package_area trigger');
    end if;

    if cardinality(v_missing) > 0 then
        raise exception 'Saknade Valvet provenance-objekt: %', array_to_string(v_missing, ', ');
    end if;
end;
$$;
