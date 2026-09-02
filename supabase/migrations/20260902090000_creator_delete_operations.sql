-- supabase/migrations/20260902090000_creator_delete_operations.sql
-- Creator-flödet kunde skapa men aldrig ta bort. Tre konkreta hål:
--
--   1. creator-content.html hade ingen väg att radera en egen prompt.
--      RLS-policyn från 20260630100000 finns, men bara admin.js använder
--      den -- Creator-vyn fick aldrig någon motsvarande handling.
--   2. creator_package_drafts har varken DELETE-policy eller DELETE-grant
--      (20260819090000 rad 33-34: "allt går via RPC:erna nedan"), och
--      någon delete-RPC skrevs aldrig. Ett paket-utkast gick alltså inte
--      att ta bort på någon väg alls.
--   3. Referenser tillagda med add_catalog_prompt_to_library /
--      add_catalog_package_to_library (20260831090000, 20260901100000)
--      hade ingen borttagningsväg -- "lägg till i mitt bibliotek" var en
--      enkelriktad handling. Prompt-referenser (module='valvet') syntes
--      dessutom ingenstans: list_my_creator_prompts filtrerar
--      module='kommun' och "Mina prompter" i promptbanken.html filtrerar
--      bort library_ref_catalog_prompt_id is not null.
--
-- Regeln för borttagning är densamma på båda ytorna: eget utkast eller
-- avslaget objekt får tas bort, under granskning måste dras tillbaka
-- först (annars försvinner något en granskare arbetar i), och publicerat
-- innehåll tas inte bort härifrån -- det ligger i den öppna katalogen och
-- måste avpubliceras av en admin.
--
-- Aktiva delningslänkar (creator_shares) mot objektet avslutas i samma
-- transaktion. subject_id har ingen främmande nyckel, så en kvarlämnad
-- delning skulle peka på en rad som inte längre finns.

-- 1. Ta bort en egen prompt (eller sluta följa en katalogprompt) ---------

