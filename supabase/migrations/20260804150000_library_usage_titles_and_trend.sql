-- supabase/migrations/20260804150000_library_usage_titles_and_trend.sql
-- Adds human-readable titles to the prompt/package/error usage RPCs by
-- joining catalog_prompts/catalog_packages + their variants. Titles are
-- null when the slug no longer resolves to a catalog item
-- (renamed or deleted) — the frontend renders a "(borttagen — <slug>)"
-- fallback rather than the RPC guessing.
--
-- The three functions below change their RETURNS TABLE column list, which
-- Postgres does not allow via CREATE OR REPLACE (42P13: cannot change
-- return type of existing function) — each is dropped first.

drop function if exists public.get_library_prompt_usage(integer, integer);
drop function if exists public.get_library_package_usage(integer, integer);
drop function if exists public.get_library_usage_errors(integer, integer);

create or replace function public.get_library_prompt_usage(p_days integer default 30, p_limit integer default 50)
returns table (
    prompt_slug text,
    prompt_title text,
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
        raise exception 'Endast plattformsägare kan läsa biblioteksstatistik.';
    end if;

    return query
    select e.prompt_slug,
           title.title as prompt_title,
           count(*) filter (where e.source = 'web' and e.event_type = 'prompt_view')::int as web_views,
           count(*) filter (where e.source = 'web' and e.event_type = 'prompt_copy')::int as web_copies,
           count(*) filter (where e.source = 'open_mcp' and e.event_type = 'prompt_get')::int as mcp_gets,
           count(*) filter (where e.outcome = 'not_found')::int as not_found,
           max(e.created_at) as last_event_at
      from public.library_usage_events e
      left join public.catalog_prompts cp on cp.slug = e.prompt_slug
      left join lateral (
        select v.title
          from public.catalog_prompt_variants v
         where v.prompt_id = cp.id
         order by (v.context_key = 'generell') desc, v.created_at asc
         limit 1
      ) title on true
     where e.created_at >= now() - make_interval(days => v_days)
       and e.prompt_slug is not null
     group by e.prompt_slug, title.title
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
    package_title text,
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
        raise exception 'Endast plattformsägare kan läsa biblioteksstatistik.';
    end if;

    return query
    select e.package_slug,
           title.title as package_title,
           count(*) filter (where e.source = 'web' and e.event_type = 'package_view')::int,
           count(*) filter (where e.source = 'open_mcp' and e.event_type = 'package_get')::int,
           count(*) filter (where e.source = 'open_mcp' and e.event_type = 'package_prompts_list')::int,
           count(*) filter (where e.outcome = 'not_found')::int,
           max(e.created_at)
      from public.library_usage_events e
      left join public.catalog_packages cpk on cpk.slug = e.package_slug
      left join lateral (
        select v.title
          from public.catalog_package_variants v
         where v.package_id = cpk.id
         order by (v.context_key = 'generell') desc, v.created_at asc
         limit 1
      ) title on true
     where e.created_at >= now() - make_interval(days => v_days)
       and e.package_slug is not null
     group by e.package_slug, title.title
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
    prompt_title text,
    package_slug text,
    package_title text,
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
        raise exception 'Endast plattformsägare kan läsa biblioteksstatistik.';
    end if;

    return query
    select e.source, e.event_type, e.outcome, e.prompt_slug,
           pt.title as prompt_title,
           e.package_slug,
           pkt.title as package_title,
           count(*)::int, max(e.created_at)
      from public.library_usage_events e
      left join public.catalog_prompts cp on cp.slug = e.prompt_slug
      left join lateral (
        select v.title
          from public.catalog_prompt_variants v
         where v.prompt_id = cp.id
         order by (v.context_key = 'generell') desc, v.created_at asc
         limit 1
      ) pt on true
      left join public.catalog_packages cpk on cpk.slug = e.package_slug
      left join lateral (
        select v.title
          from public.catalog_package_variants v
         where v.package_id = cpk.id
         order by (v.context_key = 'generell') desc, v.created_at asc
         limit 1
      ) pkt on true
     where e.created_at >= now() - make_interval(days => v_days)
       and e.outcome in ('empty', 'not_found', 'invalid_input', 'rate_limited', 'error')
     group by e.source, e.event_type, e.outcome, e.prompt_slug, pt.title, e.package_slug, pkt.title
     order by count(*) desc, max(e.created_at) desc
     limit v_limit;
end;
$$;

revoke all on function public.get_library_usage_errors(integer, integer) from public;
grant execute on function public.get_library_usage_errors(integer, integer) to authenticated;
