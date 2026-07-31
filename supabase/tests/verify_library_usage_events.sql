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

-- 8. Cleanup can be performed by service role only if the staging data should be removed:
-- delete from public.library_usage_events where prompt_slug = 'testprompt';
