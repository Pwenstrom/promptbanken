-- Låter creatorn faktiskt lämna distributionssamtycket och rättighetsintyget.
--
-- 20260823090000 lade till creator_consent_distribution och
-- creator_rights_attested på content_items och creator_package_drafts, men
-- inskicks-RPC:erna uppdaterades aldrig. Fälten kunde därför aldrig bli
-- sanna, och distributionsgaten i list_published_* hade aldrig kunnat
-- öppnas för någon post — delprojekt 7 vore omöjligt att slutföra.
--
-- Regel: rättighetsintyget krävs för distributionssamtycket. Att säga ja
-- till spridning via externa AI-klienter utan att intyga att man har rätt
-- att sprida innehållet är inget vi ska registrera.
--
-- Signaturerna byts från tre till fem respektive ett till tre argument.
-- Gamla signaturen droppas i samma migration; en tillagd default-parameter
-- skulle skapa en andra överlagring och göra PostgREST-anropet tvetydigt.

drop function if exists public.submit_creator_prompt(uuid, boolean, boolean);
drop function if exists app_private.submit_creator_prompt(uuid, boolean, boolean);

create or replace function app_private.submit_creator_prompt(
    p_content_item_id uuid,
    p_consent_shared boolean,
    p_consent_reusable boolean,
    p_consent_distribution boolean default false,
    p_rights_attested boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_updated_id uuid;
begin
    -- Villkoren nedan är originalets, ordagrant. Notera särskilt
    -- "status <> 'published'" i stället för "status = 'draft'": ett
    -- arkiverat inskick ska kunna skickas in igen utan omvägar.
    if coalesce(p_consent_shared, false) is not true then
        raise exception 'Du måste godkänna att prompten delas i öppna Promptbanken innan den kan skickas in.';
    end if;

    if coalesce(p_consent_distribution, false) and not coalesce(p_rights_attested, false) then
        raise exception 'För att innehållet ska få distribueras vidare måste du också intyga att du har rätt att sprida det.';
    end if;

    update public.content_items
       set status = 'review',
           creator_consent_shared = true,
           creator_consent_reusable = coalesce(p_consent_reusable, false),
           creator_consent_distribution = coalesce(p_consent_distribution, false),
           creator_rights_attested = coalesce(p_rights_attested, false),
           updated_at = now()
     where id = p_content_item_id
       and owner_user_id = (select auth.uid())
       and type = 'prompt'
       and module = 'kommun'
       and status <> 'published'
    returning id into v_updated_id;

    if v_updated_id is null then
        raise exception 'Prompten hittades inte, tillhör inte dig, eller är redan publicerad.';
    end if;

    return jsonb_build_object('id', v_updated_id, 'status', 'review');
end;
$$;

create or replace function public.submit_creator_prompt(
    p_content_item_id uuid,
    p_consent_shared boolean,
    p_consent_reusable boolean,
    p_consent_distribution boolean default false,
    p_rights_attested boolean default false
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.submit_creator_prompt(
        p_content_item_id, p_consent_shared, p_consent_reusable,
        p_consent_distribution, p_rights_attested
    );
$$;

revoke all on function public.submit_creator_prompt(uuid, boolean, boolean, boolean, boolean) from public;
grant execute on function public.submit_creator_prompt(uuid, boolean, boolean, boolean, boolean) to authenticated;

-- Paket-utkast: samma två fält.

drop function if exists public.submit_creator_package_draft(uuid);
drop function if exists app_private.submit_creator_package_draft(uuid);

create or replace function app_private.submit_creator_package_draft(
    p_draft_id uuid,
    p_consent_distribution boolean default false,
    p_rights_attested boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
-- Kroppen är originalets, ordagrant, med enbart de två nya fälten
-- tillagda i update-satsen och samtyckeskontrollen inlagd först. Radlåset
-- och pg_advisory_xact_lock måste vara kvar: utan låset kan två samtidiga
-- inskick båda passera treportsgränsen.
declare
    v_draft_owner uuid;
    v_item_count integer;
    v_review_count integer;
begin
    if coalesce(p_consent_distribution, false) and not coalesce(p_rights_attested, false) then
        raise exception 'För att paketet ska få distribueras vidare måste du också intyga att du har rätt att sprida innehållet.';
    end if;

    select owner_user_id into v_draft_owner
      from public.creator_package_drafts
     where id = p_draft_id and status = 'draft'
     for update;

    if v_draft_owner is null or v_draft_owner <> (select auth.uid()) then
        raise exception 'Paketet hittades inte, tillhör inte dig, eller är redan inskickat.';
    end if;

    select count(*) into v_item_count from public.creator_package_items where draft_id = p_draft_id;
    if v_item_count = 0 then
        raise exception 'Paketet behöver minst en prompt innan det kan skickas in.';
    end if;

    perform pg_advisory_xact_lock(hashtext((select auth.uid())::text));

    select count(*) into v_review_count
      from public.creator_package_drafts
     where owner_user_id = (select auth.uid()) and status = 'review';
    if v_review_count >= 3 then
        raise exception 'Du har redan 3 paket under granskning. Dra tillbaka eller vänta på granskning av ett annat paket innan du skickar in fler.';
    end if;

    update public.creator_package_drafts
       set status = 'review',
           creator_consent_distribution = coalesce(p_consent_distribution, false),
           creator_rights_attested = coalesce(p_rights_attested, false),
           updated_at = now()
     where id = p_draft_id;

    return jsonb_build_object('id', p_draft_id, 'status', 'review');
end;
$$;

create or replace function public.submit_creator_package_draft(
    p_draft_id uuid,
    p_consent_distribution boolean default false,
    p_rights_attested boolean default false
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.submit_creator_package_draft(p_draft_id, p_consent_distribution, p_rights_attested);
$$;

revoke all on function public.submit_creator_package_draft(uuid, boolean, boolean) from public;
grant execute on function public.submit_creator_package_draft(uuid, boolean, boolean) to authenticated;

-- Dra tillbaka ska nollställa alla fyra samtyckena, inte bara de två gamla.

create or replace function app_private.withdraw_creator_prompt(p_content_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_updated_id uuid;
begin
    update public.content_items
       set status = 'draft',
           creator_consent_shared = false,
           creator_consent_reusable = false,
           creator_consent_distribution = false,
           creator_rights_attested = false,
           updated_at = now()
     where id = p_content_item_id
       and owner_user_id = (select auth.uid())
       and status = 'review'
    returning id into v_updated_id;

    if v_updated_id is null then
        raise exception 'Prompten hittades inte, tillhör inte dig, eller är inte under granskning (publicerat innehåll kan inte dras tillbaka härifrån).';
    end if;

    return jsonb_build_object('id', v_updated_id, 'status', 'draft');
end;
$$;
