-- Städar bort de breda tabellgrants som projektets default-privilege ger
-- nya tabeller i public. Samma fälla som
-- 20260816120000_creator_profiles_fix_default_privilege_grant.sql fångade
-- för creator_profiles.
--
-- Läget före denna migration: creator_package_drafts, creator_package_items
-- och creator_submission_screenings hade INSERT/UPDATE/DELETE/TRUNCATE för
-- både anon och authenticated. Inte exploaterbart — RLS är påslaget och de
-- saknar skrivpolicies — men grants och policies är två oberoende lager, och
-- en framtida bred policy skulle annars öppna direktskrivning via PostgREST
-- förbi RPC:erna.
--
-- Efter: bara den select som delprojekt 3 uttryckligen ville ha, och noll
-- åtkomst till granskningsloggen.

revoke all on public.creator_package_drafts from anon, authenticated;
revoke all on public.creator_package_items from anon, authenticated;
revoke all on public.creator_submission_screenings from anon, authenticated;

-- Återställ den avsedda läsrätten från 20260819090000_creator_authoring.sql.
-- RLS-policyn creator_package_drafts_select_own begränsar den till egna rader.
grant select on public.creator_package_drafts to authenticated;
grant select on public.creator_package_items to authenticated;

-- creator_submission_screenings får medvetet ingen grant alls. Läsning sker
-- via de platform_owner-gatade RPC:erna, skrivning via edge-funktionens
-- service_role. En creator ska inte kunna läsa AI-omdömet om sitt inskick.
