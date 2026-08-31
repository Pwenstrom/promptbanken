-- Frikopplar frivilliga Open-inskick från användarens privata original.
-- Delnings-snapshots och den publika Open-katalogens läsvägar ändras inte.

alter table public.content_snapshots
    add column if not exists purpose text not null default 'share'
        check (purpose in ('share', 'open_submission')),
    add column if not exists owner_user_id uuid references auth.users(id) on delete set null,
    add column if not exists review_case_id uuid,
    add column if not exists revision_no integer,
    add column if not exists submission_state text
        check (submission_state in ('review', 'published', 'changes_requested', 'rejected', 'withdrawn')),
    add column if not exists review_note text,
    add column if not exists catalog_subject_id uuid,
    add column if not exists consent_shared boolean,
    add column if not exists consent_reusable boolean,
    add column if not exists consent_distribution boolean,
    add column if not exists rights_attested boolean;

alter table public.content_snapshots
    add constraint content_snapshots_open_submission_fields_check check (
        purpose = 'share' or (
            owner_user_id is not null and review_case_id is not null
            and revision_no > 0 and submission_state is not null
            and consent_shared is not null and consent_distribution is not null
            and rights_attested is not null
        )
    );

create unique index if not exists content_snapshots_open_submission_revision_idx
    on public.content_snapshots (review_case_id, revision_no)
    where purpose = 'open_submission';
create index if not exists content_snapshots_open_submission_owner_idx
    on public.content_snapshots (owner_user_id, subject_type, subject_id, created_at desc)
    where purpose = 'open_submission';
create unique index if not exists content_snapshots_one_active_review_idx
    on public.content_snapshots (owner_user_id, subject_type, subject_id)
    where purpose = 'open_submission' and submission_state = 'review';

comment on column public.content_snapshots.purpose is
    'share = privat versionslåsning. open_submission = immutable granskningsrevision för frivillig publicering i Open.';

create or replace function app_private.protect_open_submission_snapshot()
returns trigger language plpgsql set search_path = '' as $$
begin
    if old.purpose = 'open_submission' and (
        new.purpose is distinct from old.purpose
        or new.subject_type is distinct from old.subject_type
        or new.subject_id is distinct from old.subject_id
        or new.payload is distinct from old.payload
        or new.owner_user_id is distinct from old.owner_user_id
        or new.review_case_id is distinct from old.review_case_id
        or new.revision_no is distinct from old.revision_no
        or new.consent_shared is distinct from old.consent_shared
        or new.consent_reusable is distinct from old.consent_reusable
        or new.consent_distribution is distinct from old.consent_distribution
        or new.rights_attested is distinct from old.rights_attested
    ) then
        raise exception 'Ett inskickat granskningsunderlag kan inte ändras.';
    end if;
    return new;
end;
$$;
drop trigger if exists protect_open_submission_snapshot on public.content_snapshots;
create trigger protect_open_submission_snapshot before update on public.content_snapshots
for each row execute function app_private.protect_open_submission_snapshot();

