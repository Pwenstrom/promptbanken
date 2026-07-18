-- 20260718100000_copy_catalog_item_to_valvet.sql
-- Delprojekt 2 (kopiera prompt -> Valvet) av Promptbanken/Valvet-katalog-
-- integrationen. Se docs/superpowers/specs/2026-07-18-kopiera-prompt-till-
-- valvet-design.md i valvet_promptbanken-repot för fullständig design.

-- 1. Källspårning: nullable, on delete set null så en borttagen katalogpost
-- inte förstör kopian, bara spårningen.
alter table public.content_items
    add column if not exists source_content_item_id uuid
        references public.content_items(id) on delete set null;

-- 2. Utöka source-taggen med 'catalog_copy' (fanns sen tidigare: 'manual',
-- 'chat_extraction', se 20260712100000_save_prompt_for_key.sql).
alter table public.content_items
    drop constraint if exists content_items_source_check;
alter table public.content_items
    add constraint content_items_source_check
        check (source in ('manual', 'chat_extraction', 'catalog_copy'));

-- 3. Dedicated log table for monthly quota tracking (Free tier only).
-- Separated from content_items to avoid risking kommun/org products that
-- also use that table.
create table if not exists app_private.valvet_catalog_copies (
    id bigint generated always as identity primary key,
    workspace_id uuid not null references public.workspaces(id) on delete cascade,
    source_content_item_id uuid not null,
    created_at timestamptz not null default now()
);

create index if not exists valvet_catalog_copies_workspace_created_at_idx
    on app_private.valvet_catalog_copies (workspace_id, created_at desc);

revoke all on table app_private.valvet_catalog_copies from public;

-- 4. Partial unique index: prevents two concurrent calls from both inserting
-- (race-safe deduplication). Only applies to active (non-archived) copies.
create unique index if not exists content_items_valvet_active_copy_per_source_idx
    on public.content_items (workspace_id, source_content_item_id)
    where module = 'valvet' and status <> 'archived' and source_content_item_id is not null;

-- 5. copy_catalog_item_to_valvet: auth.uid()-baserad (vanlig inloggad
-- webb-session, inte MCP-nyckel -- samma mönster som ensure_personal_workspace()).
create or replace function app_private.copy_catalog_item_to_valvet(
    p_source_item_id uuid
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ws              public.workspaces%rowtype;
    v_source          public.content_items%rowtype;
    v_existing        public.content_items%rowtype;
    v_row             public.content_items%rowtype;
    v_copy_count      integer;
    v_mapped_type     public.content_item_type;
    v_slug            text;
    v_is_pro          boolean;
    v_constraint_name text;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    -- 1. Anroparens personliga arbetsyta (samma join-mönster som
    -- ensure_personal_workspace()) -- inte bara lita på auth.uid() blint.
    select w.* into v_ws
      from public.workspaces w
      join public.profiles p on p.workspace_id = w.id
     where p.user_id = auth.uid()
       and w.type = 'personal'
       and w.status = 'active'
     order by p.created_at
     limit 1;

    if not found then
        raise exception 'Inget personligt workspace hittades.';
    end if;

    -- Check Pro entitlement with expiry validation (not just raw plan flag).
    v_is_pro := app_private.has_active_pro_entitlement(v_ws.owner_user_id);

    -- 2. Källrad + åtkomst: publik för alla, workspace-synlig kräver pro.
    select * into v_source
      from public.content_items
     where id = p_source_item_id
       and module = 'kommun'
       and status = 'published'
       and (
           visibility = 'public'
           or (visibility = 'workspace' and v_is_pro)
       );

    if not found then
        raise exception 'Den här posten finns inte eller kräver Pro.';
    end if;

    -- 3. Dubblettkontroll: samma källa redan kopierad och inte arkiverad ->
    -- returnera den befintliga i stället för att skapa en ny.
    select * into v_existing
      from public.content_items
     where workspace_id = v_ws.id
       and module = 'valvet'
       and source_content_item_id = p_source_item_id
       and status <> 'archived';

    if found then
        return v_existing;
    end if;

    -- 4. Kvot: bara non-pro räknas. Query dedicated log table, not content_items.
    if not v_is_pro then
        select count(*) into v_copy_count
          from app_private.valvet_catalog_copies
         where workspace_id = v_ws.id
           and created_at >= date_trunc('month', now());

        if v_copy_count >= 5 then
            raise exception 'Månadskvoten på 5 kopior är förbrukad. Uppgradera till Pro för obegränsad kopiering.';
        end if;
    end if;

    -- 5. Typmappning: katalogen behåller sina egna typer, bara Valv-kopian
    -- förenklas till Valvets tvåtypersmodell.
    v_mapped_type := case when v_source.type = 'assistant'
                          then 'assistant'::public.content_item_type
                          else 'prompt'::public.content_item_type end;

    -- 6. Slug, samma kollisionsloop som save_my_item_for_key.
    v_slug := app_private.slugify_candidate(v_source.title, 'valv');
    while exists (select 1 from public.content_items where workspace_id = v_ws.id and slug = v_slug) loop
        v_slug := app_private.slugify_candidate(v_source.title, 'valv') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    end loop;

    perform set_config('request.jwt.claim.sub', v_ws.owner_user_id::text, true);

    -- 7. Insert: bara title/content/category/typ kopieras -- summary/audience
    -- finns på källraden men Valvets UI visar dem aldrig. Race-safe via
    -- unique index on (workspace_id, source_content_item_id) where active.
    -- The slug collision loop before insert is non-atomic; if two concurrent
    -- calls hit the same slug, only the dedup index (our new constraint) is
    -- meant to be caught; slug collisions are re-raised.
    begin
        insert into public.content_items (
            workspace_id, owner_user_id, created_by, type, module, title, slug,
            content, category, status, visibility, source, source_content_item_id
        ) values (
            v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id, v_mapped_type, 'valvet',
            v_source.title, v_slug, v_source.content, v_source.category,
            'draft', 'private', 'catalog_copy', p_source_item_id
        )
        returning * into v_row;

        -- Log the copy only if a new row was actually created (not in the
        -- exception handler below, which only handles dedup index collisions).
        insert into app_private.valvet_catalog_copies (workspace_id, source_content_item_id)
        values (v_ws.id, p_source_item_id);

    exception when unique_violation then
        -- Determine which constraint fired. Only handle the dedup index case;
        -- re-raise slug collisions and any other unique violations.
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'content_items_valvet_active_copy_per_source_idx' then
            -- Another concurrent call already inserted the copy for this source.
            -- Re-select and return it.
            select * into v_row
              from public.content_items
             where workspace_id = v_ws.id
               and module = 'valvet'
               and source_content_item_id = p_source_item_id
               and status <> 'archived';
        else
            -- Slug collision or other unique violation; re-raise as-is.
            raise;
        end if;
    end;

    return v_row;
end;
$$;

revoke all on function app_private.copy_catalog_item_to_valvet(uuid) from public;

create or replace function public.copy_catalog_item_to_valvet(p_source_item_id uuid)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.copy_catalog_item_to_valvet(p_source_item_id);
$$;

revoke all on function public.copy_catalog_item_to_valvet(uuid) from public;
grant execute on function public.copy_catalog_item_to_valvet(uuid) to authenticated;
