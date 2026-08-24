-- Verifierar distributionsgaten: creator-innehåll ska inte nå
-- Promptbanken Open/MCP, men ska synas på webben (delprojekt 4).
--
-- Testet skapar en publicerad katalogpost med creator-attribution, mäter
-- gaten åt båda håll, och rullar tillbaka allt genom att avbryta blocket.
-- Inget testdata blir kvar.
--
-- Kan köras med tjänsteanslutning (Supabase-MCP, psql) — till skillnad
-- från creator_review_decisions.sql behövs ingen auth-kontext här.

do $$
declare
    v_prof uuid;
    v_prompt uuid;
    v_pkg uuid;
    v_slug text := 'gatetest-' || substr(gen_random_uuid()::text, 1, 8);
    v_pkg_slug text := 'gatetest-pkg-' || substr(gen_random_uuid()::text, 1, 8);
    v_mcp integer;
    v_webb integer;
    v_get_mcp integer;
    v_get_webb integer;
    v_pkg_mcp integer;
    v_pkg_webb integer;
    v_fel text := '';
begin
    select id into v_prof from public.creator_profiles limit 1;
    if v_prof is null then
        raise exception 'Testet kräver minst en creator_profiles-rad.';
    end if;

    -- Creator-attribuerad prompt.
    insert into public.catalog_prompts (slug, status, prompt_kind, creator_profile_id)
    values (v_slug, 'published', 'prompt', v_prof)
    returning id into v_prompt;

    insert into public.catalog_prompt_variants (prompt_id, context_key, title, summary, prompt_text)
    values (v_prompt, 'generell', 'Gate-test', 'Sammanfattning', 'Text');

    -- Creator-attribuerat paket.
    insert into public.catalog_packages (slug, status, package_type, creator_profile_id)
    values (v_pkg_slug, 'published', 'collection', v_prof)
    returning id into v_pkg;

    insert into public.catalog_package_variants (package_id, context_key, title, summary)
    values (v_pkg, 'generell', 'Gate-test paket', 'Sammanfattning');

    select count(*) into v_mcp
      from public.list_published_prompts(array['generell']) where slug = v_slug;
    select count(*) into v_webb
      from public.list_published_prompts(array['generell'], true) where slug = v_slug;
    select count(*) into v_get_mcp
      from public.get_published_prompt(v_slug, array['generell']);
    select count(*) into v_get_webb
      from public.get_published_prompt(v_slug, array['generell'], true);
    select count(*) into v_pkg_mcp
      from public.list_published_packages(array['generell']) where slug = v_pkg_slug;
    select count(*) into v_pkg_webb
      from public.list_published_packages(array['generell'], null, true) where slug = v_pkg_slug;

    if v_mcp <> 0 then
        v_fel := v_fel || 'list_published_prompts läckte creator-innehåll till MCP-vägen. ';
    end if;
    if v_webb <> 1 then
        v_fel := v_fel || 'list_published_prompts dolde creator-innehåll för webben. ';
    end if;
    if v_get_mcp <> 0 then
        v_fel := v_fel || 'get_published_prompt läckte creator-innehåll till MCP-vägen. ';
    end if;
    if v_get_webb <> 1 then
        v_fel := v_fel || 'get_published_prompt dolde creator-innehåll för webben. ';
    end if;
    if v_pkg_mcp <> 0 then
        v_fel := v_fel || 'list_published_packages läckte creator-paket till MCP-vägen. ';
    end if;
    if v_pkg_webb <> 1 then
        v_fel := v_fel || 'list_published_packages dolde creator-paket för webben. ';
    end if;

    -- Blocket avbryts alltid, så testdata rullas tillbaka. Meddelandet
    -- säger om gaten höll.
    if v_fel <> '' then
        raise exception 'GATE-TEST MISSLYCKADES (rullat tillbaka): %', v_fel;
    end if;

    raise exception 'GATE-TEST OK (rullat tillbaka): creator-innehåll osynligt för Open/MCP, synligt för webben.';
end;
$$;