create or replace function app_private.build_open_submission_payload(
    p_subject_type text, p_subject_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_payload jsonb;
begin
    if p_subject_type = 'draft_prompt' then
        select jsonb_build_object(
            'kind', 'prompt', 'source_content_item_id', ci.id, 'slug', ci.slug,
            'title', ci.title, 'summary', ci.summary, 'prompt_text', ci.content,
            'category', ci.category, 'audience_label', ci.audience,
            'risk_level', ci.risk_level, 'items', '[]'::jsonb
        ) into v_payload
        from public.content_items ci
        where ci.id = p_subject_id and ci.owner_user_id = (select auth.uid())
          and ci.module = 'kommun' and ci.type = 'prompt';
    elsif p_subject_type = 'package_draft' then
        select jsonb_build_object(
            'kind', 'package', 'source_package_draft_id', d.id,
            'slug', d.id::text, 'package_type', d.package_type,
            'title', d.title, 'summary', d.summary,
            'items', coalesce((
                select jsonb_agg(jsonb_build_object(
                    'content_item_id', ci.id, 'title', ci.title,
                    'summary', ci.summary, 'prompt_text', ci.content,
                    'content', ci.content,
                    'catalog_prompt_id', coalesce(ci.library_ref_catalog_prompt_id, cp.id)
                ) order by dpi.position)
                from public.creator_package_items dpi
                join public.content_items ci on ci.id = dpi.content_item_id
                left join public.catalog_prompts cp on cp.source_content_item_id = ci.id
                where dpi.draft_id = d.id
            ), '[]'::jsonb)
        ) into v_payload
        from public.creator_package_drafts d
        where d.id = p_subject_id and d.owner_user_id = (select auth.uid());
    else
        raise exception 'Okänd typ: %. Ange draft_prompt eller package_draft.', p_subject_type;
    end if;
    return v_payload;
end;
$$;
revoke all on function app_private.build_open_submission_payload(text, uuid) from public;

create or replace function app_private.submit_creator_open_submission(
    p_subject_type text, p_subject_id uuid, p_consent_shared boolean,
    p_consent_reusable boolean, p_consent_distribution boolean,
    p_rights_attested boolean
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    v_user uuid := (select auth.uid());
    v_payload jsonb; v_case_id uuid; v_revision integer;
    v_snapshot_id uuid; v_previous_state text;
begin
    if v_user is null then raise exception 'Du måste vara inloggad.'; end if;
    if coalesce(p_consent_shared, false) is not true then
        raise exception 'Du måste godkänna publicering i Promptbanken Open innan innehållet kan skickas in.';
    end if;
    if coalesce(p_consent_distribution, false) and not coalesce(p_rights_attested, false) then
        raise exception 'För distribution via Open/MCP måste du intyga att du har rätt att sprida innehållet.';
    end if;

    perform pg_advisory_xact_lock(hashtext(v_user::text || ':' || p_subject_type || ':' || p_subject_id::text));
    if exists (select 1 from public.content_snapshots where purpose = 'open_submission'
        and owner_user_id = v_user and subject_type = p_subject_type
        and subject_id = p_subject_id and submission_state = 'review') then
        raise exception 'Det finns redan en version under granskning.';
    end if;

    v_payload := app_private.build_open_submission_payload(p_subject_type, p_subject_id);
    if v_payload is null then raise exception 'Innehållet hittades inte eller tillhör inte dig.'; end if;
    if p_subject_type = 'package_draft' and jsonb_array_length(v_payload->'items') = 0 then
        raise exception 'Paketet behöver minst en prompt innan det kan skickas in.';
    end if;

    select review_case_id, revision_no, submission_state
      into v_case_id, v_revision, v_previous_state
      from public.content_snapshots
     where purpose = 'open_submission' and owner_user_id = v_user
       and subject_type = p_subject_type and subject_id = p_subject_id
     order by created_at desc, revision_no desc limit 1;
    if v_previous_state = 'changes_requested' then
        v_revision := v_revision + 1;
    else
        v_case_id := gen_random_uuid(); v_revision := 1;
    end if;

    insert into public.content_snapshots (
        subject_type, subject_id, payload, purpose, owner_user_id,
        review_case_id, revision_no, submission_state, consent_shared,
        consent_reusable, consent_distribution, rights_attested
    ) values (
        p_subject_type, p_subject_id, v_payload, 'open_submission', v_user,
        v_case_id, v_revision, 'review', true, coalesce(p_consent_reusable, false),
        coalesce(p_consent_distribution, false), coalesce(p_rights_attested, false)
    ) returning id into v_snapshot_id;

    return jsonb_build_object('id', v_snapshot_id, 'submission_id', v_snapshot_id,
        'subject_id', p_subject_id, 'review_case_id', v_case_id,
        'revision', v_revision, 'status', 'review');
end;
$$;

create or replace function public.submit_creator_open_submission(
    p_subject_type text, p_subject_id uuid, p_consent_shared boolean,
    p_consent_reusable boolean default false,
    p_consent_distribution boolean default false,
    p_rights_attested boolean default false
)
returns jsonb language sql security invoker set search_path = '' as $$
    select app_private.submit_creator_open_submission(p_subject_type, p_subject_id,
        p_consent_shared, p_consent_reusable, p_consent_distribution, p_rights_attested);
$$;
revoke all on function public.submit_creator_open_submission(text, uuid, boolean, boolean, boolean, boolean) from public;
grant execute on function public.submit_creator_open_submission(text, uuid, boolean, boolean, boolean, boolean) to authenticated;

-- Befintliga webb-anrop behåller sina signaturer men skapar nu snapshots.
create or replace function app_private.submit_creator_prompt(
    p_content_item_id uuid, p_consent_shared boolean, p_consent_reusable boolean,
    p_consent_distribution boolean default false, p_rights_attested boolean default false
)
returns jsonb language sql security definer set search_path = '' as $$
    select app_private.submit_creator_open_submission('draft_prompt', p_content_item_id,
        p_consent_shared, p_consent_reusable, p_consent_distribution, p_rights_attested);
$$;
create or replace function app_private.submit_creator_package_draft(
    p_draft_id uuid, p_consent_distribution boolean default false,
    p_rights_attested boolean default false
)
returns jsonb language sql security definer set search_path = '' as $$
    select app_private.submit_creator_open_submission('package_draft', p_draft_id,
        true, false, p_consent_distribution, p_rights_attested);
$$;

create or replace function app_private.withdraw_creator_open_submission(p_submission_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
    update public.content_snapshots set submission_state = 'withdrawn'
     where id = p_submission_id and purpose = 'open_submission'
       and owner_user_id = (select auth.uid()) and submission_state = 'review'
    returning id into v_id;
    if v_id is null then
        raise exception 'Inskicket hittades inte, tillhör inte dig, eller är inte under granskning.';
    end if;
    return jsonb_build_object('id', v_id, 'status', 'withdrawn');
end;
$$;
create or replace function public.withdraw_creator_open_submission(p_submission_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
    select app_private.withdraw_creator_open_submission(p_submission_id);
$$;
revoke all on function public.withdraw_creator_open_submission(uuid) from public;
grant execute on function public.withdraw_creator_open_submission(uuid) to authenticated;

create or replace function app_private.withdraw_creator_prompt(p_content_item_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
    select id into v_id from public.content_snapshots where purpose = 'open_submission'
      and owner_user_id = (select auth.uid()) and subject_type = 'draft_prompt'
      and subject_id = p_content_item_id and submission_state = 'review'
      order by created_at desc limit 1;
    return app_private.withdraw_creator_open_submission(v_id);
end;
$$;
create or replace function app_private.withdraw_creator_package_draft(p_draft_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
    select id into v_id from public.content_snapshots where purpose = 'open_submission'
      and owner_user_id = (select auth.uid()) and subject_type = 'package_draft'
      and subject_id = p_draft_id and submission_state = 'review'
      order by created_at desc limit 1;
    return app_private.withdraw_creator_open_submission(v_id);
end;
$$;

create or replace function public.list_my_library_items()
returns table (
    kind text, subject_id uuid, title text, summary text, access_label text,
    open_submission_state text, review_note text, catalog_subject_id uuid,
    updated_at timestamptz
)
language sql stable security definer set search_path = '' as $$
    select 'prompt', ci.id, ci.title, ci.summary,
      case when exists (select 1 from public.creator_shares sh
        where sh.owner_user_id = (select auth.uid()) and sh.subject_type = 'draft_prompt'
          and sh.subject_id = ci.id and sh.revoked_at is null
          and (sh.expires_at is null or sh.expires_at > now())) then 'shared' else 'private' end,
      latest.submission_state, latest.review_note, latest.catalog_subject_id, ci.updated_at
    from public.content_items ci
    left join lateral (select s.submission_state, s.review_note, s.catalog_subject_id
      from public.content_snapshots s where s.purpose = 'open_submission'
        and s.owner_user_id = (select auth.uid()) and s.subject_type = 'draft_prompt'
        and s.subject_id = ci.id order by s.created_at desc, s.revision_no desc limit 1) latest on true
    where ci.owner_user_id = (select auth.uid()) and ci.type = 'prompt' and ci.module = 'kommun'
    union all
    select 'package', d.id, d.title, d.summary,
      case when exists (select 1 from public.creator_shares sh
        where sh.owner_user_id = (select auth.uid()) and sh.subject_type = 'package_draft'
          and sh.subject_id = d.id and sh.revoked_at is null
          and (sh.expires_at is null or sh.expires_at > now())) then 'shared' else 'private' end,
      latest.submission_state, latest.review_note, latest.catalog_subject_id, d.updated_at
    from public.creator_package_drafts d
    left join lateral (select s.submission_state, s.review_note, s.catalog_subject_id
      from public.content_snapshots s where s.purpose = 'open_submission'
        and s.owner_user_id = (select auth.uid()) and s.subject_type = 'package_draft'
        and s.subject_id = d.id order by s.created_at desc, s.revision_no desc limit 1) latest on true
    where d.owner_user_id = (select auth.uid()) order by 9 desc;
$$;
revoke all on function public.list_my_library_items() from public;
grant execute on function public.list_my_library_items() to authenticated;

-- Redaktionens befintliga UI/RPC-kontrakt behålls, men subject_id är nu
-- snapshotens id. Det gör även den befintliga screening-funktionen
-- snapshotbaserad utan att ändra dess HTTP-kontrakt.
create or replace function app_private.list_creator_submissions()
returns table (
    subject_type text, subject_id uuid, title text, summary text,
    creator_profile_id uuid, creator_display_name text, creator_slug text,
    consent_shared boolean, consent_distribution boolean,
    rights_attested boolean, item_count integer, latest_verdict text,
    latest_screened_at timestamptz, updated_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa creator-inskick.';
    end if;
    return query
    select case s.subject_type when 'draft_prompt' then 'prompt' else 'package' end,
      s.id, s.payload->>'title', s.payload->>'summary', prof.id,
      prof.display_name, prof.slug, s.consent_shared, s.consent_distribution,
      s.rights_attested,
      case when s.subject_type = 'package_draft'
           then jsonb_array_length(coalesce(s.payload->'items', '[]'::jsonb)) else null end,
      screening.verdict, screening.created_at, s.created_at
    from public.content_snapshots s
    left join public.creator_profiles prof on prof.user_id = s.owner_user_id
    left join lateral (
      select scr.verdict, scr.created_at from public.creator_submission_screenings scr
       where scr.subject_type = case s.subject_type when 'draft_prompt' then 'prompt' else 'package' end
         and scr.subject_id = s.id order by scr.created_at desc limit 1
    ) screening on true
    where s.purpose = 'open_submission' and s.submission_state = 'review'
    order by s.created_at desc;
end;
$$;

create or replace function app_private.get_creator_submission(
    p_subject_type text, p_subject_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_snapshot public.content_snapshots; v_result jsonb;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa creator-inskick.';
    end if;
    select * into v_snapshot from public.content_snapshots
     where id = p_subject_id and purpose = 'open_submission'
       and submission_state = 'review'
       and subject_type = case p_subject_type when 'prompt' then 'draft_prompt' else 'package_draft' end;
    if v_snapshot.id is null then raise exception 'Inskicket hittades inte eller är inte under granskning.'; end if;
    select v_snapshot.payload || jsonb_build_object(
      'subject_type', p_subject_type, 'subject_id', v_snapshot.id,
      'source_subject_id', v_snapshot.subject_id,
      'consent_shared', v_snapshot.consent_shared,
      'consent_reusable', v_snapshot.consent_reusable,
      'consent_distribution', v_snapshot.consent_distribution,
      'rights_attested', v_snapshot.rights_attested,
      'creator_display_name', prof.display_name, 'creator_slug', prof.slug,
      'content', v_snapshot.payload->>'prompt_text',
      'screenings', coalesce((select jsonb_agg(jsonb_build_object(
        'verdict', scr.verdict, 'findings', scr.findings,
        'suggested_feedback', scr.suggested_feedback,
        'rules_version', scr.rules_version, 'model', scr.model,
        'created_at', scr.created_at) order by scr.created_at desc)
        from public.creator_submission_screenings scr
        where scr.subject_type = p_subject_type and scr.subject_id = v_snapshot.id), '[]'::jsonb)
    ) into v_result
    from public.creator_profiles prof where prof.user_id = v_snapshot.owner_user_id;
    return coalesce(v_result, v_snapshot.payload || jsonb_build_object(
      'subject_type', p_subject_type, 'subject_id', v_snapshot.id,
      'content', v_snapshot.payload->>'prompt_text', 'screenings', '[]'::jsonb));
end;
$$;

alter table public.catalog_packages
    add column if not exists source_creator_package_draft_id uuid
        references public.creator_package_drafts(id) on delete set null;
create unique index if not exists catalog_packages_source_creator_draft_idx
    on public.catalog_packages (source_creator_package_draft_id)
    where source_creator_package_draft_id is not null;

create or replace function app_private.approve_creator_prompt(
    p_content_item_id uuid, p_slug text, p_icon_key text, p_color_theme text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.content_snapshots; v_profile uuid; v_prompt uuid;
begin
    if not app_private.current_user_is_platform_owner() then
      raise exception 'Endast plattformsägare kan godkänna creator-inskick.';
    end if;
    if coalesce(trim(p_slug), '') = '' then raise exception 'Ange en adress (slug) för katalogposten.'; end if;
    select * into v_s from public.content_snapshots where id = p_content_item_id
      and purpose = 'open_submission' and subject_type = 'draft_prompt' and submission_state = 'review' for update;
    if v_s.id is null then raise exception 'Prompten hittades inte eller är inte under granskning.'; end if;
    select id into v_profile from public.creator_profiles where user_id = v_s.owner_user_id;
    select id into v_prompt from public.catalog_prompts where source_content_item_id = v_s.subject_id;
    if v_prompt is null then
      if exists(select 1 from public.catalog_prompts where slug = p_slug) then
        raise exception 'Adressen % är redan tagen i katalogen. Ange en annan.', p_slug;
      end if;
      insert into public.catalog_prompts(slug,status,prompt_kind,icon_key,color_theme,
        creator_profile_id,creator_consent_distribution,creator_rights_attested,
        source_content_item_id,created_by,updated_by)
      values(p_slug,'draft','prompt',p_icon_key,p_color_theme,v_profile,
        v_s.consent_distribution,v_s.rights_attested,v_s.subject_id,(select auth.uid()),(select auth.uid()))
      returning id into v_prompt;
    else
      update public.catalog_prompts set slug=p_slug,status='draft',icon_key=p_icon_key,
        color_theme=p_color_theme,creator_consent_distribution=v_s.consent_distribution,
        creator_rights_attested=v_s.rights_attested,updated_by=(select auth.uid()) where id=v_prompt;
    end if;
    insert into public.catalog_prompt_variants(prompt_id,context_key,title,summary,prompt_text,audience_label)
    values(v_prompt,'generell',v_s.payload->>'title',coalesce(nullif(trim(v_s.payload->>'summary'),''),v_s.payload->>'title'),
      v_s.payload->>'prompt_text',v_s.payload->>'audience_label')
    on conflict(prompt_id,context_key) do update set title=excluded.title,summary=excluded.summary,
      prompt_text=excluded.prompt_text,audience_label=excluded.audience_label;
    update public.content_snapshots set submission_state='published',review_note=null,
      catalog_subject_id=v_prompt where id=v_s.id;
    return jsonb_build_object('catalog_prompt_id',v_prompt,'slug',p_slug,'status','draft','creator_profile_id',v_profile);
end;
$$;

create or replace function app_private.approve_creator_package(
    p_draft_id uuid, p_slug text, p_icon_key text, p_color_theme text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.content_snapshots; v_profile uuid; v_package uuid; v_item jsonb; v_sort int:=0; v_prompt uuid;
begin
    if not app_private.current_user_is_platform_owner() then
      raise exception 'Endast plattformsägare kan godkänna creator-inskick.';
    end if;
    if coalesce(trim(p_slug), '') = '' then raise exception 'Ange en adress (slug) för katalogposten.'; end if;
    select * into v_s from public.content_snapshots where id=p_draft_id
      and purpose='open_submission' and subject_type='package_draft' and submission_state='review' for update;
    if v_s.id is null then raise exception 'Paketet hittades inte eller är inte under granskning.'; end if;
    select id into v_profile from public.creator_profiles where user_id=v_s.owner_user_id;
    select id into v_package from public.catalog_packages where source_creator_package_draft_id=v_s.subject_id;
    if v_package is null then
      if exists(select 1 from public.catalog_packages where slug=p_slug) then
        raise exception 'Adressen % är redan tagen i katalogen. Ange en annan.',p_slug;
      end if;
      insert into public.catalog_packages(slug,status,package_type,icon_key,color_theme,
        creator_profile_id,creator_consent_distribution,creator_rights_attested,
        source_creator_package_draft_id,created_by,updated_by)
      values(p_slug,'draft',coalesce(v_s.payload->>'package_type','collection'),p_icon_key,p_color_theme,
        v_profile,v_s.consent_distribution,v_s.rights_attested,v_s.subject_id,(select auth.uid()),(select auth.uid()))
      returning id into v_package;
    else
      update public.catalog_packages set slug=p_slug,status='draft',icon_key=p_icon_key,color_theme=p_color_theme,
        creator_consent_distribution=v_s.consent_distribution,creator_rights_attested=v_s.rights_attested,
        updated_by=(select auth.uid()) where id=v_package;
      delete from public.catalog_package_items where package_id=v_package;
    end if;
    insert into public.catalog_package_variants(package_id,context_key,title,summary)
    values(v_package,'generell',v_s.payload->>'title',coalesce(nullif(trim(v_s.payload->>'summary'),''),v_s.payload->>'title'))
    on conflict(package_id,context_key) do update set title=excluded.title,summary=excluded.summary;
    for v_item in select value from jsonb_array_elements(coalesce(v_s.payload->'items','[]'::jsonb)) loop
      v_prompt := nullif(v_item->>'catalog_prompt_id','')::uuid;
      if v_prompt is null then raise exception 'Prompten % saknar godkänd katalogpost.',v_item->>'title'; end if;
      insert into public.catalog_package_items(package_id,prompt_id,sort_order)
      values(v_package,v_prompt,v_sort) on conflict(package_id,prompt_id) do nothing;
      v_sort:=v_sort+1;
    end loop;
    update public.content_snapshots set submission_state='published',review_note=null,
      catalog_subject_id=v_package where id=v_s.id;
    return jsonb_build_object('catalog_package_id',v_package,'slug',p_slug,'status','draft',
      'item_count',v_sort,'creator_profile_id',v_profile);
end;
$$;

create or replace function app_private.set_creator_submission_status(
    p_subject_type text, p_subject_id uuid, p_note text, p_new_status text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_state text;
begin
    if not app_private.current_user_is_platform_owner() then
      raise exception 'Endast plattformsägare kan besluta om creator-inskick.';
    end if;
    if coalesce(trim(p_note),'')='' then raise exception 'Skriv en motivering till creatorn.'; end if;
    v_state := case p_new_status when 'draft' then 'changes_requested' when 'archived' then 'rejected' else p_new_status end;
    update public.content_snapshots set submission_state=v_state,review_note=trim(p_note)
      where id=p_subject_id and purpose='open_submission' and submission_state='review'
        and subject_type=case p_subject_type when 'prompt' then 'draft_prompt' else 'package_draft' end
      returning id into v_id;
    if v_id is null then raise exception 'Inskicket hittades inte eller är inte under granskning.'; end if;
    return jsonb_build_object('id',v_id,'status',v_state);
end;
$$;

create or replace function app_private.get_my_creator_overview()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_needs jsonb; v_recent jsonb; v_stats jsonb; v_checklist jsonb;
begin
  if v_user is null then raise exception 'Du måste vara inloggad.'; end if;
  select coalesce(jsonb_agg(row_to_json(x) order by x.updated_at desc),'[]'::jsonb) into v_needs
  from (select case s.subject_type when 'draft_prompt' then 'prompt' else 'package' end kind,
    s.subject_id id,s.payload->>'title' title,s.submission_state status,s.review_note,s.created_at updated_at
    from public.content_snapshots s where s.purpose='open_submission' and s.owner_user_id=v_user
      and s.submission_state in ('changes_requested','rejected')
      and s.id=(select s2.id from public.content_snapshots s2 where s2.review_case_id=s.review_case_id
        order by s2.revision_no desc limit 1)) x;
  select coalesce(jsonb_agg(row_to_json(x) order by x.updated_at desc),'[]'::jsonb) into v_recent
  from (select 'prompt' kind,ci.id,ci.title,'draft' status,ci.updated_at from public.content_items ci
    where ci.owner_user_id=v_user and ci.type='prompt' and ci.module='kommun'
    union all select 'package',d.id,d.title,'draft',d.updated_at from public.creator_package_drafts d
    where d.owner_user_id=v_user order by 5 desc limit 5) x;
  select jsonb_build_object(
    'published_prompts',(select count(*) from public.content_snapshots where purpose='open_submission' and owner_user_id=v_user and subject_type='draft_prompt' and submission_state='published'),
    'published_packages',(select count(*) from public.content_snapshots where purpose='open_submission' and owner_user_id=v_user and subject_type='package_draft' and submission_state='published'),
    'in_review',(select count(*) from public.content_snapshots where purpose='open_submission' and owner_user_id=v_user and submission_state='review'),
    'drafts',(select count(*) from public.content_items where owner_user_id=v_user and type='prompt' and module='kommun')+
      (select count(*) from public.creator_package_drafts where owner_user_id=v_user)) into v_stats;
  select jsonb_build_object(
    'has_profile',exists(select 1 from public.creator_profiles where user_id=v_user),
    'has_prompt',exists(select 1 from public.content_items where owner_user_id=v_user and type='prompt' and module='kommun'),
    'has_package',exists(select 1 from public.creator_package_drafts where owner_user_id=v_user),
    'has_share',exists(select 1 from public.creator_shares where owner_user_id=v_user)) into v_checklist;
  return jsonb_build_object('needs_action',v_needs,'recent',v_recent,'stats',v_stats,'checklist',v_checklist);
end;
$$;

-- Bevara redan inskickade/publicerade creator-poster som revision 1 innan
-- originalen görs privata. Katalogens befintliga id och publicering rörs inte.
insert into public.content_snapshots (
  subject_type, subject_id, payload, purpose, owner_user_id, review_case_id,
  revision_no, submission_state, catalog_subject_id, consent_shared,
  consent_reusable, consent_distribution, rights_attested
)
select 'draft_prompt', ci.id,
  jsonb_build_object('kind','prompt','source_content_item_id',ci.id,'slug',ci.slug,
    'title',ci.title,'summary',ci.summary,'prompt_text',ci.content,
    'category',ci.category,'audience_label',ci.audience,'risk_level',ci.risk_level,
    'items','[]'::jsonb),
  'open_submission', ci.owner_user_id, gen_random_uuid(), 1,
  case ci.status when 'published' then 'published' else 'review' end,
  cp.id, ci.creator_consent_shared, ci.creator_consent_reusable,
  ci.creator_consent_distribution, ci.creator_rights_attested
from public.content_items ci
left join public.catalog_prompts cp on cp.source_content_item_id = ci.id
where ci.module='kommun' and ci.type='prompt' and ci.status in ('review','published')
  and ci.owner_user_id is not null
  and exists (select 1 from public.creator_profiles prof where prof.user_id=ci.owner_user_id)
  and not exists (select 1 from public.content_snapshots s
    where s.purpose='open_submission' and s.subject_type='draft_prompt' and s.subject_id=ci.id);

insert into public.content_snapshots (
  subject_type, subject_id, payload, purpose, owner_user_id, review_case_id,
  revision_no, submission_state, catalog_subject_id, consent_shared,
  consent_reusable, consent_distribution, rights_attested
)
select 'package_draft', d.id,
  jsonb_build_object('kind','package','source_package_draft_id',d.id,'slug',d.id::text,
    'package_type',d.package_type,'title',d.title,'summary',d.summary,
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'content_item_id',ci.id,'title',ci.title,'summary',ci.summary,
      'prompt_text',ci.content,'content',ci.content,
      'catalog_prompt_id',coalesce(ci.library_ref_catalog_prompt_id,cp.id)
    ) order by dpi.position)
    from public.creator_package_items dpi join public.content_items ci on ci.id=dpi.content_item_id
    left join public.catalog_prompts cp on cp.source_content_item_id=ci.id
    where dpi.draft_id=d.id),'[]'::jsonb)),
  'open_submission',d.owner_user_id,gen_random_uuid(),1,
  case d.status when 'published' then 'published' else 'review' end,
  pkg.id,true,false,d.creator_consent_distribution,d.creator_rights_attested
from public.creator_package_drafts d
left join public.catalog_packages pkg on pkg.source_creator_package_draft_id=d.id
where d.status in ('review','published') and not exists (
  select 1 from public.content_snapshots s where s.purpose='open_submission'
    and s.subject_type='package_draft' and s.subject_id=d.id);

-- Befintliga publicerade original muteras inte i efterhand: samma tabell
-- innehåller även äldre organisationsinnehåll med andra accessregler.
-- Alla nya inskick skapas från draft och förblir därmed redigerbara.
