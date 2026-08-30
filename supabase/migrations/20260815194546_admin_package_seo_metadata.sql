-- 20260815091000_admin_package_seo_metadata.sql
-- Skriv-stöd för de redaktionella fälten som lades till i
-- 20260815090000_catalog_package_seo_fields.sql, så admin-UI:t i Task 8 kan
-- fylla i dem (idag renderas genererade paketsidor utan dem eftersom
-- fälten bara finns läs-vägen ut via list_published_packages/
-- get_published_package).
--
-- Två separata skrivbehov:
-- 1. problem_text/when_to_use/outcome_text ligger på
--    catalog_package_variants. upsert_catalog_package_variant
--    (20260728120000, uppdaterad i 20260729090000) skriver redan den
--    tabellen men saknar parametrar för dessa tre kolumner -- de las till
--    i tabellen efter att den RPC:n senast ändrades. Utökar signaturen
--    här med samma drop+recreate-mönster som 20260728120000 använde, och
--    samma coalesce-utelämnad-preserve som 20260729090000 satte för
--    variantens övriga valfria fält.
-- 2. area/tags/is_indexable ligger på catalog_packages själv och saknar
--    en skriv-RPC helt. Ny app_private-funktion + tunn public-wrapper,
--    exakt samma mönster som 20260728120000_admin_catalog_authoring.sql
--    (security definer, search_path = '', rollkontroll mot
--    platform_owner, revoke/grant to authenticated).
--
-- Omitted-preserve: null-parameter behåller befintligt värde (coalesce
-- mot tabellens kolumn, inte mot excluded). p_tags kan inte skiljas
-- mellan "utelämnad" och "sätt till tom array" via en enda null-check på
-- samma sätt som en skalär -- det är samma begränsning
-- 20260729090000-mönstret redan har för sina array-/jsonb-parametrar, så
-- vi följer det: null = behåll, en (även tom) array = ny bindande array.
--
-- is_indexable är dock ett äkta trevägsval i UI:t (Auto/Alltid/Aldrig, se
-- Task 8 Step 2), där "Auto" *är* sql-värdet null -- till skillnad från
-- area/tags/övriga textfält i systemet kan man här inte låta "null-parameter
-- = utelämnad" betyda "behåll", för då blir det omöjligt att någonsin
-- backa från Alltid/Aldrig till Auto igen. Samma parameter kan inte
-- samtidigt betyda "rör inte" och "sätt till null". Löser det med en extra
-- p_is_indexable_provided-flagga (default false = utelämnad/rör inte,
-- true = använd p_is_indexable som den är, inklusive null för Auto).
-- area/tags behåller den vanliga coalesce-utelämnad-semantiken eftersom
-- de inte har den här trevägs-null-är-ett-giltigt-värde-egenskapen.

-- 1. upsert_catalog_package_variant: lägg till problem_text/when_to_use/
--    outcome_text, samma coalesce-utelämnad-preserve som övriga valfria
--    variantfält.
drop function if exists public.upsert_catalog_package_variant(uuid, text, text, text, text, text, jsonb, jsonb, jsonb);
drop function if exists app_private.upsert_catalog_package_variant(uuid, text, text, text, text, text, jsonb, jsonb, jsonb);

create or replace function app_private.upsert_catalog_package_variant(
    p_package_id uuid,
    p_context_key text,
    p_title text,
    p_summary text,
    p_intro_text text default null,
    p_audience_label text default null,
    p_parameter_schema jsonb default null,
    p_default_bindings jsonb default null,
    p_binding_overrides jsonb default null,
    p_problem_text text default null,
    p_when_to_use text default null,
    p_outcome_text text default null
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
        parameter_schema, default_bindings, binding_overrides,
        problem_text, when_to_use, outcome_text
    ) values (
        p_package_id, p_context_key, p_title, p_summary, p_intro_text, p_audience_label,
        p_parameter_schema, coalesce(p_default_bindings, '{}'::jsonb), coalesce(p_binding_overrides, '[]'::jsonb),
        p_problem_text, p_when_to_use, p_outcome_text
    )
    on conflict (package_id, context_key) do update
    set title = excluded.title,
        summary = excluded.summary,
        intro_text = coalesce(p_intro_text, catalog_package_variants.intro_text),
        audience_label = coalesce(p_audience_label, catalog_package_variants.audience_label),
        parameter_schema = coalesce(p_parameter_schema, catalog_package_variants.parameter_schema),
        default_bindings = coalesce(p_default_bindings, catalog_package_variants.default_bindings),
        binding_overrides = coalesce(p_binding_overrides, catalog_package_variants.binding_overrides),
        problem_text = coalesce(p_problem_text, catalog_package_variants.problem_text),
        when_to_use = coalesce(p_when_to_use, catalog_package_variants.when_to_use),
        outcome_text = coalesce(p_outcome_text, catalog_package_variants.outcome_text)
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
    p_binding_overrides jsonb default null,
    p_problem_text text default null,
    p_when_to_use text default null,
    p_outcome_text text default null
) returns public.catalog_package_variants
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.upsert_catalog_package_variant(
        p_package_id, p_context_key, p_title, p_summary, p_intro_text, p_audience_label,
        p_parameter_schema, p_default_bindings, p_binding_overrides,
        p_problem_text, p_when_to_use, p_outcome_text
    );
$$;

revoke all on function public.upsert_catalog_package_variant(
    uuid, text, text, text, text, text, jsonb, jsonb, jsonb, text, text, text
) from public;
grant execute on function public.upsert_catalog_package_variant(
    uuid, text, text, text, text, text, jsonb, jsonb, jsonb, text, text, text
) to authenticated;

-- 2. upsert_catalog_package_metadata: ny RPC för area/tags/is_indexable
--    på catalog_packages, som helt saknar en skriv-väg idag.
create or replace function app_private.upsert_catalog_package_metadata(
    p_package_id uuid,
    p_area text default null,
    p_tags text[] default null,
    p_is_indexable boolean default null,
    p_is_indexable_provided boolean default false
)
returns public.catalog_packages
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_package public.catalog_packages;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    update public.catalog_packages
       set area = coalesce(p_area, catalog_packages.area),
           tags = coalesce(p_tags, catalog_packages.tags),
           is_indexable = case
               when p_is_indexable_provided then p_is_indexable
               else catalog_packages.is_indexable
           end,
           updated_by = auth.uid()
     where id = p_package_id
     returning * into v_package;

    if not found then
        raise exception 'Paketet hittades inte.';
    end if;

    return v_package;
end;
$$;

create or replace function public.upsert_catalog_package_metadata(
    p_package_id uuid,
    p_area text default null,
    p_tags text[] default null,
    p_is_indexable boolean default null,
    p_is_indexable_provided boolean default false
) returns public.catalog_packages
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.upsert_catalog_package_metadata(
        p_package_id, p_area, p_tags, p_is_indexable, p_is_indexable_provided
    );
$$;

revoke all on function public.upsert_catalog_package_metadata(
    uuid, text, text[], boolean, boolean
) from public;
grant execute on function public.upsert_catalog_package_metadata(
    uuid, text, text[], boolean, boolean
) to authenticated;
