-- Data till creator-översikten.
--
-- Ett anrop, inte fyra. Fyra separata anrop för fyra sektioner ger en sida
-- som byggs i ryck, och översiktens hela poäng är att svara på "vad väntar
-- på mig" innan användaren hunnit undra.
--
-- Delningar och importerade utkast finns inte än; när de gör det utökas
-- needs_action och stats här i stället för att sidan får fler anrop.

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

    return jsonb_build_object(
        'needs_action', v_needs_action,
        'recent', v_recent,
        'stats', v_stats
    );
end;
$$;

create or replace function public.get_my_creator_overview()
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.get_my_creator_overview();
$$;

revoke all on function public.get_my_creator_overview() from public;
grant execute on function public.get_my_creator_overview() to authenticated;
