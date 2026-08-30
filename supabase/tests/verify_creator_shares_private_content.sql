-- supabase/tests/verify_creator_shares_private_content.sql
-- Self-contained, rollback-wrapped verification of the generalized
-- creator_shares (draft_prompt/package_draft subject types) and of two
-- bugs this work uncovered:
-- 1. create_creator_share called gen_random_bytes(16) unqualified under
--    `set search_path = ''`, which fails because pgcrypto lives in the
--    `extensions` schema -- a PRE-EXISTING bug, every call to
--    create_creator_share (published OR unpublished content) failed
--    until 20260831110500_create_creator_share_gen_random_bytes_fix.sql.
-- 2. app_private.build_content_payload had no ownership check AND no
--    explicit revoke, so any `authenticated` caller could read someone
--    else's private draft directly -- found by an independent Codex
--    review, fixed in 20260831111500_build_content_payload_revoke_public.sql.
-- 3. content_snapshots.subject_type's check constraint was never widened
--    alongside creator_shares.subject_type, so the PINNED path for the two
--    new subject types was completely broken -- found while re-verifying
--    fix #2, fixed in 20260831112000_content_snapshots_subject_type_check.sql.
-- Same pattern as rls_staging_check.sql / verify_library_reference_prompts.sql:
-- creates its own fixtures, asserts, rolls back -- safe against production.

begin;

create temp table creator_share_priv_results (
  test text primary key,
  ok boolean not null,
  detail text not null
);
grant select, insert, update, delete on table creator_share_priv_results to anon, authenticated;

