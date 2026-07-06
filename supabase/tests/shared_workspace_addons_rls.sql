-- Kör efter migrationen 20260706100000. Förväntat: tabellen finns, RLS på.
select relrowsecurity from pg_class where relname = 'shared_workspace_addons';
-- Expected: t

select count(*) as policy_count from pg_policies
 where tablename = 'shared_workspace_addons';
-- Expected: 2
