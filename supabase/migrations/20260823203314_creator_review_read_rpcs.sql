-- Admins läsning av creator-inskick, över arbetsytegränsen.
-- Se docs/superpowers/specs/2026-08-23-creator-review-flow-design.md.
--
-- Inskicken ligger i creatorernas personliga arbetsytor, som
-- plattformsägaren inte är medlem i. Därför security definer med explicit
-- platform_owner-koll, inte en RLS-policy.

create or replace function app_private.list_creator_submissions()
returns table (
    subject_type text,
    subject_id uuid,
    title text,
    summary text,
    creator_profile_id uuid,
    creator_display_name text,
    creator_slug text,
    consent_shared boolean,
    consent_distribution boolean,
    rights_attested boolean,
    item_count integer,
    latest_verdict text,
    latest_screened_at timestamptz,
    updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa creator-inskick.';
    end if;

    return query
    select 'prompt'::text,
           ci.id,
           ci.title,
           ci.summary,
           prof.id,
           prof.display_name,
           prof.slug,
           ci.creator_consent_shared,
           ci.creator_consent_distribution,
           ci.creator_rights_attested,
           null::integer,
           s.verdict,
           s.created_at,
           ci.updated_at
      from public.content_items ci
      left join public.creator_profiles prof on prof.user_id = ci.owner_user_id
      left join lateral (
          select scr.verdict, scr.created_at
            from public.creator_submission_screenings scr
           where scr.subject_type = 'prompt' and scr.subject_id = ci.id
           order by scr.created_at desc
           limit 1
      ) s on true
     where ci.status = 'review'
       and ci.type = 'prompt'
       and ci.module = 'kommun'
       and ci.creator_consent_shared = true

    union all

    select 'package'::text,
           d.id,
           d.title,
           d.summary,
           prof.id,
           prof.display_name,
           prof.slug,
           true,
           d.creator_consent_distribution,
           d.creator_rights_attested,
           (select count(*)::integer
              from public.creator_package_items i
             where i.draft_id = d.id),
           s.verdict,
           s.created_at,
           d.updated_at
      from public.creator_package_drafts d
      left join public.creator_profiles prof on prof.user_id = d.owner_user_id
      left join lateral (
          select scr.verdict, scr.created_at
            from public.creator_submission_screenings scr
           where scr.subject_type = 'package' and scr.subject_id = d.id
           order by scr.created_at desc
           limit 1
      ) s on true
     where d.status = 'review'

     order by 14 desc;
end;
$$;

create or replace function public.list_creator_submissions()
returns table (
    subject_type text,
    subject_id uuid,
    title text,
    summary text,
    creator_profile_id uuid,
    creator_display_name text,
    creator_slug text,
    consent_shared boolean,
    consent_distribution boolean,
    rights_attested boolean,
    item_count integer,
    latest_verdict text,
    latest_screened_at timestamptz,
    updated_at timestamptz
)
language sql
security invoker
set search_path = ''
as $$
    select * from app_private.list_creator_submissions();
$$;

revoke all on function public.list_creator_submissions() from public;
grant execute on function public.list_creator_submissions() to authenticated;

-- Detaljvy. Returnerar jsonb eftersom prompt och paket har olika form och
-- adminvyn ska slippa två skilda anropsvägar.
create or replace function app_private.get_creator_submission(
    p_subject_type text,
    p_subject_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_result jsonb;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa creator-inskick.';
    end if;

    if p_subject_type = 'prompt' then
        select jsonb_build_object(
                   'subject_type', 'prompt',
                   'subject_id', ci.id,
                   'title', ci.title,
                   'summary', ci.summary,
                   'content', ci.content,
                   'category', ci.category,
                   'consent_shared', ci.creator_consent_shared,
                   'consent_reusable', ci.creator_consent_reusable,
                   'consent_distribution', ci.creator_consent_distribution,
                   'rights_attested', ci.creator_rights_attested,
                   'creator_display_name', prof.display_name,
                   'creator_slug', prof.slug,
                   'items', '[]'::jsonb
               )
          into v_result
          from public.content_items ci
          left join public.creator_profiles prof on prof.user_id = ci.owner_user_id
         where ci.id = p_subject_id
           and ci.status = 'review';
    elsif p_subject_type = 'package' then
        select jsonb_build_object(
                   'subject_type', 'package',
                   'subject_id', d.id,
                   'title', d.title,
                   'summary', d.summary,
                   'content', null,
                   'category', null,
                   'consent_shared', true,
                   'consent_reusable', null,
                   'consent_distribution', d.creator_consent_distribution,
                   'rights_attested', d.creator_rights_attested,
                   'creator_display_name', prof.display_name,
                   'creator_slug', prof.slug,
                   'items', coalesce((
                       select jsonb_agg(jsonb_build_object(
                                  'content_item_id', ci.id,
                                  'title', ci.title,
                                  'content', ci.content,
                                  'status', ci.status::text,
                                  'position', i.position
                              ) order by i.position)
                         from public.creator_package_items i
                         join public.content_items ci on ci.id = i.content_item_id
                        where i.draft_id = d.id
                   ), '[]'::jsonb)
               )
          into v_result
          from public.creator_package_drafts d
          left join public.creator_profiles prof on prof.user_id = d.owner_user_id
         where d.id = p_subject_id
           and d.status = 'review';
    else
        raise exception 'Okänd typ: %. Ange prompt eller package.', p_subject_type;
    end if;

    if v_result is null then
        raise exception 'Inskicket hittades inte eller är inte under granskning.';
    end if;

    return v_result || jsonb_build_object('screenings', coalesce((
        select jsonb_agg(jsonb_build_object(
                   'verdict', scr.verdict,
                   'findings', scr.findings,
                   'suggested_feedback', scr.suggested_feedback,
                   'rules_version', scr.rules_version,
                   'model', scr.model,
                   'created_at', scr.created_at
               ) order by scr.created_at desc)
          from public.creator_submission_screenings scr
         where scr.subject_type = p_subject_type
           and scr.subject_id = p_subject_id
    ), '[]'::jsonb));
end;
$$;

create or replace function public.get_creator_submission(p_subject_type text, p_subject_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.get_creator_submission(p_subject_type, p_subject_id);
$$;

revoke all on function public.get_creator_submission(text, uuid) from public;
grant execute on function public.get_creator_submission(text, uuid) to authenticated;
