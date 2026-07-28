-- app_private.catalog_history: generic before-update/delete snapshot table,
-- captured by a single trigger function mounted on all four catalog_* tables.
-- See docs/superpowers/specs/2026-07-29-catalog-version-history-design.md.

create table app_private.catalog_history (
    id bigserial primary key,
    table_name text not null,
    row_id uuid not null,
    operation text not null,
    row_data jsonb not null,
    changed_at timestamptz not null default now(),
    changed_by uuid
);

create index catalog_history_table_row_idx
    on app_private.catalog_history (table_name, row_id, changed_at desc);

create function app_private.record_catalog_history()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
    insert into app_private.catalog_history (table_name, row_id, operation, row_data, changed_by)
    values (tg_table_name, old.id, lower(tg_op), to_jsonb(old), auth.uid());
    if tg_op = 'DELETE' then
        return old;
    else
        return new;
    end if;
end;
$$;

create trigger catalog_prompts_history
    before update or delete on public.catalog_prompts
    for each row execute function app_private.record_catalog_history();

create trigger catalog_prompt_variants_history
    before update or delete on public.catalog_prompt_variants
    for each row execute function app_private.record_catalog_history();

create trigger catalog_packages_history
    before update or delete on public.catalog_packages
    for each row execute function app_private.record_catalog_history();

create trigger catalog_package_items_history
    before update or delete on public.catalog_package_items
    for each row execute function app_private.record_catalog_history();
