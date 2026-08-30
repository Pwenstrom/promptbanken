-- 20260802110000_get_catalog_prompt_by_id_audience_tone.sql
-- get_catalog_prompt_by_id (app_private + public) saknade audience_label
-- och tone_hint i sin retur-typ, trots att upsert_catalog_prompt_variant
-- redan kunde skriva dem (20260802100000_catalog_security_examples.sql).
-- Admin-MCP:s admin_get_prompt kunde därför aldrig verifiera de fälten
-- efter skrivning. Retur-typen ändras så funktionerna måste droppas
-- innan de skapas om.

drop function if exists public.get_catalog_prompt_by_id(uuid);
drop function if exists app_private.get_catalog_prompt_by_id(uuid);
create or replace function app_private.get_catalog_prompt_by_id(p_prompt_id uuid)
returns table (
    id uuid,
    slug text,
    status text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    audience_label text,
    tone_hint text,
    risk_level text,
    area text,
    tags text[],
    output_format text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    security_examples text[]
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa en katalogprompt.';
    end if;

    return query
    select cp.id, cp.slug, cp.status, v.context_key, v.title, v.summary, v.prompt_text,
           v.audience_label, v.tone_hint,
           v.risk_level, v.area, v.tags, v.output_format,
           v.parameter_schema, v.default_bindings, v.binding_overrides, v.security_examples
      from public.catalog_prompts cp
      join public.catalog_prompt_variants v on v.prompt_id = cp.id
     where cp.id = p_prompt_id
     order by case when v.context_key = 'generell' then 0 else 1 end;
end;
$$;
create or replace function public.get_catalog_prompt_by_id(p_prompt_id uuid)
returns table (
    id uuid,
    slug text,
    status text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    audience_label text,
    tone_hint text,
    risk_level text,
    area text,
    tags text[],
    output_format text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    security_examples text[]
)
language sql
security definer
set search_path = 'public', 'app_private', 'pg_temp'
as $$
    select * from app_private.get_catalog_prompt_by_id(p_prompt_id);
$$;
revoke all on function public.get_catalog_prompt_by_id(uuid) from public;
grant execute on function public.get_catalog_prompt_by_id(uuid) to authenticated;
