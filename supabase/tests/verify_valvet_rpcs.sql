-- supabase/tests/verify_valvet_rpcs.sql
-- Manuellt körbart end-to-end-flöde mot staging. Kräver två test-nycklars
-- rå-värden (en Free-, en Pro-workspace) redan skapade via webbflödet
-- eller seed-scriptet, och deras sha256-hex-hashar.

-- 1. Tomt valv.
select * from public.list_my_items_for_key('<free-hash>');
-- Förväntat: 0 rader.

-- 2. Spara en prompt och en assistent (Free, inom kvoten).
select * from public.save_my_item_for_key('<free-hash>', gen_random_uuid(), 'prompt', 'Mitt första test', 'Innehåll här', 'Kategori A');
select * from public.save_my_item_for_key('<free-hash>', gen_random_uuid(), 'assistant', 'Min assistent', 'Du är en hjälpsam...', null);

-- 3. Lista, sök, hämta.
select * from public.list_my_items_for_key('<free-hash>');
-- Förväntat: 2 rader.
select * from public.search_my_items_for_key('<free-hash>', 'första');
-- Förväntat: 1 rad (prompten).
select * from public.get_my_item_for_key('<free-hash>', (select id from public.list_my_items_for_key('<free-hash>') limit 1));
-- Förväntat: 1 rad.

-- 4. Free kan INTE uppdatera/arkivera via MCP.
select * from public.update_my_item_for_key('<free-hash>', (select id from public.list_my_items_for_key('<free-hash>') limit 1), now());
-- Förväntat: ERROR 'Uppgradera till Pro för att uppdatera via MCP.'

-- 5. Pro: fullständig CRUD.
select * from public.save_my_item_for_key('<pro-hash>', gen_random_uuid(), 'prompt', 'Pro-test', 'Innehåll', null);
select * from public.update_my_item_for_key(
    '<pro-hash>',
    (select id from public.list_my_items_for_key('<pro-hash>') where title = 'Pro-test'),
    (select updated_at from public.list_my_items_for_key('<pro-hash>') where title = 'Pro-test'),
    'Pro-test (redigerad)'
);
select * from public.archive_my_item_for_key(
    '<pro-hash>',
    (select id from public.list_my_items_for_key('<pro-hash>', null, null, 'draft') where title = 'Pro-test (redigerad)'),
    true, false
);
-- Förväntat: alla lyckas, ingen ERROR.

-- 6. Sanity: type='assistant'-rader räknas ALDRIG mot kommunens 3-taket
-- (skapa en fjärde/femte assistant-rad på ett Free-workspace som redan har
-- 3 module='kommun'-prompts -- ska gå bra, ingen ERROR om kommun-taket).
