-- Redaktionella beslut om creator-inskick: godkänn, begär ändring, avslå.
-- Se docs/superpowers/specs/2026-08-23-creator-review-flow-design.md.
--
-- AI:n har ingen del i dessa funktioner. De kräver en inloggad
-- plattformsägare och läser aldrig creator_submission_screenings.
-- Förgranskningen är rådgivande och får inte kunna påverka utfallet.

-- 1. Proveniens: vilken creator-prompt blev vilken katalogpost ------------
--
-- Behövs för att approve_creator_package ska hitta katalogposterna för
-- utkastets prompts. Att matcha på prompttext skulle gå sönder så fort en
-- prompt redigeras efter godkännande.

alter table public.catalog_prompts
    add column if not exists source_content_item_id uuid references public.content_items(id) on delete set null;

comment on column public.catalog_prompts.source_content_item_id is
    'Det creator-inskickade content_items-id som denna katalogpost skapades från. Null för kurerat redaktionellt innehåll.';

create unique index if not exists catalog_prompts_source_content_item_idx
    on public.catalog_prompts (source_content_item_id)
    where source_content_item_id is not null;

-- 2. Godkänn en prompt ----------------------------------------------------

create or replace function app_private.approve_creator_prompt(
    p_content_item_id uuid,
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
    v_item public.content_items;
    v_creator_profile_id uuid;
    v_prompt_id uuid;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan godkänna creator-inskick.';
    end if;

    if coalesce(trim(p_slug), '') = '' then
        raise exception 'Ange en adress (slug) för katalogposten.';
    end if;

    select * into v_item
      from public.content_items
     where id = p_content_item_id and status = 'review';

    if v_item.id is null then
        raise exception 'Prompten hittades inte eller är inte under granskning.';
    end if;

    if not v_item.creator_consent_shared then
        raise exception 'Prompten saknar creatorns samtycke till publicering och kan inte godkännas.';
    end if;

    if exists (select 1 from public.catalog_prompts where slug = p_slug) then
        raise exception 'Adressen % är redan tagen i katalogen. Ange en annan.', p_slug;
    end if;

    select id into v_creator_profile_id
      from public.creator_profiles
     where user_id = v_item.owner_user_id;

    insert into public.catalog_prompts (
        slug, status, prompt_kind, icon_key, color_theme,
        creator_profile_id, creator_consent_distribution, creator_rights_attested,
        source_content_item_id, created_by, updated_by
    )
    values (
        p_slug, 'draft', 'prompt', p_icon_key, p_color_theme,
        v_creator_profile_id, v_item.creator_consent_distribution, v_item.creator_rights_attested,
        v_item.id, (select auth.uid()), (select auth.uid())
    )
    returning id into v_prompt_id;

    insert into public.catalog_prompt_variants (
        prompt_id, context_key, title, summary, prompt_text, audience_label
    )
    values (
        v_prompt_id, 'generell', v_item.title,
        coalesce(nullif(trim(v_item.summary), ''), v_item.title),
        v_item.content, v_item.audience
    );

    update public.content_items
       set status = 'published',
           review_note = null,
           updated_at = now()
     where id = p_content_item_id;

    return jsonb_build_object(
        'catalog_prompt_id', v_prompt_id,
        'slug', p_slug,
        'status', 'draft',
        'creator_profile_id', v_creator_profile_id
    );
end;
$$;

create or replace function public.approve_creator_prompt(
    p_content_item_id uuid,
    p_slug text,
    p_icon_key text,
    p_color_theme text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.approve_creator_prompt(p_content_item_id, p_slug, p_icon_key, p_color_theme);
$$;

revoke all on function public.approve_creator_prompt(uuid, text, text, text) from public;
grant execute on function public.approve_creator_prompt(uuid, text, text, text) to authenticated;

-- 3. Godkänn ett paket ----------------------------------------------------

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

    -- Varje ingående prompt måste redan ha godkänts till katalogen.
    -- Matchningen går via proveniens, inte via prompttext.
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
        p_slug, 'draft', 'collection', p_icon_key, p_color_theme,
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
        'item_count', v_sort,
        'creator_profile_id', v_creator_profile_id
    );
end;
$$;

create or replace function public.approve_creator_package(
    p_draft_id uuid,
    p_slug text,
    p_icon_key text,
    p_color_theme text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.approve_creator_package(p_draft_id, p_slug, p_icon_key, p_color_theme);
$$;

revoke all on function public.approve_creator_package(uuid, text, text, text) from public;
grant execute on function public.approve_creator_package(uuid, text, text, text) to authenticated;

-- 4. Begär ändring och avslå ---------------------------------------------

create or replace function app_private.set_creator_submission_status(
    p_subject_type text,
    p_subject_id uuid,
    p_note text,
    p_new_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan besluta om creator-inskick.';
    end if;

    if coalesce(trim(p_note), '') = '' then
        raise exception 'Skriv en motivering till creatorn innan du skickar tillbaka eller avslår.';
    end if;

    if p_subject_type = 'prompt' then
        update public.content_items
           set status = p_new_status::public.content_status,
               review_note = p_note,
               updated_at = now()
         where id = p_subject_id and status = 'review'
        returning id into v_id;
    elsif p_subject_type = 'package' then
        update public.creator_package_drafts
           set status = p_new_status,
               review_note = p_note,
               updated_at = now()
         where id = p_subject_id and status = 'review'
        returning id into v_id;
    else
        raise exception 'Okänd typ: %. Ange prompt eller package.', p_subject_type;
    end if;

    if v_id is null then
        raise exception 'Inskicket hittades inte eller är inte under granskning.';
    end if;

    return jsonb_build_object('id', v_id, 'status', p_new_status);
end;
$$;

create or replace function public.request_changes_creator_submission(
    p_subject_type text,
    p_subject_id uuid,
    p_note text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.set_creator_submission_status(p_subject_type, p_subject_id, p_note, 'draft');
$$;

create or replace function public.reject_creator_submission(
    p_subject_type text,
    p_subject_id uuid,
    p_note text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.set_creator_submission_status(p_subject_type, p_subject_id, p_note, 'archived');
$$;

revoke all on function public.request_changes_creator_submission(text, uuid, text) from public;
grant execute on function public.request_changes_creator_submission(text, uuid, text) to authenticated;
revoke all on function public.reject_creator_submission(text, uuid, text) from public;
grant execute on function public.reject_creator_submission(text, uuid, text) to authenticated;
