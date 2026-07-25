-- verify_catalog_seed_from_templates.sql
-- Manuell checklista för seedning av katalogtabellerna från befintliga
-- pro_prompt_templates och deras sju områden.

-- 1. Katalogprompts ska nu vara seedade och publicerade.
select count(*) as published_prompt_count
from public.catalog_prompts
where status = 'published';
-- Förväntat: 42

-- 2. Varje seedad prompt ska ha minst en generell variant.
select count(distinct cp.id) as prompts_with_generell_variant
from public.catalog_prompts cp
join public.catalog_prompt_variants cpv
  on cpv.prompt_id = cp.id
where cp.status = 'published'
  and cpv.context_key = 'generell';
-- Förväntat: 42

-- 3. Seedningen ska även ha lagt kontextklassning utöver generell.
select context_key, count(*) as variant_count
from public.catalog_prompt_variants
group by context_key
order by context_key;
-- Förväntat: minst rader för generell, kommun, skola, företag, förening, privat

-- 4. De sju befintliga områdena ska bli publicerade katalogpaket.
select count(*) as published_package_count
from public.catalog_packages
where status = 'published';
-- Förväntat: 7

-- 5. Varje paket ska ha minst en generell variant.
select count(distinct cpkg.id) as packages_with_generell_variant
from public.catalog_packages cpkg
join public.catalog_package_variants cpv
  on cpv.package_id = cpkg.id
where cpkg.status = 'published'
  and cpv.context_key = 'generell';
-- Förväntat: 7

-- 6. Paketkopplingarna ska täcka alla 42 seedade prompts.
select count(*) as package_item_count
from public.catalog_package_items;
-- Förväntat: 42

-- 7. Read-RPC:erna ska ge innehåll för kommunprofilen.
select count(*) as kommun_prompt_results
from public.list_published_prompts(array['kommun']);
-- Förväntat: 42

select count(*) as kommun_package_results
from public.list_published_packages(array['kommun'], null);
-- Förväntat: 7

-- 8. Privatprofilen ska åtminstone få ett mindre, men icke-tomt urval.
select count(*) as privat_prompt_results
from public.list_published_prompts(array['privat']);
-- Förväntat: > 0
