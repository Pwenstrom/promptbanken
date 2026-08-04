-- supabase/tests/verify_copy_published_prompt_to_valvet.sql
-- Manuellt körbart end-to-end-flöde mot staging/länkad produktion.
-- copy_published_prompt_to_valvet är auth.uid()-baserad (vanlig inloggad
-- webb-session), INTE nyckelhash-baserad -- kör varje block via role-
-- impersonation som respektive testanvändare (samma metod som
-- rls_test_plan.sql / verify_copy_catalog_item_to_valvet.sql).
--
-- Fixturer som behövs innan du kör:
-- 1. En Free-personlig-workspace-användare och en Pro-personlig-workspace-
--    användare (samma två som i verify_valvet_rpcs.sql går bra).
-- 2. Minst 6 publicerade (status='published') catalog_prompts-rader med
--    minst en 'generell' catalog_prompt_variants-rad var -- byt in deras
--    riktiga id:n nedan.

-- 1. Som Free: kopiera en publicerad katalogprompt.
select * from public.copy_published_prompt_to_valvet('<published-prompt-1>');
-- Förväntat: 1 rad. module='valvet', visibility='private', status='draft',
-- source='catalog_copy', source_template_id='<published-prompt-1>',
-- source_version satt (sha256-hex), source_copied_at satt.
-- title/content matchar prompt-variantens title/prompt_text, category
-- matchar variantens area.

-- 2. Som Free: samma anrop igen, utan att arkivera kopian -> dubblettskydd.
select * from public.copy_published_prompt_to_valvet('<published-prompt-1>');
-- Förväntat: returnerar SAMMA rad (samma id) som steg 1. Ingen ny rad skapas.

-- 3. Som Free: kopiera 4 ytterligare UNIKA publicerade prompts (steg 1 var
-- den första, så detta är kopia 2-5 denna kalendermånad), sedan en sjätte.
select * from public.copy_published_prompt_to_valvet('<published-prompt-2>');
select * from public.copy_published_prompt_to_valvet('<published-prompt-3>');
select * from public.copy_published_prompt_to_valvet('<published-prompt-4>');
select * from public.copy_published_prompt_to_valvet('<published-prompt-5>');
select * from public.copy_published_prompt_to_valvet('<published-prompt-6>');
-- Förväntat: prompt-2 t.o.m. prompt-5 lyckas (totalt 5 unika kopior denna
-- månad, inklusive steg 1). prompt-6 ger ERROR 'Månadskvoten på 5 kopior är
-- förbrukad. Uppgradera till Pro för obegränsad kopiering.'
-- OBS: delar kvot med copy_catalog_item_to_valvet/copy_template_to_valvet
-- (samma app_private.valvet_catalog_copies-tabell) -- kör detta test i ett
-- workspace som inte redan gjort andra katalogkopior denna månad.

-- 4. Som Pro: upprepa kopiering 6+ gånger (unika källor) -- ingen kvotfel.
-- Förväntat: alla lyckas, ingen ERROR om månadskvot.

-- 5. Kontextfallback: kopiera en prompt som har både en 'generell'- och en
-- t.ex. 'skola'-variant, med p_context_keys=array['skola'].
select * from public.copy_published_prompt_to_valvet('<prompt-with-skola-variant>', array['skola']);
-- Förväntat: title/content_hämtas från skola-varianten, inte generell.

-- 6. Okänt/opublicerat id.
select * from public.copy_published_prompt_to_valvet('<draft-or-missing-id>');
-- Förväntat: ERROR 'Den här mallen finns inte.'

-- 7. Kvotavläsning: samma delade RPC som övriga kopieringsvägar.
select * from public.valvet_catalog_copy_quota();
-- Förväntat: som Free, used=antal kopior denna månad (alla vägar
-- inräknade), monthly_limit=5. Som Pro: used=0, monthly_limit=null.
