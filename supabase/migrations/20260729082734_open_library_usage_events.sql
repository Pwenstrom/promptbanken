create table if not exists public.library_usage_events (
    id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default now(),
    event_version smallint not null default 1,
    source text not null,
    event_type text not null,
    outcome text not null default 'success',
    prompt_slug text,
    package_slug text,
    context_keys text[],
    area text,
    risk_level text,
    result_count integer,
    catalog_version text,
    metadata jsonb not null default '{}'::jsonb,
    constraint library_usage_source_check
      check (source in ('web', 'open_mcp', 'admin_mcp', 'valvet', 'enterprise_mcp')),
    constraint library_usage_event_type_check
      check (event_type in (
        'prompt_view', 'prompt_copy', 'prompt_get', 'prompt_list',
        'package_view', 'package_get', 'package_list', 'package_prompts_list',
        'search', 'filter_apply', 'error'
      )),
    constraint library_usage_outcome_check
      check (outcome in ('success', 'empty', 'not_found', 'invalid_input', 'rate_limited', 'error')),
    constraint library_usage_result_count_check
      check (result_count is null or result_count >= 0),
    constraint library_usage_metadata_size_check
      check (octet_length(metadata::text) <= 2048),
    constraint library_usage_prompt_slug_len_check
      check (prompt_slug is null or length(prompt_slug) <= 120),
    constraint library_usage_package_slug_len_check
      check (package_slug is null or length(package_slug) <= 120)
);

alter table public.library_usage_events enable row level security;

drop policy if exists "library_usage_events_no_direct_read" on public.library_usage_events;
drop policy if exists "library_usage_events_no_direct_write" on public.library_usage_events;

create index if not exists library_usage_events_created_at_idx
    on public.library_usage_events (created_at desc);

create index if not exists library_usage_events_source_type_created_idx
    on public.library_usage_events (source, event_type, created_at desc);

create index if not exists library_usage_events_prompt_slug_created_idx
    on public.library_usage_events (prompt_slug, created_at desc)
    where prompt_slug is not null;

create index if not exists library_usage_events_package_slug_created_idx
    on public.library_usage_events (package_slug, created_at desc)
    where package_slug is not null;

create index if not exists library_usage_events_outcome_created_idx
    on public.library_usage_events (outcome, created_at desc)
    where outcome <> 'success';

revoke all on public.library_usage_events from public;
grant insert on public.library_usage_events to anon, authenticated;

create or replace function app_private.library_usage_allowed_metadata(p_metadata jsonb)
returns boolean
language sql
stable
set search_path = ''
as $$
    select coalesce(jsonb_typeof(p_metadata), 'object') = 'object'
       and not exists (
             select 1
               from jsonb_object_keys(coalesce(p_metadata, '{}'::jsonb)) as key(name)
              where key.name not in (
                'tool',
                'package_type',
                'copy_surface',
                'query_length',
                'filter_key',
                'filter_value'
              )
       );
$$;

revoke all on function app_private.library_usage_allowed_metadata(jsonb) from public;

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
        raise exception 'Ogiltig statistikkÃ¤lla.';
    end if;

    if p_event_type not in (
        'prompt_view', 'prompt_copy', 'prompt_get', 'prompt_list',
        'package_view', 'package_get', 'package_list', 'package_prompts_list',
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

    select case
        when p_context_keys is null then null
        else (
            select array_agg(left(trim(value), 40))
              from unnest(p_context_keys) as value
             where trim(value) <> ''
             limit 10
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
        nullif(left(trim(coalesce(p_prompt_slug, '')), 120), ''),
        nullif(left(trim(coalesce(p_package_slug, '')), 120), ''),
        v_context_keys,
        nullif(left(trim(coalesce(p_area, '')), 80), ''),
        nullif(left(trim(coalesce(p_risk_level, '')), 40), ''),
        p_result_count,
        nullif(left(trim(coalesce(p_catalog_version, '')), 80), ''),
        v_metadata
    );

    return jsonb_build_object('accepted', true);
end;
$$;

revoke all on function public.track_library_usage_event(
    text, text, text, text, text, text[], text, text, integer, text, jsonb
) from public;
grant execute on function public.track_library_usage_event(
    text, text, text, text, text, text[], text, text, integer, text, jsonb
) to anon, authenticated;

create or replace function public.get_library_usage_summary(p_days integer default 30)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
    v_since timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 365)));
    v_result jsonb;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsÃ¤gare kan lÃ¤sa biblioteksstatistik.';
    end if;

    select jsonb_build_object(
        'days', v_days,
        'totals', coalesce((
            select jsonb_object_agg(source, total)
              from (
                select source, count(*)::int as total
                  from public.library_usage_events
                 where created_at >= v_since
                 group by source
              ) s
        ), '{}'::jsonb),
        'metrics', jsonb_build_object(
            'web_prompt_views', count(*) filter (where source = 'web' and event_type = 'prompt_view'),
            'web_prompt_copies', count(*) filter (where source = 'web' and event_type = 'prompt_copy'),
            'mcp_prompt_gets', count(*) filter (where source = 'open_mcp' and event_type = 'prompt_get'),
            'package_activity', count(*) filter (where event_type in ('package_view', 'package_get', 'package_list', 'package_prompts_list')),
            'searches_empty', count(*) filter (where event_type = 'search' and outcome = 'empty'),
            'errors_or_not_found', count(*) filter (where outcome in ('not_found', 'error'))
        ),
        'daily', coalesce((
            select jsonb_agg(row_to_json(d) order by d.day)
              from (
                select date_trunc('day', created_at)::date as day,
                       source,
                       count(*)::int as events
                  from public.library_usage_events
                 where created_at >= v_since
                 group by 1, 2
                 order by 1, 2
              ) d
        ), '[]'::jsonb),
        'last_open_mcp_success_at', (
            select max(created_at)
              from public.library_usage_events
             where source = 'open_mcp'
               and outcome = 'success'
        )
    )
    into v_result
    from public.library_usage_events
    where created_at >= v_since;

    return coalesce(v_result, jsonb_build_object('days', v_days, 'totals', '{}'::jsonb, 'metrics', '{}'::jsonb, 'daily', '[]'::jsonb));
