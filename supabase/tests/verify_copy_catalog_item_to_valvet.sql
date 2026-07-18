-- supabase/tests/verify_copy_catalog_item_to_valvet.sql
-- Manuellt körbart end-to-end-flöde mot staging. copy_catalog_item_to_valvet
-- är auth.uid()-baserad (vanlig inloggad webb-session), INTE nyckelhash-
-- baserad -- kör varje block genom Supabase REST API eller SQL-editorns
-- role-impersonation medan du är autentiserad som respektive testanvändare
-- (samma metod som rls_test_plan.sql), inte som postgres-superuser.
--
-- Fixturer som behövs innan du kör:
-- 1. En Free-personlig-workspace-användare och en Pro-personlig-workspace-
--    användare (samma två som i verify_valvet_rpcs.sql går bra).
-- 2. Minst 6 publicerade, publika (visibility='public') content_items-rader
--    med module='kommun' -- byt in deras riktiga id:n nedan.
-- 3. Minst 1 publicerad, workspace-synlig (visibility='workspace')
--    content_items-rad med module='kommun'.

-- 1. Som Free: kopiera en publik katalogpost.
select * from public.copy_catalog_item_to_valvet('<public-item-1>');
-- Förväntat (FÖRE migrationen): ERROR function public.copy_catalog_item_to_valvet(uuid) does not exist.
-- Förväntat (EFTER migrationen): 1 rad. module='valvet', visibility='private',
-- status='draft', source='catalog_copy', source_content_item_id='<public-item-1>'.
-- Dessutom: title/content/category matchar källraden exakt, summary/audience är NULL.

-- 2. Som Free: samma anrop igen, utan att arkivera kopian -> dubblettskydd.
select * from public.copy_catalog_item_to_valvet('<public-item-1>');
-- Förväntat: returnerar SAMMA rad (samma id) som steg 1. Ingen ny rad skapas.

-- 3. Som Free: försök kopiera en workspace-synlig (icke-publik) katalogpost.
select * from public.copy_catalog_item_to_valvet('<workspace-visible-item>');
-- Förväntat: ERROR 'Den här posten finns inte eller kräver Pro.'

-- 4. Som Free: kopiera 4 ytterligare UNIKA publika katalogposter (steg 1 var
-- den första, så detta är kopia 2-5 denna kalendermånad), sedan en sjätte.
select * from public.copy_catalog_item_to_valvet('<public-item-2>');
select * from public.copy_catalog_item_to_valvet('<public-item-3>');
select * from public.copy_catalog_item_to_valvet('<public-item-4>');
select * from public.copy_catalog_item_to_valvet('<public-item-5>');
select * from public.copy_catalog_item_to_valvet('<public-item-6>');
-- Förväntat: item-2 t.o.m. item-5 lyckas (totalt 5 unika kopior denna
-- månad, inklusive steg 1). item-6 ger ERROR 'Månadskvoten på 5 kopior är
-- förbrukad. Uppgradera till Pro för obegränsad kopiering.'

-- 5. Som Pro: kopiera samma workspace-synliga post som i steg 3 -- ska gå bra.
select * from public.copy_catalog_item_to_valvet('<workspace-visible-item>');
-- Förväntat: 1 rad, samma fält som steg 1 fast source_content_item_id pekar
-- på <workspace-visible-item>.

-- 6. Som Pro: upprepa kopiering 6+ gånger (unika källor) -- ingen kvotfel.
-- Förväntat: alla lyckas, ingen ERROR om månadskvot.

-- 7. Typmappning: kopiera en katalogpost med type='guide' eller
-- 'checklist' (byt in ett sådant id nedan).
select * from public.copy_catalog_item_to_valvet('<guide-or-checklist-item>');
-- Förväntat: den nya raden har type='prompt' (inte 'guide'/'checklist').

-- 8. Typmappning: kopiera en katalogpost med type='assistant'.
select * from public.copy_catalog_item_to_valvet('<assistant-item>');
-- Förväntat: den nya raden har type='assistant'.

-- 9. Kvotavläsning: RPC för UI-display.
-- Som Free-användare som redan gjort 2 kopior denna månad:
select * from public.valvet_catalog_copy_quota();
-- Förväntat: used=2, monthly_limit=5.
-- Som Pro-användare:
select * from public.valvet_catalog_copy_quota();
-- Förväntat: used=0, monthly_limit=null (unlimited).
