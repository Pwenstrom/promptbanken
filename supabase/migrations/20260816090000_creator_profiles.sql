-- Creator-profiler: publika, SEO-indexerbara presentationssidor.
-- Se docs/superpowers/specs/2026-08-16-creator-profiler-design.md.
--
-- Obs: public.profiles är arbetsyte-roller, inte visningsprofiler.
-- creator_profiles är knuten till en person (auth.users), inte en workspace.

-- 1. Tabell, index och RLS ------------------------------------------------

create table if not exists public.creator_profiles (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null unique references auth.users(id) on delete cascade,
    slug text not null unique,
    display_name text not null,
    bio_short text,
    bio_long text,
    competence_areas text[],
    organisation text,
    website_url text,
    linkedin_url text,
    -- Reserverad. Används inte förrän filuppladdning finns: en extern
    -- bild-URL på en publik sida läcker besökarens IP till tredje part.
    avatar_url text,
    status text not null default 'draft' check (status in ('draft', 'published')),
    published_at timestamptz,
    slug_locked boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint creator_profiles_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
    constraint creator_profiles_published_at_check check (
        (status = 'published' and published_at is not null)
        or status <> 'published'
    )
);

alter table public.creator_profiles enable row level security;

drop policy if exists "creator_profiles_select_own" on public.creator_profiles;
create policy "creator_profiles_select_own"
    on public.creator_profiles for select
    to authenticated
    using (user_id = (select auth.uid()));

drop policy if exists "creator_profiles_select_published" on public.creator_profiles;
create policy "creator_profiles_select_published"
    on public.creator_profiles for select
    to anon, authenticated
    using (status = 'published');

-- Ingen insert/update/delete-policy: all skrivning går via
-- SECURITY DEFINER-RPC:erna nedan.

create index if not exists creator_profiles_status_idx
    on public.creator_profiles (status)
    where status = 'published';

-- 2. Hjälpfunktioner för slug och validering ------------------------------

-- Reserverade namn: en självbetjäningsprofil på en indexerbar sida under
-- plattformens egen domän får inte kunna utge sig för att vara officiell.
create or replace function app_private.creator_slug_is_reserved(p_value text)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
    select lower(trim(coalesce(p_value, ''))) = any (array[
        'promptbanken', 'admin', 'support', 'official', 'kontakt', 'system',
        'hoglandsforbundet', 'api', 'mcp', 'paket', 'creator', 'creators',
        'workshop', 'valvet'
    ]);
$$;

-- Samma svenska normalisering som areaAnchor i scripts/catalog-page-lib.mjs.
create or replace function app_private.creator_slugify(p_value text)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
    select nullif(
        trim(both '-' from
            regexp_replace(
                regexp_replace(
                    lower(translate(coalesce(p_value, ''), 'åäöÅÄÖéèüÉÈÜ', 'aaoAAOeeuEEU')),
                    '[^a-z0-9]+', '-', 'g'
                ),
                '-+', '-', 'g'
            )
        ),
        ''
    );
$$;

create or replace function app_private.creator_url_is_valid(p_value text)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
    select p_value is null
        or trim(p_value) = ''
        or trim(p_value) ~* '^https?://[^\s<>"]+$';
$$;

revoke all on function app_private.creator_slug_is_reserved(text) from public;
revoke all on function app_private.creator_slugify(text) from public;
revoke all on function app_private.creator_url_is_valid(text) from public;
grant execute on function app_private.creator_slug_is_reserved(text) to authenticated;
grant execute on function app_private.creator_slugify(text) to authenticated;
grant execute on function app_private.creator_url_is_valid(text) to authenticated;

-- 3. Skriv-RPC:er (agerar enbart på auth.uid(), tar aldrig ett user-id) --

create or replace function app_private.upsert_my_creator_profile(
    p_display_name text,
    p_slug text default null,
    p_bio_short text default null,
    p_bio_long text default null,
    p_competence_areas text[] default null,
    p_organisation text default null,
    p_website_url text default null,
    p_linkedin_url text default null
)
returns public.creator_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid;
    v_display_name text;
    v_slug text;
    -- Normaliserade infogningsvärden (tom sträng -> null). Används för
    -- INSERT. Vid UPDATE avgörs "angivet vs utelämnat" av om p_-parametern
    -- själv är null (utelämnad, default) eller inte (angiven, även om tom
    -- sträng -- då ska fältet rensas, inte lämnas orört).
    v_bio_short text;
    v_bio_long text;
    v_organisation text;
    v_website_url text;
    v_linkedin_url text;
    v_existing public.creator_profiles;
    v_profile public.creator_profiles;
