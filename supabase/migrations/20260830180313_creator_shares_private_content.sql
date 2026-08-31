-- 20260831110000_creator_shares_private_content.sql
-- Generaliserar creator_shares till att omfatta eget opublicerat innehåll
-- (utkast och innehåll under granskning), inte bara publicerat
-- katalog-innehåll. Se
-- docs/superpowers/specs/2026-08-30-connect-my-library-architecture-analysis.md,
-- sektion E och H.
--
-- Två nya subject_type-värden: 'draft_prompt' (pekar på content_items.id,
-- module='kommun') och 'package_draft' (pekar på creator_package_drafts.id).
-- Ägarskapskontrollen för dessa är owner_user_id = auth.uid() direkt --
-- ingen creator_profile_id-koppling behövs eftersom innehållet aldrig
-- passerat granskningen och alltså inte ligger i katalogen än.

alter table public.creator_shares
    drop constraint if exists creator_shares_subject_type_check;

alter table public.creator_shares
    add constraint creator_shares_subject_type_check
      check (subject_type in ('prompt', 'package', 'draft_prompt', 'package_draft'));

-- 1. build_content_payload: två nya grenar --------------------------------

create or replace function app_private.build_content_payload(
    p_subject_type text,
    p_subject_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_payload jsonb;
begin
    if p_subject_type = 'prompt' then
        select jsonb_build_object(
                   'kind', 'prompt',
                   'slug', cp.slug,
                   'title', v.title,
                   'summary', v.summary,
                   'prompt_text', v.prompt_text,
                   'example_input', v.example_input,
                   'audience_label', v.audience_label,
                   'tone_hint', v.tone_hint,
                   'risk_level', v.risk_level,
                   'security_examples', to_jsonb(coalesce(v.security_examples, array[]::text[]))
               )
          into v_payload
          from public.catalog_prompts cp
          join public.catalog_prompt_variants v
            on v.prompt_id = cp.id and v.context_key = 'generell'
         where cp.id = p_subject_id and cp.status = 'published';

    elsif p_subject_type = 'package' then
        select jsonb_build_object(
                   'kind', 'package',
                   'slug', cpkg.slug,
                   'package_type', cpkg.package_type,
                   'title', v.title,
                   'summary', v.summary,
                   'intro_text', v.intro_text,
                   'items', coalesce((
                       select jsonb_agg(jsonb_build_object(
                                  'title', pv.title,
                                  'summary', pv.summary,
                                  'prompt_text', pv.prompt_text
                              ) order by cpi.sort_order)
                         from public.catalog_package_items cpi
                         join public.catalog_prompts p on p.id = cpi.prompt_id
                         join public.catalog_prompt_variants pv
                           on pv.prompt_id = p.id and pv.context_key = 'generell'
                        where cpi.package_id = cpkg.id and p.status = 'published'
                   ), '[]'::jsonb)
               )
          into v_payload
          from public.catalog_packages cpkg
          join public.catalog_package_variants v
            on v.package_id = cpkg.id and v.context_key = 'generell'
         where cpkg.id = p_subject_id and cpkg.status = 'published';

    elsif p_subject_type = 'draft_prompt' then
        select jsonb_build_object(
                   'kind', 'prompt',
                   'slug', ci.slug,
                   'title', ci.title,
                   'summary', ci.summary,
                   'prompt_text', ci.content,
                   'risk_level', ci.risk_level,
                   'security_examples', '[]'::jsonb
               )
          into v_payload
          from public.content_items ci
         where ci.id = p_subject_id and ci.module = 'kommun' and ci.type = 'prompt';

    elsif p_subject_type = 'package_draft' then
        select jsonb_build_object(
                   'kind', 'package',
                   'slug', d.id::text,
                   'package_type', 'collection',
                   'title', d.title,
                   'summary', d.summary,
                   'intro_text', null,
                   'items', coalesce((
                       select jsonb_agg(jsonb_build_object(
                                  'title', ci.title,
                                  'summary', ci.summary,
                                  'prompt_text', ci.content
                              ) order by dpi.position)
                         from public.creator_package_items dpi
                         join public.content_items ci on ci.id = dpi.content_item_id
                        where dpi.draft_id = d.id
                   ), '[]'::jsonb)
               )
          into v_payload
          from public.creator_package_drafts d
         where d.id = p_subject_id;
    end if;

    return v_payload;
end;
$$;

-- 2. create_creator_share: ägarskapskontroll för alla fyra typer ----------

create or replace function app_private.create_creator_share(
    p_subject_type text,
    p_subject_id uuid,
    p_pin_version boolean default false,
    p_expires_at timestamptz default null,
    p_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user uuid := (select auth.uid());
    v_profile_id uuid;
    v_owns boolean;
    v_payload jsonb;
    v_snapshot_id uuid;
    v_token text := encode(extensions.gen_random_bytes(16), 'hex');
    v_share_id uuid;
begin
    if v_user is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    if p_subject_type not in ('prompt', 'package', 'draft_prompt', 'package_draft') then
        raise exception 'Okänd typ: %.', p_subject_type;
    end if;

    select id into v_profile_id from public.creator_profiles where user_id = v_user;
    if v_profile_id is null then
        raise exception 'Du behöver en creator-profil för att kunna dela innehåll.';
    end if;

    if p_subject_type = 'prompt' then
        select exists (
            select 1 from public.catalog_prompts
             where id = p_subject_id and status = 'published' and creator_profile_id = v_profile_id
        ) into v_owns;
    elsif p_subject_type = 'package' then
        select exists (
            select 1 from public.catalog_packages
             where id = p_subject_id and status = 'published' and creator_profile_id = v_profile_id
        ) into v_owns;
    elsif p_subject_type = 'draft_prompt' then
        select exists (
            select 1 from public.content_items
             where id = p_subject_id and owner_user_id = v_user and module = 'kommun' and type = 'prompt'
        ) into v_owns;
    else -- package_draft
        select exists (
            select 1 from public.creator_package_drafts
             where id = p_subject_id and owner_user_id = v_user
        ) into v_owns;
    end if;

    if not v_owns then
        raise exception 'Du kan bara dela ditt eget innehåll.';
    end if;

    if coalesce(p_pin_version, false) then
        v_payload := app_private.build_content_payload(p_subject_type, p_subject_id);
        if v_payload is null then
            raise exception 'Innehållet kunde inte läsas för låsning.';
        end if;
        insert into public.content_snapshots (subject_type, subject_id, payload)
        values (p_subject_type, p_subject_id, v_payload)
        returning id into v_snapshot_id;
    end if;

    insert into public.creator_shares (
        owner_user_id, subject_type, subject_id, token, snapshot_id, label, expires_at
    )
    values (
        v_user, p_subject_type, p_subject_id, v_token, v_snapshot_id,
        nullif(trim(coalesce(p_label, '')), ''), p_expires_at
    )
    returning id into v_share_id;

    return jsonb_build_object('id', v_share_id, 'token', v_token, 'pinned', v_snapshot_id is not null);
end;
$$;

-- 3. get_shared_content: nytt reviewed-fält --------------------------------

create or replace function public.get_shared_content(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_share public.creator_shares;
    v_payload jsonb;
    v_creator jsonb;
begin
    select * into v_share from public.creator_shares where token = p_token;

    if v_share.id is null then
        return jsonb_build_object('state', 'not_found');
    end if;

    if v_share.revoked_at is not null
       or (v_share.expires_at is not null and v_share.expires_at <= now()) then
        return jsonb_build_object('state', 'expired');
    end if;

    if v_share.snapshot_id is not null then
        select s.payload into v_payload
          from public.content_snapshots s where s.id = v_share.snapshot_id;
    else
        v_payload := app_private.build_content_payload(v_share.subject_type, v_share.subject_id);
    end if;

    if v_payload is null then
        return jsonb_build_object('state', 'expired');
    end if;

    select jsonb_build_object('display_name', prof.display_name, 'slug', prof.slug)
      into v_creator
      from public.creator_profiles prof
     where prof.user_id = v_share.owner_user_id
       and prof.status = 'published';

    insert into public.creator_share_events (share_id, event_type, occurred_on, event_count)
    values (v_share.id, 'view', current_date, 1)
    on conflict (share_id, event_type, occurred_on)
    do update set event_count = public.creator_share_events.event_count + 1;

    return jsonb_build_object(
        'state', 'ok',
        'pinned', v_share.snapshot_id is not null,
        'reviewed', v_share.subject_type in ('prompt', 'package'),
        'expires_at', v_share.expires_at,
        'creator', v_creator,
        'content', v_payload
    );
end;
$$;

-- 4. list_my_shareable_content ----------------------------------------------

create or replace function public.list_my_shareable_content()
returns table (
    kind text,
    subject_id uuid,
    title text,
    status_label text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_user uuid := (select auth.uid());
    v_profile_id uuid;
begin
    if v_user is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    select id into v_profile_id from public.creator_profiles where user_id = v_user;

    return query
    select 'prompt'::text, cp.id, v.title, 'Publicerad'::text
      from public.catalog_prompts cp
      join public.catalog_prompt_variants v
        on v.prompt_id = cp.id and v.context_key = 'generell'
     where cp.status = 'published' and cp.creator_profile_id = v_profile_id

    union all

    select 'package'::text, cpkg.id, v.title, 'Publicerad'::text
      from public.catalog_packages cpkg
      join public.catalog_package_variants v
        on v.package_id = cpkg.id and v.context_key = 'generell'
     where cpkg.status = 'published' and cpkg.creator_profile_id = v_profile_id

    union all

    select 'draft_prompt'::text, ci.id, ci.title,
           case ci.status when 'review' then 'Under granskning' else 'Utkast' end
      from public.content_items ci
     where ci.owner_user_id = v_user
       and ci.type = 'prompt'
       and ci.module = 'kommun'
       and ci.status in ('draft', 'review')

    union all

    select 'package_draft'::text, d.id, d.title,
           case d.status when 'review' then 'Under granskning' else 'Utkast' end
      from public.creator_package_drafts d
     where d.owner_user_id = v_user
       and d.status in ('draft', 'review');
end;
$$;

revoke all on function public.list_my_shareable_content() from public;
grant execute on function public.list_my_shareable_content() to authenticated;
