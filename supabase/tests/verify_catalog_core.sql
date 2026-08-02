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

select proname
from pg_proc
where proname in (
  'list_published_prompts',
  'get_published_prompt',
  'list_published_packages',
  'get_published_package',
  'list_published_package_prompts'
)
order by proname;

-- Chat-driven draft creation
select proname
from pg_proc
where proname in ('create_prompt_draft_from_chat', 'create_package_draft_from_chat')
order by proname;

-- Kontextprofiler: read-RPC:er ska ta text[] (inte text) som kontextparameter
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
where p.proname in (
  'list_published_prompts',
  'get_published_prompt',
  'list_published_packages',
  'get_published_package',
  'list_published_package_prompts'
)
order by p.proname;

-- security_examples: kolumn finns, och de tre publika läs-RPC:erna samt
-- write-RPC:n har fältet i sin signatur.
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'catalog_prompt_variants'
   and column_name = 'security_examples';

select p.proname, pg_get_function_result(p.oid) as return_type
  from pg_proc p
 where p.proname in ('list_published_prompts', 'get_published_prompt', 'get_catalog_prompt_by_id')
   and pg_get_function_result(p.oid) like '%security_examples%';
