-- Pakettyp för creator-utkast: samling eller workflow.
--
-- catalog_packages har haft package_type sedan katalogkärnan, men
-- creator_package_drafts har aldrig haft någon typ. Följden syns i
-- approve_creator_package, som hårdkodar 'collection': en creator kunde
-- bygga ett workflow och få det publicerat som en samling utan att någon
-- märkte det.
--
-- Samma check-villkor som catalog_packages, så att typen kan kopieras rakt
-- av vid godkännande.

alter table public.creator_package_drafts
    add column if not exists package_type text not null default 'collection'
        check (package_type in ('collection', 'workflow'));

comment on column public.creator_package_drafts.package_type is
    'collection = mallar som hör ihop, användaren väljer själv. workflow = steg som körs i ordning. Kopieras till catalog_packages vid godkännande.';

-- 1. Skapa och redigera med typ -------------------------------------------
--
-- Kroppen är originalets med typen tillagd. Notera att typen bara får
-- ändras medan utkastet är i 'draft' — samma villkor som titel och
-- sammanfattning redan har.

drop function if exists public.upsert_creator_package_draft(uuid, text, text);
drop function if exists app_private.upsert_creator_package_draft(uuid, text, text);

create or replace function app_private.upsert_creator_package_draft(
    p_draft_id uuid,
    p_title text,
    p_summary text,
    p_package_type text default 'collection'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
    v_type text := coalesce(nullif(trim(coalesce(p_package_type, '')), ''), 'collection');
begin
    if trim(coalesce(p_title, '')) = '' then
        raise exception 'Paketet behöver en titel.';
    end if;

    if v_type not in ('collection', 'workflow') then
        raise exception 'Okänd pakettyp: %. Ange collection eller workflow.', v_type;
    end if;

    if p_draft_id is null then
        insert into public.creator_package_drafts (owner_user_id, title, summary, package_type)
        values ((select auth.uid()), trim(p_title), nullif(trim(coalesce(p_summary, '')), ''), v_type)
        returning id into v_id;
    else
        update public.creator_package_drafts
           set title = trim(p_title),
               summary = nullif(trim(coalesce(p_summary, '')), ''),
               package_type = v_type,
               updated_at = now()
         where id = p_draft_id
           and owner_user_id = (select auth.uid())
           and status = 'draft'
        returning id into v_id;

        if v_id is null then
            raise exception 'Paketet hittades inte, tillhör inte dig, eller kan inte redigeras i sitt nuvarande läge.';
        end if;
    end if;

    return jsonb_build_object('id', v_id, 'package_type', v_type);
end;
$$;

create or replace function public.upsert_creator_package_draft(
    p_draft_id uuid,
    p_title text,
    p_summary text,
    p_package_type text default 'collection'
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.upsert_creator_package_draft(p_draft_id, p_title, p_summary, p_package_type);
$$;

revoke all on function public.upsert_creator_package_draft(uuid, text, text, text) from public;
grant execute on function public.upsert_creator_package_draft(uuid, text, text, text) to authenticated;

-- 2. Listan måste returnera typen, annars kan vyn inte visa den ----------

drop function if exists public.list_my_creator_package_drafts();

create or replace function public.list_my_creator_package_drafts()
returns table (
    id uuid,
    title text,
    summary text,
    package_type text,
    status text,
    item_count integer,
    review_note text,
    updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select d.id, d.title, d.summary, d.package_type, d.status,
           (select count(*)::integer from public.creator_package_items i where i.draft_id = d.id),
           d.review_note,
           d.updated_at
      from public.creator_package_drafts d
     where d.owner_user_id = (select auth.uid())
     order by d.updated_at desc;
$$;

revoke all on function public.list_my_creator_package_drafts() from public;
grant execute on function public.list_my_creator_package_drafts() to authenticated;

-- 3. Godkännandet ska respektera creatorns val --------------------------
--
-- Enda ändringen mot 20260823093000 är att package_type hämtas från
-- utkastet i stället för att hårdkodas till 'collection'.

create or replace function app_private.approve_creator_package(
    p_draft_id uuid,
    p_slug text,
    p_icon_key text,
    p_color_theme text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_draft public.creator_package_drafts;
    v_creator_profile_id uuid;
    v_package_id uuid;
    v_missing text;
    v_item record;
    v_sort integer := 0;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan godkänna creator-inskick.';
    end if;

    if coalesce(trim(p_slug), '') = '' then
        raise exception 'Ange en adress (slug) för katalogposten.';
    end if;

    select * into v_draft
      from public.creator_package_drafts
     where id = p_draft_id and status = 'review';

    if v_draft.id is null then
        raise exception 'Paket-utkastet hittades inte eller är inte under granskning.';
    end if;

    if exists (select 1 from public.catalog_packages where slug = p_slug) then
        raise exception 'Adressen % är redan tagen i katalogen. Ange en annan.', p_slug;
    end if;

    select string_agg(ci.title, ', ' order by i.position) into v_missing
      from public.creator_package_items i
      join public.content_items ci on ci.id = i.content_item_id
     where i.draft_id = p_draft_id
       and not exists (
           select 1 from public.catalog_prompts cp
            where cp.source_content_item_id = ci.id
       );

    if v_missing is not null then
        raise exception 'Dessa prompts saknar godkänd katalogpost och måste godkännas först: %', v_missing;
    end if;

    select id into v_creator_profile_id
      from public.creator_profiles
     where user_id = v_draft.owner_user_id;

    insert into public.catalog_packages (
        slug, status, package_type, icon_key, color_theme,
        creator_profile_id, creator_consent_distribution, creator_rights_attested,
        created_by, updated_by
    )
    values (
        p_slug, 'draft', v_draft.package_type, p_icon_key, p_color_theme,
        v_creator_profile_id, v_draft.creator_consent_distribution, v_draft.creator_rights_attested,
        (select auth.uid()), (select auth.uid())
    )
    returning id into v_package_id;

    insert into public.catalog_package_variants (package_id, context_key, title, summary)
    values (
        v_package_id, 'generell', v_draft.title,
        coalesce(nullif(trim(v_draft.summary), ''), v_draft.title)
    );

    for v_item in
        select cp.id as prompt_id
          from public.creator_package_items i
          join public.catalog_prompts cp on cp.source_content_item_id = i.content_item_id
         where i.draft_id = p_draft_id
         order by i.position
    loop
        insert into public.catalog_package_items (package_id, prompt_id, sort_order)
        values (v_package_id, v_item.prompt_id, v_sort)
        on conflict (package_id, prompt_id) do nothing;
        v_sort := v_sort + 1;
    end loop;

    update public.creator_package_drafts
       set status = 'published',
           review_note = null,
           updated_at = now()
     where id = p_draft_id;

    return jsonb_build_object(
        'catalog_package_id', v_package_id,
        'slug', p_slug,
        'status', 'draft',
        'package_type', v_draft.package_type,
        'item_count', v_sort,
        'creator_profile_id', v_creator_profile_id
    );
end;
$$;
