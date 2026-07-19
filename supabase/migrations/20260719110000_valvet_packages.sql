-- 20260719110000_valvet_packages.sql
-- Delprojekt 3: promptpaket i Valvet. Paket = pro_prompt_templates 7 områden.
-- Aktivering = prenumerationsrad; kopiering per mall via ny RPC som speglar
-- copy_catalog_item_to_valvet (delad månadskvot, ingen dedup -- se spec
-- docs/superpowers/specs/2026-07-19-promptpaket-design.md).

-- 1. Aktiveringstabell, direkt webb-CRUD via RLS (samma mönster som Valvets
-- övriga CRUD).
create table if not exists public.valvet_package_activations (
    id           uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete cascade,
    area         text not null,
    created_at   timestamptz not null default now(),
    unique (workspace_id, area)
);

alter table public.valvet_package_activations enable row level security;

drop policy if exists "valvet_package_activations_select" on public.valvet_package_activations;
create policy "valvet_package_activations_select"
on public.valvet_package_activations
for select to authenticated
using (
    exists (
        select 1 from public.profiles p
          join public.workspaces w on w.id = p.workspace_id
         where p.user_id = (select auth.uid())
           and p.workspace_id = valvet_package_activations.workspace_id
           and w.type = 'personal'
    )
);

drop policy if exists "valvet_package_activations_insert" on public.valvet_package_activations;
create policy "valvet_package_activations_insert"
on public.valvet_package_activations
for insert to authenticated
with check (
    exists (
        select 1 from public.profiles p
          join public.workspaces w on w.id = p.workspace_id
         where p.user_id = (select auth.uid())
           and p.workspace_id = valvet_package_activations.workspace_id
           and w.type = 'personal'
    )
);

drop policy if exists "valvet_package_activations_delete" on public.valvet_package_activations;
create policy "valvet_package_activations_delete"
on public.valvet_package_activations
for delete to authenticated
using (
    exists (
        select 1 from public.profiles p
          join public.workspaces w on w.id = p.workspace_id
         where p.user_id = (select auth.uid())
           and p.workspace_id = valvet_package_activations.workspace_id
           and w.type = 'personal'
    )
);

revoke all on table public.valvet_package_activations from public;
grant select, insert, delete on table public.valvet_package_activations to authenticated;

-- 2. Kopiera en mall ur pro_prompt_templates till eget valv. Spegel av
-- app_private.copy_catalog_item_to_valvet med tre avvikelser: källa är
-- pro_prompt_templates, ingen dubblettdedup (source_content_item_id-FK:n
-- pekar på content_items och kan inte bära template-id), och mappningen
-- type='prompt'/category=area_label/content=prompt_text.
create or replace function app_private.copy_template_to_valvet(
    p_template_id uuid
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ws         public.workspaces%rowtype;
    v_source     public.pro_prompt_templates%rowtype;
    v_row        public.content_items%rowtype;
    v_copy_count integer;
    v_slug       text;
    v_is_pro     boolean;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

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

    v_is_pro := app_private.has_active_pro_entitlement(v_ws.owner_user_id);

    select * into v_source
      from public.pro_prompt_templates
     where id = p_template_id;

    if not found then
        raise exception 'Den här mallen finns inte.';
    end if;

    -- Delad månadskvot med katalogkopiorna (Free 5/mån).
    if not v_is_pro then
        select count(*) into v_copy_count
          from app_private.valvet_catalog_copies
         where workspace_id = v_ws.id
           and created_at >= date_trunc('month', now());

        if v_copy_count >= 5 then
            raise exception 'Månadskvoten på 5 kopior är förbrukad. Uppgradera till Pro för obegränsad kopiering.';
        end if;
    end if;

    v_slug := app_private.slugify_candidate(v_source.title, 'valv');
    while exists (select 1 from public.content_items where workspace_id = v_ws.id and slug = v_slug) loop
        v_slug := app_private.slugify_candidate(v_source.title, 'valv') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    end loop;

    perform set_config('request.jwt.claim.sub', v_ws.owner_user_id::text, true);

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, module, title, slug,
        content, category, status, visibility, source, source_content_item_id
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id,
        'prompt'::public.content_item_type, 'valvet',
        v_source.title, v_slug, v_source.prompt_text, v_source.area_label,
        'draft', 'private', 'catalog_copy', null
    )
    returning * into v_row;

    -- Loggen bär template-id i source_content_item_id (kolumnen saknar FK).
    insert into app_private.valvet_catalog_copies (workspace_id, source_content_item_id)
    values (v_ws.id, p_template_id);

    return v_row;
end;
$$;

revoke all on function app_private.copy_template_to_valvet(uuid) from public;

create or replace function public.copy_template_to_valvet(p_template_id uuid)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.copy_template_to_valvet(p_template_id);
$$;

revoke all on function public.copy_template_to_valvet(uuid) from public;
grant execute on function public.copy_template_to_valvet(uuid) to authenticated;
