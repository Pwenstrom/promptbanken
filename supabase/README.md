# Supabase

This directory contains the proposed Supabase database surface for Promptbanken.
The files under `migrations/` are schema files only. Run and verify them in
staging before any production deployment.

## Migration overview

- `20260612120000_initial_schema.sql` creates enum types, public tables, indexes, and
  triggers for workspaces, profiles, content items, files, and API keys.
- `20260612121000_rls_policies.sql` creates the private helper schema, enables RLS on all
  public tables, defines access policies, and grants table/function privileges.
- `20260612122000_public_views.sql` creates read-only views for API/MCP consumers using
  `security_invoker = true` so underlying RLS still applies on Postgres 15+.

## Run order

Apply the migrations in order in a staging Supabase project first:

1. `20260612120000_initial_schema.sql`
2. `20260612121000_rls_policies.sql`
3. `20260612122000_public_views.sql`

Do not run these directly in production until staging has verified schema
creation, RLS behavior, API exposure, and rollback/recovery expectations.

## Bootstrap first platform owner

The RLS model intentionally requires an initial trusted bootstrap step. After
the first Auth user exists, use the service role or another trusted database
admin path to create:

1. The initial `public.workspaces` row.
2. A `public.profiles` row for that user's `auth.users.id`.
3. The role value `platform_owner` on that profile.

After this bootstrap, platform owners can administer workspaces and profiles
through the normal authenticated policies. Keep the service role key server-side
only and never expose it in browser code or public environment variables.

## Before production

Review these points before deploying to production:

- Confirm migration filenames and migration history match Supabase CLI
  expectations for the target project.
- Confirm the project runs Postgres 15 or newer if relying on
  `security_invoker = true` views.
- Run the RLS scenarios in `tests/rls_test_plan.sql` against staging.
- Run Supabase advisors, if available, and review any security/performance
  findings before release.
- Verify Data API exposure settings and grants for `anon` and `authenticated`.
- Confirm `api_keys.key_hash` is never exposed through public views, logs, or
  client responses.
- Confirm all service-role usage is restricted to trusted backend/bootstrap
  code.
- Confirm that preserving `published_at` on unpublish matches the intended
  audit semantics before production data is created.
