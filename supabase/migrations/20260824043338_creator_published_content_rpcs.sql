-- Publik attribution för creator-innehåll (delprojekt 4).
--
-- Två läs-RPC:er för den statiska sidgeneratorn:
--
-- 1. list_creator_published_content(slug) fyller creator-sidans två
--    nollägen med creatorns faktiskt publicerade paket och prompts.
-- 2. list_catalog_creator_bylines() ger sidgeneratorn en uppslagstabell
--    slug -> creator för "Av <namn>"-raden på katalogens paketsidor.
--
-- Byline-uppslaget ligger medvetet i en egen funktion i stället för som
-- nya returkolumner på list_published_packages. De fem delade läs-RPC:erna
-- läses av både webben och den hostade MCP:n; att röra deras signatur igen
-- för en presentationsdetalj är onödig risk.

create or replace function public.list_creator_published_content(p_slug text)
returns table (
    kind text,
    slug text,
    title text,
    summary text
)
language sql
stable
security definer
set search_path = ''
as $$
    select 'package'::text, cpkg.slug, v.title, v.summary
      from public.catalog_packages cpkg
      join public.creator_profiles prof on prof.id = cpkg.creator_profile_id
      join public.catalog_package_variants v
        on v.package_id = cpkg.id and v.context_key = 'generell'
     where prof.slug = p_slug
       and prof.status = 'published'
       and cpkg.status = 'published'

    union all

    select 'prompt'::text, cp.slug, v.title, v.summary
      from public.catalog_prompts cp
      join public.creator_profiles prof on prof.id = cp.creator_profile_id
      join public.catalog_prompt_variants v
        on v.prompt_id = cp.id and v.context_key = 'generell'
     where prof.slug = p_slug
       and prof.status = 'published'
       and cp.status = 'published'

     order by 1, 3;
$$;

revoke all on function public.list_creator_published_content(text) from public;
grant execute on function public.list_creator_published_content(text) to anon, authenticated, service_role;

create or replace function public.list_catalog_creator_bylines()
returns table (
    kind text,
    slug text,
    creator_slug text,
    creator_display_name text
)
language sql
stable
security definer
set search_path = ''
as $$
    select 'package'::text, cpkg.slug, prof.slug, prof.display_name
      from public.catalog_packages cpkg
      join public.creator_profiles prof on prof.id = cpkg.creator_profile_id
     where cpkg.status = 'published'
       and prof.status = 'published'

    union all

    select 'prompt'::text, cp.slug, prof.slug, prof.display_name
      from public.catalog_prompts cp
      join public.creator_profiles prof on prof.id = cp.creator_profile_id
     where cp.status = 'published'
       and prof.status = 'published';
$$;

revoke all on function public.list_catalog_creator_bylines() from public;
grant execute on function public.list_catalog_creator_bylines() to anon, authenticated, service_role;
