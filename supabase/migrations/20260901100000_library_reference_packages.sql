-- supabase/migrations/20260901100000_library_reference_packages.sql
-- Paket får samma två operationer prompts redan har sedan
-- 20260831090000: en levande referens (add_catalog_package_to_library)
-- och en full, redigerbar kopia (copy_published_package_to_valvet).
-- Ingen ny innehållstabell -- referensen är en nullbar kolumn på
-- creator_package_drafts, och kopian återanvänder den redan befintliga
-- prompt-kopieringen (copy_published_prompt_to_valvet) i en loop plus
-- den redan befintliga add_prompt_to_package_draft. Se
-- docs/superpowers/specs/2026-08-30-connect-my-library-architecture-
-- analysis.md sektion P.4 ("kvarstående gap").

alter table public.creator_package_drafts
    add column if not exists library_ref_catalog_package_id uuid
        references public.catalog_packages(id) on delete set null;

comment on column public.creator_package_drafts.library_ref_catalog_package_id is
    'Satt när utkastet är en levande referens till ett publicerat katalogpaket (inte en kopia). creator_package_items är då tom -- läs innehållet via get_referenced_library_package(id), aldrig via items-tabellen.';

create index if not exists creator_package_drafts_library_ref_idx
    on public.creator_package_drafts (library_ref_catalog_package_id)
    where library_ref_catalog_package_id is not null;

-- 1. Lägg till en paketreferens ---------------------------------------

create or replace function app_private.add_catalog_package_to_library(
    p_package_id uuid
)
returns public.creator_package_drafts
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid      uuid := (select auth.uid());
    v_existing public.creator_package_drafts%rowtype;
    v_row      public.creator_package_drafts%rowtype;
    v_id       uuid;
    v_title    text;
    v_summary  text;
begin
    if v_uid is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    select cpkg.id, v.title, v.summary
      into v_id, v_title, v_summary
      from public.catalog_packages cpkg
      join public.catalog_package_variants v
        on v.package_id = cpkg.id and v.context_key = 'generell'
     where cpkg.id = p_package_id
       and cpkg.status = 'published';

    if v_id is null then
        raise exception 'Det här paketet finns inte.';
    end if;

    select * into v_existing
      from public.creator_package_drafts
     where owner_user_id = v_uid
       and library_ref_catalog_package_id = v_id
       and status <> 'archived';

    if found then
        return v_existing;
    end if;

    insert into public.creator_package_drafts (
        owner_user_id, title, summary, status, library_ref_catalog_package_id
    ) values (
        v_uid, v_title, v_summary, 'draft', v_id
    )
    returning * into v_row;

    return v_row;
end;
$$;

revoke all on function app_private.add_catalog_package_to_library(uuid) from public;

create or replace function public.add_catalog_package_to_library(p_package_id uuid)
returns public.creator_package_drafts
language sql
security definer
set search_path = ''
as $$
    select * from app_private.add_catalog_package_to_library(p_package_id);
$$;

revoke all on function public.add_catalog_package_to_library(uuid) from public;
grant execute on function public.add_catalog_package_to_library(uuid) to authenticated;

-- 2. Läs en paketreferens live -----------------------------------------