create or replace function app_private.delete_my_creator_prompt(
    p_content_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid  uuid := (select auth.uid());
    v_row  public.content_items%rowtype;
begin
    if v_uid is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    select * into v_row
      from public.content_items
     where id = p_content_item_id
       and owner_user_id = v_uid
       and type = 'prompt';

    if not found then
        raise exception 'Prompten hittades inte eller tillhör inte dig.';
    end if;

    if v_row.status = 'published' then
        raise exception 'Publicerade prompts kan inte tas bort härifrån. Kontakta Promptbanken för att avpublicera den först.';
    end if;

    if v_row.status = 'review' then
        raise exception 'Prompten är under granskning. Dra tillbaka den först, sedan kan den tas bort.';
    end if;

    update public.creator_shares
       set revoked_at = now()
     where owner_user_id = v_uid
       and subject_type = 'prompt'
       and subject_id = v_row.id
       and revoked_at is null;

    delete from public.content_items where id = v_row.id;

    return jsonb_build_object(
        'id', v_row.id,
        'deleted', true,
        'was_library_reference', v_row.library_ref_catalog_prompt_id is not null
    );
end;
$$;

revoke all on function app_private.delete_my_creator_prompt(uuid) from public;

create or replace function public.delete_my_creator_prompt(p_content_item_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
    select app_private.delete_my_creator_prompt(p_content_item_id);
$$;

revoke all on function public.delete_my_creator_prompt(uuid) from public;
grant execute on function public.delete_my_creator_prompt(uuid) to authenticated;

-- 2. Ta bort ett eget paket-utkast (eller sluta följa ett katalogpaket) --

create or replace function app_private.delete_my_creator_package_draft(
    p_draft_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid := (select auth.uid());
    v_row public.creator_package_drafts%rowtype;
begin
    if v_uid is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    select * into v_row
      from public.creator_package_drafts
     where id = p_draft_id
       and owner_user_id = v_uid;

    if not found then
        raise exception 'Paketet hittades inte eller tillhör inte dig.';
    end if;

    if v_row.status = 'published' then
        raise exception 'Publicerade paket kan inte tas bort härifrån. Kontakta Promptbanken för att avpublicera det först.';
    end if;

    if v_row.status = 'review' then
        raise exception 'Paketet är under granskning. Dra tillbaka det först, sedan kan det tas bort.';
    end if;

    update public.creator_shares
       set revoked_at = now()
     where owner_user_id = v_uid
       and subject_type = 'package'
       and subject_id = v_row.id
       and revoked_at is null;

    -- creator_package_items har on delete cascade mot draft_id
    -- (20260819090000 rad 38). Prompt-raderna i content_items rörs inte:
    -- de är egna prompts som kan ingå i fler paket.
    delete from public.creator_package_drafts where id = v_row.id;

    return jsonb_build_object(
        'id', v_row.id,
        'deleted', true,
        'was_library_reference', v_row.library_ref_catalog_package_id is not null
    );
end;
$$;

revoke all on function app_private.delete_my_creator_package_draft(uuid) from public;

create or replace function public.delete_my_creator_package_draft(p_draft_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
    select app_private.delete_my_creator_package_draft(p_draft_id);
$$;

revoke all on function public.delete_my_creator_package_draft(uuid) from public;
grant execute on function public.delete_my_creator_package_draft(uuid) to authenticated;

-- 3. Läs biblioteket: följda och kopierade prompts -----------------------
--
-- Ny, snävt syftad läsväg i stället för att bredda list_my_creator_prompts
-- (module='kommun'). Samma motivering som list_my_package_eligible_prompts
-- i 20260901110000: den befintliga listan driver Creator-publiceringen,
-- där submit/update-RPC:erna kräver module='kommun'. Referensrader har
-- tom content -- titel och sammanfattning läses live ur katalogen, precis
-- som get_referenced_library_prompt gör för prompttexten.

create or replace function public.list_my_library_prompts()
returns table (
    id uuid,
    title text,
    summary text,
    category text,
    status text,
    is_library_reference boolean,
    source_prompt_id uuid,
    updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select ci.id,
           coalesce(v.title, ci.title),
           coalesce(v.summary, ci.summary),
           coalesce(v.area, ci.category),
           ci.status::text,
           ci.library_ref_catalog_prompt_id is not null,
           coalesce(ci.library_ref_catalog_prompt_id, ci.source_template_id),
           ci.updated_at
      from public.content_items ci
      left join public.catalog_prompt_variants v
        on v.prompt_id = ci.library_ref_catalog_prompt_id
       and v.context_key = 'generell'
     where ci.owner_user_id = (select auth.uid())
       and ci.type = 'prompt'
       and ci.module = 'valvet'
       and ci.status <> 'archived'
     order by ci.updated_at desc;
$$;

revoke all on function public.list_my_library_prompts() from public;
grant execute on function public.list_my_library_prompts() to authenticated;

-- 4. Paketlistan måste kunna skilja referens från eget utkast ------------
--
-- Utan flaggan renderar creator-packages.html en följd katalogpakets-
-- referens som ett tomt eget utkast med "Lägg till prompt" och "Skicka in
-- för granskning" -- handlingar som inte betyder något för en referens.

drop function if exists public.list_my_creator_package_drafts();

create or replace function public.list_my_creator_package_drafts()
returns table (
    id uuid,
    title text,
    summary text,
    package_type text,
    status text,
    item_count integer,
    review_note text,
    is_library_reference boolean,
    updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select d.id, d.title, d.summary, d.package_type, d.status,
           (select count(*)::integer from public.creator_package_items i where i.draft_id = d.id),
           d.review_note,
           d.library_ref_catalog_package_id is not null,
           d.updated_at
      from public.creator_package_drafts d
     where d.owner_user_id = (select auth.uid())
     order by d.updated_at desc;
$$;

revoke all on function public.list_my_creator_package_drafts() from public;
grant execute on function public.list_my_creator_package_drafts() to authenticated;
