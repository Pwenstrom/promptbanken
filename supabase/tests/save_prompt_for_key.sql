-- C:\Users\petwen\OneDrive - Höglandsförbundet\Projekt\mcp_promptbanken\promptbanken\supabase\tests\save_prompt_for_key.sql
-- Kor mot staging. Ersatt <PRO_KEY_HASH> med sha256 av en riktig Pro-testnyckel,
-- <FREE_KEY_HASH> med sha256 av en Free-nyckel.

-- 1. Ogiltig nyckel -> exception 'Ogiltig eller aterkallad MCP-nyckel.'
select app_private.save_prompt_for_key(
    'not-a-real-hash', 'Test', 'Innehall', 'kommunikation', 'manual', true, null
);

-- 2. Free-nyckel -> exception 'save_workspace_prompt kraver en Pro-nyckel...'
select app_private.save_prompt_for_key(
    '<FREE_KEY_HASH>', 'Test', 'Innehall', 'kommunikation', 'manual', true, null
);

-- 3. Pro-nyckel, risk_check_passed=false -> exception 'risk_check_passed maste vara true...'
select app_private.save_prompt_for_key(
    '<PRO_KEY_HASH>', 'Test', 'Innehall', 'kommunikation', 'manual', false, null
);

-- 4. Pro-nyckel, tom title -> exception 'Ogiltig indata...'
select app_private.save_prompt_for_key(
    '<PRO_KEY_HASH>', '', 'Innehall', 'kommunikation', 'manual', true, null
);

-- 5. Pro-nyckel, giltigt anrop -> lyckas, returnerar en content_items-rad
--    med visibility='private', status='draft', source='manual'.
select * from app_private.save_prompt_for_key(
    '<PRO_KEY_HASH>', 'Mitt testmall', 'Testinnehall for verifiering.', 'kommunikation', 'manual', true, gen_random_uuid()
);

-- 6. Loggen ska nu innehalla rader for forsok 1-5.
select outcome, count(*) from app_private.mcp_write_attempts group by outcome order by outcome;
-- Expected: invalid_key=1, not_pro=1, risk_check_not_passed=1, invalid_input=1, success=1
