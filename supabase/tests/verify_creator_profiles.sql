-- supabase/tests/verify_creator_profiles.sql
-- Manuell checklista för creator_profiles-tabellen, RLS och RPC:erna.
-- Varje select nedan ska returnera noll rader vid godkänt.

-- 1. Tabellen finns.
select 'creator_profiles saknas' as fel
 where to_regclass('public.creator_profiles') is null;

-- 2. Alla kolumner enligt spec finns.
select 'creator_profiles saknar kolumn' as fel, c.expected
  from (values
        ('id'), ('user_id'), ('slug'), ('display_name'), ('bio_short'),
        ('bio_long'), ('competence_areas'), ('organisation'), ('website_url'),
        ('linkedin_url'), ('avatar_url'), ('status'), ('published_at'),
        ('slug_locked'), ('created_at'), ('updated_at')
       ) as c(expected)
 where not exists (
     select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'creator_profiles'
        and column_name = c.expected
 );

-- 3. RLS är aktiverad på tabellen.
select 'RLS är inte aktiverad på creator_profiles' as fel
 where not exists (
     select 1 from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'creator_profiles'
        and c.relrowsecurity
 );

-- 4. Båda select-policyerna finns.
select 'saknar policy' as fel, p.expected
  from (values ('creator_profiles_select_own'), ('creator_profiles_select_published')) as p(expected)
 where not exists (
     select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'creator_profiles'
        and policyname = p.expected
 );

-- 5. Alla åtta RPC:erna finns i public-schemat.
select 'saknar public-RPC' as fel, r.expected
  from (values
        ('upsert_my_creator_profile'),
        ('publish_my_creator_profile'),
        ('unpublish_my_creator_profile'),
        ('get_my_creator_profile'),
        ('list_published_creator_profiles'),
        ('get_published_creator_profile'),
        ('admin_update_creator_profile_slug'),
        ('admin_unpublish_creator_profile')
       ) as r(expected)
 where not exists (
     select 1 from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = r.expected
 );

-- 5b. Motsvarande app_private-implementationer finns också.
select 'saknar app_private-funktion' as fel, r.expected
  from (values
        ('upsert_my_creator_profile'),
        ('publish_my_creator_profile'),
        ('unpublish_my_creator_profile'),
        ('admin_update_creator_profile_slug'),
        ('admin_unpublish_creator_profile'),
        ('creator_slug_is_reserved'),
        ('creator_slugify'),
        ('creator_url_is_valid')
       ) as r(expected)
 where not exists (
     select 1 from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app_private'
        and p.proname = r.expected
 );

-- 6. creator_slugify normaliserar svenska tecken korrekt.
select 'creator_slugify(Anna Andersson) fel' as fel
 where app_private.creator_slugify('Anna Andersson') is distinct from 'anna-andersson';

select 'creator_slugify(Åsa Öberg) fel' as fel
 where app_private.creator_slugify('Åsa Öberg') is distinct from 'asa-oberg';

-- 7. creator_slug_is_reserved flaggar reserverade namn.
select 'creator_slug_is_reserved(Promptbanken) fel' as fel
 where app_private.creator_slug_is_reserved('Promptbanken') is distinct from true;

-- 8. creator_url_is_valid avvisar icke-http(s)-länkar och accepterar giltiga.
select 'creator_url_is_valid(javascript:) fel' as fel
 where app_private.creator_url_is_valid('javascript:alert(1)') is distinct from false;

select 'creator_url_is_valid(https://example.com) fel' as fel
 where app_private.creator_url_is_valid('https://example.com') is distinct from true;

-- 9. public.creator_profiles har en explicit table-grant (select) till
--    anon och authenticated, utöver RLS-policyerna (samma mönster som
--    20260612121000_rls_policies.sql).
select 'saknar table-grant' as fel, g.expected_grantee
  from (values ('anon'), ('authenticated')) as g(expected_grantee)
 where not exists (
     select 1 from information_schema.role_table_grants
      where table_schema = 'public'
        and table_name = 'creator_profiles'
        and privilege_type = 'SELECT'
        and grantee = g.expected_grantee
 );

-- Obs: att invalid-format p_slug och dubbel-slug faktiskt ger svenska
-- felmeddelanden i app_private.upsert_my_creator_profile och
-- admin_update_creator_profile_slug kräver en inloggad auth.uid()-session
-- (självbetjäningsfunktionen) respektive platform_owner-kontext
-- (adminfunktionen) och går inte att uttrycka som en fristående
-- "noll rader vid godkänt"-select i den här filen. Verifieras manuellt
-- eller i ett framtida RPC-integrationstest.