begin
    v_uid := auth.uid();
    if v_uid is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    v_display_name := nullif(trim(coalesce(p_display_name, '')), '');
    if v_display_name is null then
        raise exception 'Visningsnamn krävs.';
    end if;

    if app_private.creator_slug_is_reserved(v_display_name) then
        raise exception 'Det namnet är reserverat.';
    end if;

    v_bio_short := nullif(trim(coalesce(p_bio_short, '')), '');
    v_bio_long := nullif(trim(coalesce(p_bio_long, '')), '');
    v_organisation := nullif(trim(coalesce(p_organisation, '')), '');
    v_website_url := nullif(trim(coalesce(p_website_url, '')), '');
    v_linkedin_url := nullif(trim(coalesce(p_linkedin_url, '')), '');

    if not app_private.creator_url_is_valid(v_website_url)
       or not app_private.creator_url_is_valid(v_linkedin_url) then
        raise exception 'Ogiltig länk. Använd en adress som börjar med http:// eller https://.';
    end if;

    select * into v_existing from public.creator_profiles where user_id = v_uid;

    if found and v_existing.slug_locked then
        v_slug := v_existing.slug;
    else
        v_slug := nullif(trim(coalesce(p_slug, '')), '');
        if v_slug is null then
            v_slug := app_private.creator_slugify(v_display_name);
        end if;
        if v_slug is null then
            raise exception 'Kunde inte skapa en giltig adress från namnet.';
        end if;
        if app_private.creator_slug_is_reserved(v_slug) then
            raise exception 'Den adressen är reserverad.';
        end if;
    end if;

    insert into public.creator_profiles (
        user_id, slug, display_name, bio_short, bio_long, competence_areas,
        organisation, website_url, linkedin_url, updated_at
    ) values (
        v_uid, v_slug, v_display_name, v_bio_short, v_bio_long, p_competence_areas,
        v_organisation, v_website_url, v_linkedin_url, now()
    )
    on conflict (user_id) do update
    set slug = v_slug,
        display_name = v_display_name,
        -- p_x null = utelämnad -> orört. p_x angiven (inkl. tom sträng,
        -- normaliserad till null) -> skriv, kan alltså rensa fältet.
        bio_short = case when p_bio_short is null
                         then public.creator_profiles.bio_short
                         else v_bio_short end,
        bio_long = case when p_bio_long is null
                        then public.creator_profiles.bio_long
                        else v_bio_long end,
        competence_areas = coalesce(p_competence_areas, public.creator_profiles.competence_areas),
        organisation = case when p_organisation is null
                            then public.creator_profiles.organisation
                            else v_organisation end,
        website_url = case when p_website_url is null
                           then public.creator_profiles.website_url
                           else v_website_url end,
        linkedin_url = case when p_linkedin_url is null
                            then public.creator_profiles.linkedin_url
                            else v_linkedin_url end,
        updated_at = now()
    returning * into v_profile;

    return v_profile;
end;
$$;

create or replace function public.upsert_my_creator_profile(
    p_display_name text,
    p_slug text default null,
    p_bio_short text default null,
    p_bio_long text default null,
    p_competence_areas text[] default null,
    p_organisation text default null,
    p_website_url text default null,
    p_linkedin_url text default null
) returns public.creator_profiles
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.upsert_my_creator_profile(
        p_display_name, p_slug, p_bio_short, p_bio_long, p_competence_areas,
        p_organisation, p_website_url, p_linkedin_url
    );
$$;

revoke all on function public.upsert_my_creator_profile(
    text, text, text, text, text[], text, text, text
) from public;
grant execute on function public.upsert_my_creator_profile(
    text, text, text, text, text[], text, text, text
) to authenticated;

create or replace function app_private.publish_my_creator_profile()
returns public.creator_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid;
    v_profile public.creator_profiles;
begin
    v_uid := auth.uid();
    if v_uid is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    select * into v_profile from public.creator_profiles where user_id = v_uid;
    if not found then
        raise exception 'Ingen profil att publicera.';
    end if;

    if nullif(trim(coalesce(v_profile.display_name, '')), '') is null
       or nullif(trim(coalesce(v_profile.bio_short, '')), '') is null then
        raise exception 'Fyll i namn och en kort presentation innan du publicerar.';
    end if;

    update public.creator_profiles
       set status = 'published',
           published_at = coalesce(published_at, now()),
           slug_locked = true,
           updated_at = now()
     where user_id = v_uid
     returning * into v_profile;

    return v_profile;
