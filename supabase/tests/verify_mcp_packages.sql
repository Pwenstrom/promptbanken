-- verify_mcp_packages.sql -- manuell checklista mot live.
-- Delprojekt 4: MCP-exponering av promptpaket.

-- 1. Ogiltig nyckel avvisas på alla fyra:
select public.list_active_packages_for_key('finns-inte');  -- ERROR: Ogiltig nyckel.
select public.activate_package_for_key('finns-inte', 'kommunikation');  -- ERROR: Ogiltig nyckel.
select public.deactivate_package_for_key('finns-inte', 'kommunikation');  -- ERROR: Ogiltig nyckel.
select public.copy_template_to_valvet_for_key('finns-inte', gen_random_uuid(), true);  -- ERROR: Ogiltig nyckel.

-- Med en RIKTIG nyckels sha256-hash nedan (byt in):
-- 2. Aktivera/avaktivera-rundtur, idempotent:
select public.activate_package_for_key('<hash>', 'kommunikation');
select * from public.list_active_packages_for_key('<hash>');  -- 1 rad
select public.activate_package_for_key('<hash>', 'kommunikation');  -- no-op, inget fel
select public.deactivate_package_for_key('<hash>', 'kommunikation');
select * from public.list_active_packages_for_key('<hash>');  -- 0 rader
select public.deactivate_package_for_key('<hash>', 'kommunikation');  -- no-op, inget fel

-- 3. Kopiering kräver confirm=true:
select public.copy_template_to_valvet_for_key('<hash>', '<template-id>', false);
-- ERROR: confirm måste vara true för att kopiera en mall.

-- 4. Kopiering med confirm=true lyckas och räknas mot delad kvot:
select type, title, category, status, visibility, source
  from public.copy_template_to_valvet_for_key('<hash>', '<template-id>', true);
-- prompt / mallens titel / area_label / draft / private / catalog_copy
select * from public.valvet_catalog_copy_quota();  -- used ökat med 1

-- 5. Rate limit (20/60s) delas med andra skrivverktyg, aktivera/avaktivera opåverkade:
-- kör copy_template_to_valvet_for_key 21 ggr snabbt -> 21:a avvisas
-- ("För många försök, vänta en minut och försök igen.");
-- aktivera/avaktivera fungerar fortfarande direkt efter utan väntan.
