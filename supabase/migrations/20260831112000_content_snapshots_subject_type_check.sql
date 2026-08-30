-- 20260831112000_content_snapshots_subject_type_check.sql
-- Fixup for 20260831110000_creator_shares_private_content.sql: that
-- migration widened creator_shares.subject_type to accept 'draft_prompt'/
-- 'package_draft' but missed the identical check constraint on
-- content_snapshots (20260825090000_creator_shares.sql line 25). Without
-- this, the PINNED path (p_pin_version=true) for the two new subject types
-- is completely broken -- create_creator_share fails with
-- "new row for relation content_snapshots violates check constraint
-- content_snapshots_subject_type_check" the moment it tries to store the
-- locked-version copy. Caught by re-running the pinned path after the
-- app_private.build_content_payload revoke fixup (20260831111500).

alter table public.content_snapshots
    drop constraint if exists content_snapshots_subject_type_check;

alter table public.content_snapshots
    add constraint content_snapshots_subject_type_check
        check (subject_type in ('prompt', 'package', 'draft_prompt', 'package_draft'));