end;
$$;

create or replace function public.publish_my_creator_profile()
returns public.creator_profiles
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.publish_my_creator_profile();
$$;

revoke all on function public.publish_my_creator_profile() from public;
grant execute on function public.publish_my_creator_profile() to authenticated;

create or replace function app_private.unpublish_my_creator_profile()
returns public.creator_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid;
    v_profile public.creator_profiles;
begin
    v_uid := auth.uid();
    if v_uid is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    update public.creator_profiles
       set status = 'draft',
           updated_at = now()
     where user_id = v_uid
     returning * into v_profile;

    if not found then
        raise exception 'Ingen profil att avpublicera.';
    end if;

    return v_profile;
end;
$$;

create or replace function public.unpublish_my_creator_profile()
returns public.creator_profiles
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.unpublish_my_creator_profile();
$$;

revoke all on function public.unpublish_my_creator_profile() from public;
grant execute on function public.unpublish_my_creator_profile() to authenticated;

-- 4. Läs-RPC:er ------------------------------------------------------------

create or replace function public.get_my_creator_profile()
returns setof public.creator_profiles
language sql
stable
security definer
set search_path = ''
as $$
    select * from public.creator_profiles where user_id = auth.uid();
$$;

revoke all on function public.get_my_creator_profile() from public;
grant execute on function public.get_my_creator_profile() to authenticated;

create or replace function public.list_published_creator_profiles()
returns table (
    slug text,
    display_name text,
    bio_short text,
    bio_long text,
    competence_areas text[],
    organisation text,
    website_url text,
    linkedin_url text,
    published_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select slug, display_name, bio_short, bio_long, competence_areas,
           organisation, website_url, linkedin_url, published_at
      from public.creator_profiles
     where status = 'published'
     order by published_at desc;
$$;

revoke all on function public.list_published_creator_profiles() from public;
grant execute on function public.list_published_creator_profiles() to anon, authenticated;

create or replace function public.get_published_creator_profile(p_slug text)
returns table (
    slug text,
    display_name text,
    bio_short text,
    bio_long text,
    competence_areas text[],
    organisation text,
    website_url text,
    linkedin_url text,
    published_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select slug, display_name, bio_short, bio_long, competence_areas,
           organisation, website_url, linkedin_url, published_at
      from public.creator_profiles
     where status = 'published'
       and slug = p_slug;
$$;

revoke all on function public.get_published_creator_profile(text) from public;
grant execute on function public.get_published_creator_profile(text) to anon, authenticated;

-- 5. Admin-RPC:er (gated på platform_owner, tar user-id) -------------------

create or replace function app_private.admin_update_creator_profile_slug(
    p_user_id uuid,
    p_slug text
)
returns public.creator_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_slug text;
    v_profile public.creator_profiles;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan hantera creator-profiler.';
    end if;

    v_slug := nullif(trim(coalesce(p_slug, '')), '');
    if v_slug is null or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
        raise exception 'Ogiltig adress. Använd gemener, siffror och bindestreck.';
    end if;
    if app_private.creator_slug_is_reserved(v_slug) then
        raise exception 'Den adressen är reserverad.';
    end if;

    update public.creator_profiles
       set slug = v_slug,
           updated_at = now()
     where user_id = p_user_id
     returning * into v_profile;

    if not found then
        raise exception 'Ingen profil hittades för den användaren.';
    end if;

    return v_profile;
end;
$$;

create or replace function public.admin_update_creator_profile_slug(
    p_user_id uuid,
    p_slug text
) returns public.creator_profiles
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.admin_update_creator_profile_slug(p_user_id, p_slug);
$$;

revoke all on function public.admin_update_creator_profile_slug(uuid, text) from public;
grant execute on function public.admin_update_creator_profile_slug(uuid, text) to authenticated;

create or replace function app_private.admin_unpublish_creator_profile(p_user_id uuid)
returns public.creator_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_profile public.creator_profiles;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan hantera creator-profiler.';
    end if;

    update public.creator_profiles
       set status = 'draft',
           updated_at = now()
     where user_id = p_user_id
     returning * into v_profile;

    if not found then
        raise exception 'Ingen profil hittades för den användaren.';
    end if;

    return v_profile;
end;
$$;

create or replace function public.admin_unpublish_creator_profile(p_user_id uuid)
returns public.creator_profiles
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select * from app_private.admin_unpublish_creator_profile(p_user_id);
$$;

revoke all on function public.admin_unpublish_creator_profile(uuid) from public;
grant execute on function public.admin_unpublish_creator_profile(uuid) to authenticated;
