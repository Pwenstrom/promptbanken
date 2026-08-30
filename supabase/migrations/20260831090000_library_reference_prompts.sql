-- 20260831090000_library_reference_prompts.sql
-- "Lägg till i mitt bibliotek" som referens, inte kopia. Se
-- docs/superpowers/specs/2026-08-30-connect-my-library-architecture-analysis.md,
-- sektion F.
--
-- En referensrad i content_items har module='valvet', content='' (ingen
-- bakad prompttext) och library_ref_catalog_prompt_id satt till
-- källraden i catalog_prompts. Renderingslagret läser prompttexten live via
-- get_referenced_library_prompt istället för content_items.content.
-- source_template_id/source_version/source_copied_at (redan i bruk för
-- copy_published_prompt_to_valvet) sätts INTE på en referensrad -- de
-- betyder "kopierad vid den här tidpunkten", vilket är fel påstående om en
-- rad som medvetet ska följa originalet live.

alter table public.content_items
    add column if not exists library_ref_catalog_prompt_id uuid
        references public.catalog_prompts(id) on delete set null;

comment on column public.content_items.library_ref_catalog_prompt_id is
    'Satt när raden är en levande referens till en publicerad katalogprompt (inte en kopia). content är då tom sträng -- läs prompttexten via get_referenced_library_prompt(id), aldrig via content-kolumnen.';

create index if not exists content_items_library_ref_idx
    on public.content_items (library_ref_catalog_prompt_id)
    where library_ref_catalog_prompt_id is not null;

-- 1. Lägg till en referens -------------------------------------------------

create or replace function app_private.add_catalog_prompt_to_library(
    p_prompt_id uuid
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ws       public.workspaces%rowtype;
    v_existing public.content_items%rowtype;
    v_row      public.content_items%rowtype;
    v_slug     text;
    v_id       uuid;
    v_title    text;
    v_area     text;
begin
    if auth.uid() is null then
        raise exception 'Du måste vara inloggad.';
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

    select cp.id, v.title, v.area
      into v_id, v_title, v_area
      from public.catalog_prompts cp
      join public.catalog_prompt_variants v
        on v.prompt_id = cp.id and v.context_key = 'generell'
     where cp.id = p_prompt_id
       and cp.status = 'published';

    if v_id is null then
        raise exception 'Den här mallen finns inte.';
    end if;

    -- Dubblettskydd: redan tillagd som referens och inte arkiverad -> returnera den.
    select * into v_existing
      from public.content_items
     where workspace_id = v_ws.id
       and module = 'valvet'
       and library_ref_catalog_prompt_id = v_id
       and status <> 'archived';

    if found then
        return v_existing;
    end if;

    v_slug := app_private.slugify_candidate(v_title, 'ref');
    while exists (select 1 from public.content_items where workspace_id = v_ws.id and slug = v_slug) loop
        v_slug := app_private.slugify_candidate(v_title, 'ref') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    end loop;

    perform set_config('request.jwt.claim.sub', v_ws.owner_user_id::text, true);

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, module, title, slug,
        content, category, status, visibility, source, library_ref_catalog_prompt_id
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id,
        'prompt'::public.content_item_type, 'valvet',
        v_title, v_slug, '', v_area,
        'draft', 'private', 'catalog_reference', v_id
    )
    returning * into v_row;

    return v_row;
end;
$$;

revoke all on function app_private.add_catalog_prompt_to_library(uuid) from public;

create or replace function public.add_catalog_prompt_to_library(p_prompt_id uuid)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.add_catalog_prompt_to_library(p_prompt_id);
$$;

revoke all on function public.add_catalog_prompt_to_library(uuid) from public;
grant execute on function public.add_catalog_prompt_to_library(uuid) to authenticated;

-- 2. Läs referensens live-innehåll -----------------------------------------

create or replace function public.get_referenced_library_prompt(
    p_content_item_id uuid,
    p_context_keys text[] default array['generell'::text]
)
returns table (
    title text,
    summary text,
    prompt_text text,
    area text,
    risk_level text,
    security_examples text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_catalog_id uuid;
begin
    select ci.library_ref_catalog_prompt_id
      into v_catalog_id
      from public.content_items ci
     where ci.id = p_content_item_id
       and ci.owner_user_id = auth.uid();

    if v_catalog_id is null then
        raise exception 'Ingen referens hittades för den här posten.';
    end if;

    return query
        select coalesce(matched.title, fallback.title),
               coalesce(matched.summary, fallback.summary),
               coalesce(matched.prompt_text, fallback.prompt_text),
               coalesce(matched.area, fallback.area),
               coalesce(matched.risk_level, fallback.risk_level),
               coalesce(matched.security_examples, fallback.security_examples)
          from public.catalog_prompts cp
          left join lateral (
              select v.* from public.catalog_prompt_variants v
               where v.prompt_id = cp.id and v.context_key = any(p_context_keys)
               order by array_position(p_context_keys, v.context_key)
               limit 1
          ) matched on true
          left join public.catalog_prompt_variants fallback
            on fallback.prompt_id = cp.id and fallback.context_key = 'generell'
         where cp.id = v_catalog_id
           and cp.status = 'published';
end;
$$;

revoke all on function public.get_referenced_library_prompt(uuid, text[]) from public;
grant execute on function public.get_referenced_library_prompt(uuid, text[]) to authenticated;