end;
$$;

revoke all on function public.get_library_usage_summary(integer) from public;
grant execute on function public.get_library_usage_summary(integer) to authenticated;

create or replace function public.get_library_prompt_usage(p_days integer default 30, p_limit integer default 50)
returns table (
    prompt_slug text,
    web_views integer,
    web_copies integer,
    mcp_gets integer,
    not_found integer,
    last_event_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
    v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsÃ¤gare kan lÃ¤sa biblioteksstatistik.';
    end if;

    return query
    select e.prompt_slug,
           count(*) filter (where e.source = 'web' and e.event_type = 'prompt_view')::int as web_views,
           count(*) filter (where e.source = 'web' and e.event_type = 'prompt_copy')::int as web_copies,
           count(*) filter (where e.source = 'open_mcp' and e.event_type = 'prompt_get')::int as mcp_gets,
           count(*) filter (where e.outcome = 'not_found')::int as not_found,
           max(e.created_at) as last_event_at
      from public.library_usage_events e
     where e.created_at >= now() - make_interval(days => v_days)
       and e.prompt_slug is not null
     group by e.prompt_slug
     order by (count(*) filter (where e.event_type in ('prompt_copy', 'prompt_get'))) desc,
              count(*) desc
     limit v_limit;
end;
$$;

revoke all on function public.get_library_prompt_usage(integer, integer) from public;
grant execute on function public.get_library_prompt_usage(integer, integer) to authenticated;

create or replace function public.get_library_package_usage(p_days integer default 30, p_limit integer default 50)
returns table (
    package_slug text,
    web_views integer,
    mcp_gets integer,
    package_prompt_lists integer,
    not_found integer,
    last_event_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
    v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsÃ¤gare kan lÃ¤sa biblioteksstatistik.';
    end if;

    return query
    select e.package_slug,
           count(*) filter (where e.source = 'web' and e.event_type = 'package_view')::int,
           count(*) filter (where e.source = 'open_mcp' and e.event_type = 'package_get')::int,
           count(*) filter (where e.source = 'open_mcp' and e.event_type = 'package_prompts_list')::int,
           count(*) filter (where e.outcome = 'not_found')::int,
           max(e.created_at)
      from public.library_usage_events e
     where e.created_at >= now() - make_interval(days => v_days)
       and e.package_slug is not null
     group by e.package_slug
     order by count(*) desc
     limit v_limit;
end;
$$;

revoke all on function public.get_library_package_usage(integer, integer) from public;
grant execute on function public.get_library_package_usage(integer, integer) to authenticated;

create or replace function public.get_library_usage_errors(p_days integer default 30, p_limit integer default 50)
returns table (
    source text,
    event_type text,
    outcome text,
    prompt_slug text,
    package_slug text,
    count integer,
    last_event_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
    v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsÃ¤gare kan lÃ¤sa biblioteksstatistik.';
    end if;

    return query
    select e.source, e.event_type, e.outcome, e.prompt_slug, e.package_slug,
           count(*)::int, max(e.created_at)
      from public.library_usage_events e
     where e.created_at >= now() - make_interval(days => v_days)
       and e.outcome in ('empty', 'not_found', 'invalid_input', 'rate_limited', 'error')
     group by e.source, e.event_type, e.outcome, e.prompt_slug, e.package_slug
     order by count(*) desc, max(e.created_at) desc
     limit v_limit;
end;
$$;

revoke all on function public.get_library_usage_errors(integer, integer) from public;
grant execute on function public.get_library_usage_errors(integer, integer) to authenticated;

create or replace function public.get_library_search_feedback(p_days integer default 30, p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsÃ¤gare kan lÃ¤sa biblioteksstatistik.';
    end if;

    return jsonb_build_object(
        'days', v_days,
        'searches', (
            select count(*)::int
              from public.library_usage_events
             where created_at >= now() - make_interval(days => v_days)
               and event_type = 'search'
        ),
        'empty_searches', (
            select count(*)::int
              from public.library_usage_events
             where created_at >= now() - make_interval(days => v_days)
               and event_type = 'search'
               and outcome = 'empty'
        ),
        'by_context', coalesce((
            select jsonb_agg(row_to_json(c) order by c.empty_count desc)
              from (
                select coalesce(array_to_string(context_keys, ','), '-') as context_key,
                       count(*) filter (where outcome = 'empty')::int as empty_count,
                       count(*)::int as total_count
                  from public.library_usage_events
                 where created_at >= now() - make_interval(days => v_days)
                   and event_type = 'search'
                 group by 1
                 limit greatest(1, least(coalesce(p_limit, 50), 200))
              ) c
        ), '[]'::jsonb)
    );
end;
$$;

revoke all on function public.get_library_search_feedback(integer, integer) from public;
grant execute on function public.get_library_search_feedback(integer, integer) to authenticated;
