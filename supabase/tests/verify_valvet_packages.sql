-- verify_valvet_packages.sql -- manuell checklista mot live.
-- Delprojekt 3: promptpaket. Spec: docs/superpowers/specs/2026-07-19-promptpaket-design.md
-- Kör block 1-4 som inloggad testanvändare (REST/SQL-editor-impersonation),
-- inte som postgres.

-- 1. Aktivera/avaktivera-rundtur (eget personligt workspace-id):
-- insert into public.valvet_package_activations (workspace_id, area)
-- values ('<mitt-ws-id>', 'kommunikation');
-- select * from public.valvet_package_activations;          -- 1 rad (bara egna)
-- delete from public.valvet_package_activations where area = 'kommunikation';

-- 2. RLS-negativtest: samma insert med NÅGON ANNANS workspace_id ->
--    förväntat: new row violates row-level security policy.

-- 3. Kopiera en mall (template-id från list_pro_templates()):
-- select type, title, category, status, visibility, source, source_content_item_id
--   from public.copy_template_to_valvet('<template-id>');
-- Förväntat: prompt / mallens titel / area_label / draft / private /
--            catalog_copy / null. Posten syns under Mina insättningar.

-- 4. Kvot (Free): kopian ovan räknas mot samma 5/mån som katalogkopior --
--    select * from public.valvet_catalog_copy_quota();  -- used ska ha ökat.
--    6:e kopian samma månad -> 'Månadskvoten på 5 kopior är förbrukad...'.

-- 5. Som postgres: tabell + policies finns:
select relrowsecurity from pg_class where relname = 'valvet_package_activations'; -- true
select polname from pg_policy p join pg_class c on c.oid = p.polrelid
 where c.relname = 'valvet_package_activations';  -- select/insert/delete-policies
