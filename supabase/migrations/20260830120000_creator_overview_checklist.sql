-- Kom igång-checklista på creator-översikten.
--
-- get_my_creator_overview() får ett fjärde fält, checklist: har
-- användaren gjort respektive sak minst en gång. Utkast räcker -- det
-- här är "har du provat", inte "är det publicerat".

create or replace function app_private.get_my_creator_overview()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user uuid := (select auth.uid());
    v_needs_action jsonb;
    v_recent jsonb;
    v_stats jsonb;
    v_checklist jsonb;
begin
    if v_user is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    -- Kräver åtgärd: allt som skickats tillbaka eller avslagits med en
    -- motivering. Utan motivering finns inget att åtgärda.
    select coalesce(jsonb_agg(row_to_json(t) order by t.updated_at desc), '[]'::jsonb)
      into v_needs_action
      from (
        select 'prompt'::text as kind,
               ci.id,
               ci.title,
               ci.status::text as status,
               ci.review_note,
               ci.updated_at
          from public.content_items ci
         where ci.owner_user_id = v_user
           and ci.type = 'prompt'
           and ci.module = 'kommun'
           and ci.status in ('draft', 'archived')
           and coalesce(trim(ci.review_note), '') <> ''

        union all

        select 'package'::text,
               d.id,
               d.title,
               d.status,
               d.review_note,
               d.updated_at
          from public.creator_package_drafts d
         where d.owner_user_id = v_user
           and d.status in ('draft', 'archived')
           and coalesce(trim(d.review_note), '') <> ''
      ) t;

    -- Fortsätt arbeta: de fem senast ändrade, oavsett typ eller status.
    select coalesce(jsonb_agg(row_to_json(t) order by t.updated_at desc), '[]'::jsonb)
      into v_recent
      from (
        select 'prompt'::text as kind, ci.id, ci.title, ci.status::text as status, ci.updated_at
          from public.content_items ci
         where ci.owner_user_id = v_user
           and ci.type = 'prompt'
           and ci.module = 'kommun'

        union all

        select 'package'::text, d.id, d.title, d.status, d.updated_at
          from public.creator_package_drafts d
         where d.owner_user_id = v_user

         order by 5 desc
         limit 5
      ) t;

    select jsonb_build_object(
        'published_prompts', (
            select count(*) from public.content_items ci
             where ci.owner_user_id = v_user and ci.type = 'prompt'
               and ci.module = 'kommun' and ci.status = 'published'
        ),
        'published_packages', (
            select count(*) from public.creator_package_drafts d
             where d.owner_user_id = v_user and d.status = 'published'
        ),
        'in_review', (
            select count(*) from public.content_items ci
             where ci.owner_user_id = v_user and ci.type = 'prompt'
               and ci.module = 'kommun' and ci.status = 'review'
        ) + (
            select count(*) from public.creator_package_drafts d
             where d.owner_user_id = v_user and d.status = 'review'
        ),
        'drafts', (
            select count(*) from public.content_items ci
             where ci.owner_user_id = v_user and ci.type = 'prompt'
               and ci.module = 'kommun' and ci.status = 'draft'
        ) + (
            select count(*) from public.creator_package_drafts d
             where d.owner_user_id = v_user and d.status = 'draft'
        )
    ) into v_stats;

    select jsonb_build_object(
        'has_profile', exists (
            select 1 from public.creator_profiles where user_id = v_user
        ),
        'has_prompt', exists (
            select 1 from public.content_items
             where owner_user_id = v_user and type = 'prompt' and module = 'kommun'
        ),
        'has_package', exists (
            select 1 from public.creator_package_drafts where owner_user_id = v_user
        ),
        'has_share', exists (
            select 1 from public.creator_shares where owner_user_id = v_user
        )
    ) into v_checklist;

    return jsonb_build_object(
        'needs_action', v_needs_action,
        'recent', v_recent,
        'stats', v_stats,
        'checklist', v_checklist
    );
end;
$$;
