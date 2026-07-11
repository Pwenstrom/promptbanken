-- Adds a place to record why a reviewer sent a prompt back to draft, so
-- the editor can see what to fix without asking in another channel.

alter table public.content_items
    add column if not exists review_note text;
