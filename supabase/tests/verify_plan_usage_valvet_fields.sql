-- supabase/tests/verify_plan_usage_valvet_fields.sql
-- Manuellt körbart mot staging. get_plan_usage är auth.uid()-baserad --
-- kör varje block via SQL-editorns role-impersonation som respektive
-- testanvändare (samma metod som verify_copy_catalog_item_to_valvet.sql),
-- inte som postgres-superuser.
--
-- Fixturer: samma Free- och Pro-personlig-workspace-användare som i
-- verify_valvet_rpcs.sql. Byt in respektive workspace-id nedan.

-- 1. Som Free-användare med känt antal aktiva Valvet-items, X sparningar
--    via MCP denna månad och Y katalogkopior denna månad:
select * from public.get_plan_usage('<free-workspace-id>');
-- Förväntat (FÖRE migrationen): 9 kolumner, inga valvet_-fält.
-- Förväntat (EFTER migrationen): 15 kolumner. De första nio oförändrade
-- (max_prompts=3, max_mcp_keys=1 för Free). Dessutom:
--   valvet_items_used   = antal content_items med module='valvet',
--                         owner = workspace-ägaren, status <> 'archived'
--   valvet_items_max    = 50
--   monthly_saves_used  = antal rader i app_private.mcp_write_attempts med
--                         tool='save_my_item', outcome='success',
--                         created_at >= date_trunc('month', now())
--   monthly_saves_max   = 5
--   catalog_copies_used = antal rader i app_private.valvet_catalog_copies
--                         denna kalendermånad
--   catalog_copies_max  = 5

-- 2. Som Pro-användare:
select * from public.get_plan_usage('<pro-workspace-id>');
-- Förväntat: valvet_items_max=1000, monthly_saves_max=null,
-- catalog_copies_max=null (obegränsat). used-kolumnerna räknas ändå.

-- 3. Korsreferens mot befintliga kvot-RPC:er (samma användare som steg 1):
select * from public.valvet_catalog_copy_quota();
-- Förväntat: used = catalog_copies_used från steg 1, monthly_limit = 5.

-- 4. Som medlem i en delad addon-yta (organization utan licens):
select * from public.get_plan_usage('<addon-workspace-id>');
-- Förväntat: de nio första kolumnerna som före migrationen; alla sex
-- valvet-/kvotfält är 0 respektive null (Valvet är personligt).

-- 5. Admin-regression: logga in i admin.html som valfri användare och
-- kontrollera att planpanelen (Din plan/användning) renderar som förut.
