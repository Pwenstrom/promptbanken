-- C:\Users\petwen\OneDrive - Höglandsförbundet\Projekt\mcp_promptbanken\promptbanken\supabase\tests\log_write_attempt.sql
-- Kor mot staging efter migrationen. Ersatt <PRO_KEY_HASH> med en riktig
-- Pro-testnyckels hash.

-- 1. save_prompt_for_key ska fortfarande fungera identiskt (ingen
--    beteendeandring for anroparen -- bara loggningsvagen andrades).
select app_private.save_prompt_for_key(
    'not-a-real-hash', 'Test', 'Innehall', 'kommunikation', 'manual', true, null
);
-- Expected: samma exception som innan, 'Ogiltig eller aterkallad MCP-nyckel.'

-- 2. Direktanrop till den nya log_write_attempt-funktionen -> INGEN raise,
--    ska bara lyckas tyst.
select app_private.log_write_attempt('not-a-real-hash', 'invalid_key', true);

-- 3. Verifiera att den raden faktiskt persisterade (till skillnad fran innan).
select outcome, count(*) from app_private.mcp_write_attempts
 where key_hash = 'not-a-real-hash'
 group by outcome;
-- Expected: invalid_key=1 (denna gang persisterar den, eftersom
-- log_write_attempt inte foljs av nagon raise i samma anrop).
