-- supabase/tests/verify_catalog_package_seo_fields.sql
-- Kör mot staging eller länkad utvecklingsdatabas efter migrationen.

-- 1. Kolumnerna finns
select 'catalog_package_variants saknar kolumn' as fel, c.expected
  from (values ('problem_text'), ('when_to_use'), ('outcome_text')) as c(expected)
 where not exists (
     select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'catalog_package_variants'
        and column_name = c.expected
 );

select 'catalog_packages saknar kolumn' as fel, c.expected
  from (values ('area'), ('tags'), ('is_indexable')) as c(expected)
 where not exists (
     select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'catalog_packages'
        and column_name = c.expected
 );

-- 2. RPC:erna returnerar de nya fälten
select 'list_published_packages saknar fält' as fel
 where not exists (
     select 1
       from information_schema.parameters
      where specific_schema = 'public'
        and parameter_name = 'is_indexable'
        and specific_name like 'list_published_packages%'
 );

select 'get_published_package saknar fält' as fel
 where not exists (
     select 1
       from information_schema.parameters
      where specific_schema = 'public'
        and parameter_name = 'is_indexable'
        and specific_name like 'get_published_package%'
 );

-- 3. RPC:erna går fortfarande att anropa med oförändrad signatur
select count(*) >= 0 as list_ok
  from public.list_published_packages(array['generell'], null);
