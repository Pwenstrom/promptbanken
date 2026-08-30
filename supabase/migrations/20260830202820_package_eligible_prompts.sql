-- supabase/migrations/20260901110000_package_eligible_prompts.sql
-- Paketbyggarens picker (creatorPackages.js, i loadDrafts()) läser idag
-- list_my_creator_prompts(), som filtrerar module='kommun' -- en
-- användares Valvet-prompts (module='valvet') syns aldrig som
-- valbara, trots att add_prompt_to_package_draft (20260819090000,
-- rad 267-275) redan accepterar dem (kollar bara type='prompt' och
-- ägarskap, ingen modulrestriktion). Ny, separat RPC istället för att
-- ändra list_my_creator_prompts() -- den kan ha andra beroenden,
-- säkrare att lägga till en ny, snävt syftad läsväg. Se
-- docs/superpowers/specs/2026-08-30-connect-my-library-architecture-
-- analysis.md sektion P.3.

create or replace function public.list_my_package_eligible_prompts()
returns table (
    id uuid,
    title text,
    status text
)
language sql
stable
security definer
set search_path = ''
as $$
    select ci.id, ci.title, ci.status::text
      from public.content_items ci
     where ci.owner_user_id = (select auth.uid())
       and ci.type = 'prompt'
       and ci.module in ('kommun', 'valvet')
       and ci.status <> 'archived'
     order by ci.updated_at desc;
$$;

revoke all on function public.list_my_package_eligible_prompts() from public;
grant execute on function public.list_my_package_eligible_prompts() to authenticated;
