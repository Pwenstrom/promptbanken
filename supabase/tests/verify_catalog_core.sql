-- verify_catalog_core.sql
-- Manuell checklista för katalogkärnans schema.

select to_regclass('public.catalog_prompts') is not null as has_catalog_prompts;
select to_regclass('public.catalog_prompt_variants') is not null as has_catalog_prompt_variants;
select to_regclass('public.catalog_packages') is not null as has_catalog_packages;
select to_regclass('public.catalog_package_variants') is not null as has_catalog_package_variants;
select to_regclass('public.catalog_package_items') is not null as has_catalog_package_items;

select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'catalog_prompt_variants'
order by ordinal_position;

select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'catalog_package_items'
order by ordinal_position;

-- Promptflöde
select proname
from pg_proc
where proname in ('create_catalog_prompt', 'upsert_catalog_prompt_variant', 'publish_catalog_prompt')
order by proname;

-- Paketflöde
select proname
from pg_proc
where proname in (
  'create_catalog_package',
  'upsert_catalog_package_variant',
  'add_prompt_to_catalog_package',
  'update_catalog_package_item',
  'remove_prompt_from_catalog_package',
  'publish_catalog_package'
)
order by proname;
