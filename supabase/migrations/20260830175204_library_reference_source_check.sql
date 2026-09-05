-- 20260831090500_library_reference_source_check.sql
-- Fixup för 20260831090000_library_reference_prompts.sql: content_items_
-- source_check tillät bara 'manual', 'chat_extraction', 'catalog_copy'
-- (20260718100000_copy_catalog_item_to_valvet.sql) -- 'catalog_reference'
-- (used by add_catalog_prompt_to_library) saknades. Fångat av
-- supabase/tests/verify_library_reference_prompts.sql innan merge.

alter table public.content_items
    drop constraint if exists content_items_source_check;
alter table public.content_items
    add constraint content_items_source_check
        check (source in ('manual', 'chat_extraction', 'catalog_copy', 'catalog_reference'));
