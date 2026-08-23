-- Verifierar besluts-RPC:erna för creator-inskick (delprojekt 4).
--
-- VIKTIGT om körsätt: triggern app_private.enforce_content_access_model
-- kräver att auth.uid() är satt när en content_items-rad skapas
-- ("Prompts måste skapas av inloggad användare."). Testet går därför inte
-- att köra från en tjänsteanslutning utan auth-kontext, till exempel
-- Supabase-MCP:n eller psql som postgres. Kör det via PostgREST med en
-- riktig plattformsägar-JWT, eller i SQL-editorn med användarkontext.

-- Del 1: negativ väg. Kör som användare som INTE är plattformsägare.
do $$
declare
    v_leaked boolean := false;
begin
    begin
        perform public.request_changes_creator_submission('prompt', gen_random_uuid(), 'test');
        v_leaked := true;
    exception when others then
        raise notice 'OK: request_changes avvisade icke-plattformsägare';
    end;

    if v_leaked then
        raise exception 'FEL: request_changes släppte igenom en icke-plattformsägare';
    end if;

    begin
        perform public.approve_creator_prompt(gen_random_uuid(), 'x', null, null);
        v_leaked := true;
    exception when others then
        raise notice 'OK: approve_creator_prompt avvisade icke-plattformsägare';
    end;

    if v_leaked then
        raise exception 'FEL: approve_creator_prompt släppte igenom en icke-plattformsägare';
    end if;
end;
$$;

-- Del 2: positiv väg. Kör som plattformsägare med auth-kontext.
-- Skapar sitt eget testdata och städar upp efter sig.
do $$
declare
    v_owner uuid := (select auth.uid());
    v_workspace uuid;
    v_item uuid;
    v_result jsonb;
    v_slug text := 'testprompt-' || substr(gen_random_uuid()::text, 1, 8);
begin
    if v_owner is null then
        raise exception 'Testet kräver auth-kontext. Se kommentaren överst i filen.';
    end if;

    v_workspace := public.ensure_personal_workspace();

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, title, slug, summary, content,
        status, visibility, creator_consent_shared, creator_consent_distribution, creator_rights_attested
    )
    values (
        v_workspace, v_owner, v_owner, 'prompt', 'Testprompt för granskning',
        'testprompt-granskning-' || substr(gen_random_uuid()::text, 1, 8),
        'Sammanfattning', 'Skriv ett svar om X.',
        'review', 'private', true, true, true
    )
    returning id into v_item;

    v_result := public.approve_creator_prompt(v_item, v_slug, 'library', null);

    if (v_result->>'status') <> 'draft' then
        raise exception 'FEL: katalogposten skapades inte som utkast';
    end if;

    if not exists (
        select 1 from public.catalog_prompts
         where id = (v_result->>'catalog_prompt_id')::uuid
           and creator_consent_distribution = true
           and creator_rights_attested = true
           and creator_profile_id is not distinct from (v_result->>'creator_profile_id')::uuid
           and source_content_item_id = v_item
    ) then
        raise exception 'FEL: attributionen eller proveniensen kopierades inte till katalogposten';
    end if;

    if (select status::text from public.content_items where id = v_item) <> 'published' then
        raise exception 'FEL: källposten sattes inte till published';
    end if;

    if (select count(*) from public.catalog_prompt_variants
         where prompt_id = (v_result->>'catalog_prompt_id')::uuid
           and context_key = 'generell') <> 1 then
        raise exception 'FEL: generell-varianten skapades inte';
    end if;

    raise notice 'OK: approve_creator_prompt skapar utkast, kopierar attribution och sätter proveniens';

    delete from public.catalog_prompts where id = (v_result->>'catalog_prompt_id')::uuid;
    delete from public.content_items where id = v_item;
end;
$$;

-- Del 3: tom motivering ska avvisas. Kör som plattformsägare.
do $$
declare
    v_leaked boolean := false;
begin
    begin
        perform public.request_changes_creator_submission('prompt', gen_random_uuid(), '   ');
        v_leaked := true;
    exception when others then
        if sqlerrm not like '%motivering%' then
            raise exception 'FEL: fel avvisningsorsak: %', sqlerrm;
        end if;
        raise notice 'OK: tom motivering avvisas';
    end;

    if v_leaked then
        raise exception 'FEL: tom motivering accepterades';
    end if;
end;
$$;
