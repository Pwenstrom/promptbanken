-- 20260815130000_library_usage_package_page_and_share_columns.sql
-- Gör package_page_view och package_share synliga i adminstatistiken.
--
-- Händelserna lagras redan (20260812090000 och 20260815120000), men
-- analys-RPC:erna räknar uttryckligen vissa event_type-värden och tar därför
-- inte med dem. Utan det här steget finns siffrorna i databasen men syns
-- ingenstans.
--
-- page_views är särskilt viktig: det är söktrafiken på de statiska
-- paketsidorna, alltså den trafik hela SEO-arbetet syftar till. Den hålls
-- åtskild från web_views (paketvyn i appen) eftersom det är två olika
-- beteenden -- att hitta sidan respektive att faktiskt öppna paketet.
--
-- Additivt: nya fält läggs sist i returtabellen, befintliga rör vi inte.
-- get_library_package_usage måste dock droppas och återskapas eftersom
-- returtabellen ändras.

drop function if exists public.get_library_package_usage(integer, integer);

create or replace function public.get_library_package_usage(p_days integer default 30, p_limit integer default 50)
returns table (
    package_slug text,
    package_title text,
    web_views integer,
    mcp_gets integer,
    package_prompt_lists integer,
    not_found integer,
    last_event_at timestamptz,
    page_views integer,
    shares integer
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
           max(e.created_at),
           count(*) filter (where e.event_type = 'package_page_view')::int,
           count(*) filter (where e.event_type = 'package_share')::int
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