create or replace function public.get_referenced_library_package(
    p_draft_id uuid,
    p_context_keys text[] default array['generell'::text]
)
returns table (
    title text,
    summary text,
    intro_text text,
    package_type text,
    item_title text,
    item_summary text,
    item_prompt_text text,
    item_sort_order integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_catalog_id uuid;
begin
    select d.library_ref_catalog_package_id
      into v_catalog_id
      from public.creator_package_drafts d
     where d.id = p_draft_id
       and d.owner_user_id = auth.uid();

    if v_catalog_id is null then
        raise exception 'Ingen paketreferens hittades för det här utkastet.';
    end if;

    return query
        select coalesce(pv_matched.title, pv_fallback.title),
               coalesce(pv_matched.summary, pv_fallback.summary),
               coalesce(pv_matched.intro_text, pv_fallback.intro_text),
               cpkg.package_type,
               coalesce(v_matched.title, v_fallback.title),
               coalesce(v_matched.summary, v_fallback.summary),
               coalesce(v_matched.prompt_text, v_fallback.prompt_text),
               cpi.sort_order
          from public.catalog_packages cpkg
          left join lateral (
              select v.* from public.catalog_package_variants v
               where v.package_id = cpkg.id and v.context_key = any(p_context_keys)
               order by array_position(p_context_keys, v.context_key)
               limit 1
          ) pv_matched on true
          left join public.catalog_package_variants pv_fallback
            on pv_fallback.package_id = cpkg.id and pv_fallback.context_key = 'generell'
          join public.catalog_package_items cpi on cpi.package_id = cpkg.id
          join public.catalog_prompts cp on cp.id = cpi.prompt_id
          left join lateral (
              select v.* from public.catalog_prompt_variants v
               where v.prompt_id = cp.id and v.context_key = any(p_context_keys)
               order by array_position(p_context_keys, v.context_key)
               limit 1
          ) v_matched on true
          left join public.catalog_prompt_variants v_fallback
            on v_fallback.prompt_id = cp.id and v_fallback.context_key = 'generell'
         where cpkg.id = v_catalog_id
           and cpkg.status = 'published'
           and cp.status = 'published'
         order by cpi.sort_order;
end;
$$;

revoke all on function public.get_referenced_library_package(uuid, text[]) from public;
grant execute on function public.get_referenced_library_package(uuid, text[]) to authenticated;

-- 3. Skapa en egen, redigerbar version av ett paket ----------------------

create or replace function app_private.copy_published_package_to_valvet(
    p_package_id   uuid,
    p_context_keys text[] default array['generell'::text]
)
returns public.creator_package_drafts
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid          uuid := (select auth.uid());
    v_pkg_id       uuid;
    v_title        text;
    v_summary      text;
    v_new_draft    public.creator_package_drafts%rowtype;
    v_item         record;
    v_content_item public.content_items%rowtype;
    v_position     integer := 0;
begin
    if v_uid is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    select cpkg.id, v.title, v.summary
      into v_pkg_id, v_title, v_summary
      from public.catalog_packages cpkg
      join public.catalog_package_variants v
        on v.package_id = cpkg.id and v.context_key = 'generell'
     where cpkg.id = p_package_id
       and cpkg.status = 'published';

    if v_pkg_id is null then
        raise exception 'Det här paketet finns inte.';
    end if;

    insert into public.creator_package_drafts (owner_user_id, title, summary, status)
    values (v_uid, v_title, v_summary, 'draft')
    returning * into v_new_draft;

    for v_item in
        select cpi.prompt_id, cpi.sort_order
          from public.catalog_package_items cpi
          join public.catalog_prompts cp on cp.id = cpi.prompt_id
         where cpi.package_id = v_pkg_id
           and cp.status = 'published'
         order by cpi.sort_order
    loop
        v_content_item := app_private.copy_published_prompt_to_valvet(v_item.prompt_id, p_context_keys);

        perform app_private.add_prompt_to_package_draft(
            v_new_draft.id, v_content_item.id, v_position
        );
        v_position := v_position + 1;
    end loop;

    return v_new_draft;
end;
$$;

revoke all on function app_private.copy_published_package_to_valvet(uuid, text[]) from public;

create or replace function public.copy_published_package_to_valvet(
    p_package_id   uuid,
    p_context_keys text[] default array['generell'::text]
)
returns public.creator_package_drafts
language sql
security definer
set search_path = ''
as $$
    select * from app_private.copy_published_package_to_valvet(p_package_id, p_context_keys);
$$;

revoke all on function public.copy_published_package_to_valvet(uuid, text[]) from public;
grant execute on function public.copy_published_package_to_valvet(uuid, text[]) to authenticated;
