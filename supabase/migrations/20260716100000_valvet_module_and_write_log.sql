-- 20260716100000_valvet_module_and_write_log.sql
-- Valvet: modul-tagg på content_items, ny typ 'assistant', och en delad
-- skriv-loggtabell för rate limiting/kvot (mönster från
-- docs/superpowers/specs/2026-07-12-mcp-save-as-template-write-design.md,
-- aldrig applicerad som migration -- bygger den nu, generaliserad med en
-- 'tool'-kolumn eftersom flera verktyg (framtida save_workspace_prompt och
-- Valvets save_my_item) delar samma logg).

do $$
begin
    alter type public.content_item_type add value if not exists 'assistant';
exception
    when duplicate_object then null;
end $$;

alter table public.content_items
    add column if not exists module text not null default 'kommun';

do $$
begin
    alter table public.content_items
        add constraint content_items_module_check check (module in ('kommun', 'valvet'));
exception
    when duplicate_object then null;
end $$;

-- content_items.idempotency_key och dess unika index
-- (content_items_idempotency_key_per_workspace) finns redan sedan
-- 20260712100000_save_prompt_for_key.sql -- inget att göra här.

-- Modul-låsning: gäller ALLA UPDATE på content_items, oavsett riktning
-- (kommun->valvet och valvet->kommun), så en post inte kan omklassas för
-- att kringgå ettdera systemets gräns.
create or replace function app_private.lock_content_item_module()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'UPDATE' and old.module is distinct from new.module then
        raise exception 'module kan inte ändras efter att en post skapats.';
    end if;
    return new;
end;
$$;

revoke all on function app_private.lock_content_item_module() from public;

drop trigger if exists lock_content_item_module on public.content_items;
create trigger lock_content_item_module
before update on public.content_items
for each row execute function app_private.lock_content_item_module();

-- app_private.mcp_write_attempts(id, key_hash, workspace_id, outcome,
-- risk_check_passed, created_at) finns redan (20260712100000). Lägger bara
-- till en tool-kolumn så flera write-verktyg kan dela loggen utan att
-- blanda ihop sina kvoter/rate limits. Default matchar det enda
-- write-verktyg som fanns innan denna migration.
alter table app_private.mcp_write_attempts
    add column if not exists tool text not null default 'save_workspace_prompt';

create index if not exists mcp_write_attempts_workspace_tool_created_at_idx
    on app_private.mcp_write_attempts (workspace_id, tool, created_at desc);
