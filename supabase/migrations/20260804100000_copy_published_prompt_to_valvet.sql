-- 20260804100000_copy_published_prompt_to_valvet.sql
-- Valvet läste tidigare katalogen via två separata legacy-vägar:
-- copy_catalog_item_to_valvet (content_items module='kommun', MVP-katalogen
-- från juni) och copy_template_to_valvet (pro_prompt_templates, som
-- promptbanken.html själv redan bytt bort från 2026-08-02, commit
-- 432ded0 "fix(web): read Pro template list from the catalog instead of
-- legacy pro_prompt_templates"). Ingen av dem läser dagens källa till
-- sanning: catalog_prompts/catalog_prompt_variants.
--
-- Detta lägger till en tredje kopieringsväg, copy_published_prompt_to_valvet,
-- som läser samma tabeller och samma kontextfallback-mönster som
-- list_published_prompts/get_published_prompt (20260721130000,
-- 20260729120000) så Valvets katalogbläddring visar samma innehåll som
-- promptbanken.html gör idag, inklusive area/risk_level.
--
-- De två äldre kopieringsvägarna rörs INTE -- historiska Valvet-kopior som
-- redan pekar på content_items(module='kommun) eller pro_prompt_templates
-- ska fortsätta fungera. source_template_id/source_version/source_copied_at
-- (tillagda i 20260727141513) återanvänds här för den nya källan också --
-- kolumnerna är bara uuid/text/timestamptz, ingen FK till en specifik
-- källtabell, så de bär redan dubbla betydelser i praktiken.

comment on column public.content_items.source_template_id is
    'Källpost i antingen pro_prompt_templates (copy_template_to_valvet, legacy) eller catalog_prompts (copy_published_prompt_to_valvet) beroende på vilken kopieringsväg som användes.';

create or replace function app_private.copy_published_prompt_to_valvet(
    p_prompt_id    uuid,
    p_context_keys text[] default array['generell'::text]
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ws             public.workspaces%rowtype;
    v_existing       public.content_items%rowtype;
    v_row            public.content_items%rowtype;
    v_copy_count     integer;
    v_slug           text;
    v_is_pro         boolean;
    v_source_version text;
    v_copied_at      timestamptz := now();
    v_id             uuid;
    v_title          text;
    v_summary        text;
    v_prompt_text    text;
    v_area           text;
    v_risk_level     text;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    select w.* into v_ws
      from public.workspaces w
      join public.profiles p on p.workspace_id = w.id
     where p.user_id = auth.uid()
       and w.type = 'personal'
       and w.status = 'active'
     order by p.created_at
     limit 1;

    if not found then
        raise exception 'Inget personligt workspace hittades.';
    end if;

    v_is_pro := app_private.has_active_pro_entitlement(v_ws.owner_user_id);

    -- Samma matchat-eller-generell-fallback som list_published_prompts/
    -- get_published_prompt (20260729120000).
    select cp.id,
           coalesce(matched.title, fallback.title),
           coalesce(matched.summary, fallback.summary),
           coalesce(matched.prompt_text, fallback.prompt_text),
           coalesce(matched.area, fallback.area),
           coalesce(matched.risk_level, fallback.risk_level)
      into v_id, v_title, v_summary, v_prompt_text, v_area, v_risk_level
      from public.catalog_prompts cp
      left join lateral (
          select v.*
            from public.catalog_prompt_variants v
           where v.prompt_id = cp.id
             and v.context_key = any(p_context_keys)
           order by array_position(p_context_keys, v.context_key)
           limit 1
      ) matched on true
      left join public.catalog_prompt_variants fallback
        on fallback.prompt_id = cp.id
       and fallback.context_key = 'generell'
     where cp.id = p_prompt_id
       and cp.status = 'published';

    if v_id is null or v_prompt_text is null then
        raise exception 'Den här mallen finns inte.';
    end if;

    -- Dubblettskydd: samma källa redan kopierad och inte arkiverad -> returnera den.
    select * into v_existing
      from public.content_items
     where workspace_id = v_ws.id
       and module = 'valvet'
       and source_template_id = v_id
       and status <> 'archived';

    if found then
        return v_existing;
    end if;

    if not v_is_pro then
        select count(*) into v_copy_count
          from app_private.valvet_catalog_copies
         where workspace_id = v_ws.id
           and created_at >= date_trunc('month', now());

        if v_copy_count >= 5 then
            raise exception 'Månadskvoten på 5 kopior är förbrukad. Uppgradera till Pro för obegränsad kopiering.';
        end if;
    end if;

    v_source_version := encode(
        extensions.digest(
            jsonb_build_object(
                'title', v_title,
                'summary', v_summary,
                'prompt_text', v_prompt_text,
                'area', v_area,
                'risk_level', v_risk_level
            )::text,
            'sha256'
        ),
        'hex'
    );

    v_slug := app_private.slugify_candidate(v_title, 'valv');
    while exists (select 1 from public.content_items where workspace_id = v_ws.id and slug = v_slug) loop
        v_slug := app_private.slugify_candidate(v_title, 'valv') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    end loop;

    perform set_config('request.jwt.claim.sub', v_ws.owner_user_id::text, true);

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, module, title, slug,
        content, category, status, visibility, source, source_content_item_id,
        source_template_id, source_version, source_copied_at
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id,
        'prompt'::public.content_item_type, 'valvet',
        v_title, v_slug, v_prompt_text, v_area,
        'draft', 'private', 'catalog_copy', null,
        v_id, v_source_version, v_copied_at
    )
    returning * into v_row;

    insert into app_private.valvet_catalog_copies (workspace_id, source_content_item_id)
    values (v_ws.id, v_id);

    return v_row;
end;
$$;

revoke all on function app_private.copy_published_prompt_to_valvet(uuid, text[]) from public;

create or replace function public.copy_published_prompt_to_valvet(
    p_prompt_id    uuid,
    p_context_keys text[] default array['generell'::text]
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.copy_published_prompt_to_valvet(p_prompt_id, p_context_keys);
$$;

revoke all on function public.copy_published_prompt_to_valvet(uuid, text[]) from public;
grant execute on function public.copy_published_prompt_to_valvet(uuid, text[]) to authenticated;
