-- supabase/tests/verify_library_usage_events.sql
-- Manual verification for open library usage analytics.
-- Run against staging/local with representative anon, normal authenticated,
-- and platform_owner contexts.

-- 1. As anon: this should succeed and return {"accepted": true}.
select public.track_library_usage_event(
  p_source := 'web',
  p_event_type := 'prompt_view',
  p_outcome := 'success',
  p_prompt_slug := 'testprompt',
  p_context_keys := array['generell'],
  p_metadata := jsonb_build_object('filter_key', 'context', 'filter_value', 'generell')
);

-- 2. As anon/open MCP: search metadata should be accepted for aggregate search feedback.
select public.track_library_usage_event(
  p_source := 'open_mcp',
  p_event_type := 'search',
  p_outcome := 'empty',
  p_context_keys := array['kommun'],
  p_result_count := 0,
  p_metadata := jsonb_build_object('tool', 'search_prompts')
);

-- 3. As anon: direct table read should fail or return no rows because no SELECT grant/policy exists.
select * from public.library_usage_events order by created_at desc limit 1;

-- 4. As anon: invalid metadata key should fail.
select public.track_library_usage_event(
  p_source := 'web',
  p_event_type := 'prompt_view',
  p_metadata := jsonb_build_object('user_agent', 'do-not-store')
);

-- 5. As normal authenticated non-platform user: admin summary should fail.
select public.get_library_usage_summary(30);

-- 6. As platform_owner: admin summary should return aggregate JSON.
select public.get_library_usage_summary(30);

-- 7. As platform_owner: prompt aggregate should include the test slug after Step 1.
select * from public.get_library_prompt_usage(30, 10)
 where prompt_slug = 'testprompt';

-- 9. As platform_owner: the test slug from Step 1/7 has no matching catalog_prompts
--    row, so prompt_title must be null (frontend renders the "(borttagen — slug)"
--    fallback, SQL does not guess).
select prompt_slug, prompt_title
  from public.get_library_prompt_usage(30, 10)
 where prompt_slug = 'testprompt';
-- Expected: one row, prompt_title is null.

-- 10. As platform_owner: pick a slug that has BOTH a catalog_prompts row and at
--     least one usage event (get_library_prompt_usage only returns slugs with
--     usage events, so a published-but-never-used slug would return zero rows
--     here even though everything works) and confirm prompt_title resolves to
--     a real title, not the slug itself. Replace '<real-published-slug>' with
--     a slug from:
--     select e.prompt_slug from public.library_usage_events e
--       join public.catalog_prompts cp on cp.slug = e.prompt_slug limit 1;
select prompt_slug, prompt_title
  from public.get_library_prompt_usage(365, 200)
 where prompt_slug = '<real-published-slug>';
-- Expected: prompt_title is non-null and differs from prompt_slug when the
-- catalog title differs from the slug (true for legacy-* seeded slugs).

-- 8. Cleanup can be performed by service role only if the staging data should be removed:
-- delete from public.library_usage_events where prompt_slug = 'testprompt';
