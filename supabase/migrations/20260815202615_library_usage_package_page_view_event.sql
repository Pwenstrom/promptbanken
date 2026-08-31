-- 20260815120000_library_usage_package_page_view_event.sql
-- Lägger till 'package_page_view' som tillåtet event_type.
--
-- De statiska paketsidorna (/paket/<slug>/) är ren HTML utan appens
-- JavaScript, så en besökare som kommer från sökmotor och läser sidan utan
-- att klicka vidare in i appen syns i dag ingenstans i statistiken. Det är
-- en blind fläck som växer i takt med att SEO-arbetet fungerar.
--
-- Egen händelsetyp i stället för att återanvända 'package_view': annars går
-- det inte att skilja söktrafik på den statiska sidan från faktisk
-- paketanvändning i appen, och båda siffrorna blir svårtolkade.
--
-- Samma anonymitetsnivå som övriga händelser: ingen personuppgift, ingen
-- cookie, ingen identifierare — bara paketets slug och en tidsstämpel.

alter table public.library_usage_events
    drop constraint if exists library_usage_event_type_check;

alter table public.library_usage_events
    add constraint library_usage_event_type_check
      check (event_type in (
        'prompt_view', 'prompt_copy', 'prompt_get', 'prompt_list',
        'package_view', 'package_get', 'package_list', 'package_prompts_list',
        'package_share', 'package_page_view',
        'search', 'filter_apply', 'error'
      ));

create or replace function public.track_library_usage_event(
    p_source text,
    p_event_type text,
    p_outcome text default 'success',
    p_prompt_slug text default null,
    p_package_slug text default null,
    p_context_keys text[] default null,
    p_area text default null,
    p_risk_level text default null,
    p_result_count integer default null,
    p_catalog_version text default null,
    p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
    v_context_keys text[];
begin
    if p_source not in ('web', 'open_mcp') then
        raise exception 'Ogiltig statistikkälla.';
    end if;

    if p_event_type not in (
        'prompt_view', 'prompt_copy', 'prompt_get', 'prompt_list',
        'package_view', 'package_get', 'package_list', 'package_prompts_list',
        'package_share', 'package_page_view',
        'search', 'filter_apply', 'error'
    ) then
        raise exception 'Ogiltig statistiktyp.';
    end if;

    if coalesce(p_outcome, 'success') not in ('success', 'empty', 'not_found', 'invalid_input', 'rate_limited', 'error') then
        raise exception 'Ogiltigt statistikutfall.';
    end if;

    if jsonb_typeof(v_metadata) <> 'object' or not app_private.library_usage_allowed_metadata(v_metadata) then
        raise exception 'Ogiltig statistikmetadata.';
    end if;

    if not app_private.library_usage_safe_slug(nullif(trim(coalesce(p_prompt_slug, '')), ''), 120)
       or not app_private.library_usage_safe_slug(nullif(trim(coalesce(p_package_slug, '')), ''), 120) then
        raise exception 'Ogiltig katalogslug.';
    end if;

    if p_area is not null and trim(p_area) not in (
        'kommunikation', 'forandringsledning', 'processer', 'beslutsberedning',
        'visuellt', 'ledarskap', 'arbetsbank',
        'Skriva och förbättra text', 'Svara och kommunicera',
        'Sammanfatta och strukturera', 'Möten och workshops',
        'Beslut och rutiner', 'Bilder och infografik'
    ) then
        raise exception 'Ogiltigt statistikområde.';
    end if;

    if p_risk_level is not null and trim(p_risk_level) not in (
        'low', 'medium', 'high', 'Låg risk', 'Medelrisk', 'Hög risk'
    ) then
        raise exception 'Ogiltig risknivå.';
    end if;

    if p_catalog_version is not null
       and trim(p_catalog_version) !~ '^[0-9]{1,10}$' then
        raise exception 'Ogiltig katalogversion.';
    end if;

    if exists (
        select 1
          from unnest(coalesce(p_context_keys, '{}'::text[])) as values(value)
         where trim(value) <> ''
           and trim(value) not in ('generell', 'kommun', 'skola', 'företag', 'förening', 'privat')
    ) then
        raise exception 'Ogiltig statistikkontext.';
    end if;

    select case
        when p_context_keys is null then null
        else (
            select array_agg(left(trim(limited.value), 40) order by limited.ordinality)
              from (
                select value, ordinality
                  from unnest(p_context_keys) with ordinality as values(value, ordinality)
                 where trim(value) <> ''
                 limit 10
              ) as limited
        )
    end into v_context_keys;

    insert into public.library_usage_events (
        source,
        event_type,
        outcome,
        prompt_slug,
        package_slug,
        context_keys,
        area,
        risk_level,
        result_count,
        catalog_version,
        metadata
    ) values (
        p_source,
        p_event_type,
        coalesce(p_outcome, 'success'),
        nullif(trim(coalesce(p_prompt_slug, '')), ''),
        nullif(trim(coalesce(p_package_slug, '')), ''),
        v_context_keys,
        nullif(trim(coalesce(p_area, '')), ''),
        nullif(trim(coalesce(p_risk_level, '')), ''),
        p_result_count,
        nullif(trim(coalesce(p_catalog_version, '')), ''),
        v_metadata
    );

    return jsonb_build_object('accepted', true);
end;
$$;

grant execute on function public.track_library_usage_event(
    text, text, text, text, text, text[], text, text, integer, text, jsonb
) to anon, authenticated;
