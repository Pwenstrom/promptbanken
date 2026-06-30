-- Add risk_level to content_items so editors can flag prompts by risk,
-- matching the låg/medel/hög terminology already used in script.js.

do $$ begin
    create type public.content_risk_level as enum ('low', 'medium', 'high');
exception
    when duplicate_object then null;
end $$;

alter table public.content_items
    add column if not exists risk_level public.content_risk_level not null default 'low';
