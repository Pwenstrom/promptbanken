-- supabase/tests/creator_authoring.sql
-- Manuell/CI-körd kontroll. Kör mot en databas med migrationen applicerad.
-- Förutsätter två testanvändare (byt ut UUID:erna mot riktiga auth.users-id:n
-- i din testmiljö, t.ex. via seed-test-users.mjs-mönstret).

-- 1. submit_creator_prompt vägrar utan samtycke
do $$
begin
    begin
        perform app_private.submit_creator_prompt(gen_random_uuid(), false, false);
        raise exception 'FEL: submit_creator_prompt borde ha kastat fel utan samtycke';
    exception when others then
        if sqlerrm not like '%godkänna%' then
            raise;
        end if;
    end;
end $$;

-- 2. add_prompt_to_package_draft stoppar vid 8 prompts (strukturell kontroll,
-- kör mot en riktig draft med 8 redan tillagda rader i din testmiljö och
-- verifiera att rad 9 kastar 'högst 8 prompts').

-- 3. submit_creator_package_draft stoppar vid 3 samtidiga review-paket
-- (skapa 3 drafts, submit:a alla tre, försök submit:a en fjärde, förvänta fel
-- som matchar '%3 paket under granskning%').

-- 4. RLS: en annan användares session kan inte se draften
-- (sätt session till user B, kör `select * from creator_package_drafts
-- where id = '<user A:s draft-id>'` — förvänta 0 rader).
