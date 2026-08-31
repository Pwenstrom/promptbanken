-- Supabase's default privileges auto-grant ALL (arwdDxtm) on every new
-- public-schema table to anon/authenticated. The prior migration's
-- column-restricted `grant select (...)` on creator_profiles was additive
-- on top of that pre-existing table-wide grant and did not narrow it --
-- user_id and avatar_url remained fully readable, verified via
-- has_column_privilege() in supabase/tests/verify_creator_profiles.sql
-- (checks 9/9b) after applying 20260816090000_creator_profiles.sql to
-- production. Revoke the default-privilege grant explicitly, then
-- re-apply the intended column-restricted select-only access. RLS still
-- gates insert/update/delete (no policies for those), but the underlying
-- table grant must not itself allow them either.
revoke all on public.creator_profiles from anon, authenticated;

grant select (
    id, slug, display_name, bio_short, bio_long, competence_areas,
    organisation, website_url, linkedin_url, status, published_at,
    slug_locked, created_at, updated_at
) on public.creator_profiles to anon, authenticated;