create temp table creator_share_priv_tokens (
  key text primary key,
  token text not null
);
grant select, insert, update, delete on table creator_share_priv_tokens to anon, authenticated;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('60000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'share.owner@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('60000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'share.other@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.workspaces (id, name, slug, type, plan, owner_user_id, max_prompts, mcp_enabled)
values
  ('61000000-0000-0000-0000-000000000001', 'Share owner ws', 'share-owner-ws', 'personal', 'free', '60000000-0000-0000-0000-000000000001', 3, true),
  ('61000000-0000-0000-0000-000000000002', 'Share other ws', 'share-other-ws', 'personal', 'free', '60000000-0000-0000-0000-000000000002', 3, true);

insert into public.profiles (user_id, workspace_id, role)
values
  ('60000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', 'editor'),
  ('60000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000002', 'editor');

-- Both users have a creator profile, so the "you need a creator profile"
-- gate never masks whether the ownership check itself is correct.
insert into public.creator_profiles (id, user_id, slug, display_name, status)
values
  ('62000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'share-owner-fixture', 'Share Owner', 'draft'),
  ('62000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000002', 'share-other-fixture', 'Share Other', 'draft');

insert into public.catalog_prompts (id, slug, status, creator_profile_id)
values ('63000000-0000-0000-0000-000000000001', 'share-fixture-published-prompt', 'published', '62000000-0000-0000-0000-000000000001');
insert into public.catalog_prompt_variants (prompt_id, context_key, title, summary, prompt_text)
values ('63000000-0000-0000-0000-000000000001', 'generell', 'Published fixture', 'Published summary', 'Published prompt text');

set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);

-- Owner's own unpublished creator prompt (module='kommun', status='draft').
-- visibility='private' matches reality: submit_creator_prompt is what
-- flips visibility to 'public', not a raw insert, and a Free personal
-- workspace can only insert 'private' rows directly.
insert into public.content_items (id, workspace_id, owner_user_id, created_by, type, module, title, slug, content, status, visibility)
values ('64000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'prompt', 'kommun', 'Draft fixture title', 'draft-fixture-title', 'Original draft text', 'draft', 'private');

-- 1. list_my_shareable_content includes the draft.
do $$
declare
    v_row record;
    v_found boolean := false;
begin
    for v_row in select * from public.list_my_shareable_content() loop
        if v_row.kind = 'draft_prompt' and v_row.subject_id = '64000000-0000-0000-0000-000000000001' and v_row.status_label = 'Utkast' then
            v_found := true;
        end if;
    end loop;
    insert into creator_share_priv_results values (
        'list_my_shareable_content includes own draft_prompt',
        v_found,
        case when v_found then 'found' else 'NOT found' end
    );
end $$;

-- 2. Create a share for the draft prompt (unpinned).
do $$
declare
    v_result jsonb;
begin
    v_result := public.create_creator_share('draft_prompt', '64000000-0000-0000-0000-000000000001');
    insert into creator_share_priv_tokens values ('draft', v_result->>'token');
    insert into creator_share_priv_results values (
        'create_creator_share succeeds for own draft_prompt, unpinned',
        (v_result->>'pinned')::boolean = false and v_result->>'token' is not null,
        v_result::text
    );
end $$;

-- 3. get_shared_content returns state=ok, reviewed=false, live content.
do $$
declare
    v_token text;
    v_result jsonb;
begin
    select token into v_token from creator_share_priv_tokens where key = 'draft';
    v_result := public.get_shared_content(v_token);

    insert into creator_share_priv_results values (
        'get_shared_content: draft_prompt state=ok, reviewed=false, live text',
        v_result->>'state' = 'ok'
            and (v_result->>'reviewed')::boolean = false
            and v_result->'content'->>'prompt_text' = 'Original draft text',
        v_result::text
    );
end $$;

-- 4. Edit the source row, re-fetch -> follows latest (no cache) since the
-- share was created unpinned.
do $$
declare
    v_token text;
    v_result jsonb;
begin
    update public.content_items set content = 'Updated draft text'
     where id = '64000000-0000-0000-0000-000000000001';

    select token into v_token from creator_share_priv_tokens where key = 'draft';
    v_result := public.get_shared_content(v_token);

    insert into creator_share_priv_results values (
        'get_shared_content follows latest edit (unpinned)',
        v_result->'content'->>'prompt_text' = 'Updated draft text',
        v_result::text
    );
end $$;

-- 4b. Pinned path for draft_prompt: content_snapshots must accept the new
-- subject_type, and the snapshot must NOT follow later edits.
do $$
declare
    v_result jsonb;
    v_token text;
    v_read jsonb;
begin
    v_result := public.create_creator_share('draft_prompt', '64000000-0000-0000-0000-000000000001', true);
    v_token := v_result->>'token';

    update public.content_items set content = 'Edited after pinning'
     where id = '64000000-0000-0000-0000-000000000001';

    v_read := public.get_shared_content(v_token);

    insert into creator_share_priv_results values (
        'pinned draft_prompt share: snapshot accepted, ignores later edits',
        (v_result->>'pinned')::boolean = true
            and v_read->'content'->>'prompt_text' = 'Updated draft text',
        v_read::text
    );
end $$;

-- 4c. app_private.build_content_payload must be unreachable directly by
-- an ordinary authenticated caller (the ownership check lives one level
-- up, in create_creator_share -- this function has none of its own).
do $$
declare
    v_rejected boolean := false;
begin
    begin
        perform app_private.build_content_payload('draft_prompt', '64000000-0000-0000-0000-000000000001');
    exception
        when insufficient_privilege then
            v_rejected := true;
        when others then
            v_rejected := false;
    end;
    insert into creator_share_priv_results values (
        'build_content_payload is not directly callable by authenticated',
        v_rejected,
        case when v_rejected then 'insufficient_privilege as expected' else 'NOT rejected -- security hole' end
    );
end $$;

-- 5. Published prompt/package path unchanged: reviewed=true.
do $$
declare
    v_result jsonb;
    v_read jsonb;
begin
    v_result := public.create_creator_share('prompt', '63000000-0000-0000-0000-000000000001');
    v_read := public.get_shared_content(v_result->>'token');

    insert into creator_share_priv_results values (
        'published prompt path unchanged: reviewed=true',
        v_read->>'state' = 'ok' and (v_read->>'reviewed')::boolean = true,
        v_read::text
    );
end $$;
reset role;

-- 6. A different creator (with their OWN creator profile, so the "you
-- need a profile" gate can't mask this) cannot share someone else's draft.
set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000002', true);

do $$
declare
    v_rejected boolean := false;
    v_message text;
begin
    begin
        perform public.create_creator_share('draft_prompt', '64000000-0000-0000-0000-000000000001');
    exception
        when others then
            v_rejected := true;
            v_message := sqlerrm;
    end;

    insert into creator_share_priv_results values (
        'other creator (own profile) cannot share someone else''s draft',
        v_rejected and v_message = 'Du kan bara dela ditt eget innehåll.',
        coalesce(v_message, 'NOT rejected -- security hole')
    );
end $$;
reset role;

select test, ok, detail from creator_share_priv_results order by test;

rollback;
