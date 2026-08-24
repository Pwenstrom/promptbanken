-- Återkoppling till creatorn (delprojekt 4).
--
-- Utan review_note i listnings-RPC:erna ser creatorn aldrig varför en
-- ändring begärdes, och adminets "Begär ändring" blir en återvändsgränd:
-- posten hamnar tillbaka i draft utan att någon förklaring når fram.
--
-- Signaturerna är oförändrade (inga argument), men returtabellen växer.
-- create or replace klarar inte en ändrad returtabell, så drop krävs.

drop function if exists public.list_my_creator_prompts();

create or replace function public.list_my_creator_prompts()
returns table (
    id uuid,
    title text,
    slug text,
    summary text,
    status text,
    visibility text,
    creator_consent_shared boolean,
    creator_consent_reusable boolean,
    review_note text,
    updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select ci.id, ci.title, ci.slug, ci.summary, ci.status::text, ci.visibility::text,
           ci.creator_consent_shared, ci.creator_consent_reusable, ci.review_note,
           ci.updated_at
      from public.content_items ci
     where ci.owner_user_id = (select auth.uid())
       and ci.type = 'prompt'
       and ci.module = 'kommun'
     order by ci.updated_at desc;
$$;

revoke all on function public.list_my_creator_prompts() from public;
grant execute on function public.list_my_creator_prompts() to authenticated;

drop function if exists public.list_my_creator_package_drafts();

create or replace function public.list_my_creator_package_drafts()
returns table (
    id uuid,
    title text,
    summary text,
    status text,
    item_count integer,
    review_note text,
    updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select d.id, d.title, d.summary, d.status,
           (select count(*)::integer from public.creator_package_items i where i.draft_id = d.id),
           d.review_note,
           d.updated_at
      from public.creator_package_drafts d
     where d.owner_user_id = (select auth.uid())
     order by d.updated_at desc;
$$;

revoke all on function public.list_my_creator_package_drafts() from public;
grant execute on function public.list_my_creator_package_drafts() to authenticated;
