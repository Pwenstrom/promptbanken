-- Gör listvyerna renderingsbara med samma metadata som detaljvyerna och
-- rättar verifierade språk- och integritetsproblem i kataloginnehållet.

drop function if exists public.list_published_prompts(text[]);

create function public.list_published_prompts(
    p_context_keys text[] default array['generell']
)
returns table (
    id uuid,
    slug text,
    icon_key text,
    image_key text,
    color_theme text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cp.id,
        cp.slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        coalesce(matched.context_key, fallback.context_key) as context_key,
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(matched.example_input, fallback.example_input) as example_input,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label,
        coalesce(matched.tone_hint, fallback.tone_hint) as tone_hint,
        coalesce(matched.parameter_schema, fallback.parameter_schema) as parameter_schema,
        coalesce(matched.default_bindings, fallback.default_bindings, '{}'::jsonb) as default_bindings,
        coalesce(matched.binding_overrides, fallback.binding_overrides, '[]'::jsonb) as binding_overrides
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
    where cp.status = 'published'
    order by cp.slug;
$$;

revoke all on function public.list_published_prompts(text[]) from public;
grant execute on function public.list_published_prompts(text[]) to anon, authenticated;

drop function if exists public.list_published_package_prompts(text, text[]);

create function public.list_published_package_prompts(
    p_package_slug text,
    p_context_keys text[] default array['generell']
)
returns table (
    prompt_id uuid,
    prompt_slug text,
    icon_key text,
    image_key text,
    color_theme text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    sort_order integer,
    step_title text,
    step_intro text,
    is_required boolean
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cp.id as prompt_id,
        cp.slug as prompt_slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        coalesce(matched.context_key, fallback.context_key) as context_key,
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(matched.example_input, fallback.example_input) as example_input,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label,
        coalesce(matched.tone_hint, fallback.tone_hint) as tone_hint,
        coalesce(matched.parameter_schema, fallback.parameter_schema) as parameter_schema,
        coalesce(matched.default_bindings, fallback.default_bindings, '{}'::jsonb) as default_bindings,
        coalesce(matched.binding_overrides, fallback.binding_overrides, '[]'::jsonb) as binding_overrides,
        cpi.sort_order,
        cpi.step_title,
        cpi.step_intro,
        cpi.is_required
    from public.catalog_packages cpkg
    join public.catalog_package_items cpi on cpi.package_id = cpkg.id
    join public.catalog_prompts cp on cp.id = cpi.prompt_id
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
    where cpkg.status = 'published'
      and cpkg.slug = p_package_slug
      and cp.status = 'published'
    order by cpi.sort_order;
$$;

revoke all on function public.list_published_package_prompts(text, text[]) from public;
grant execute on function public.list_published_package_prompts(text, text[]) to anon, authenticated;

update public.catalog_prompt_variants variant
set prompt_text = replace(
    replace(variant.prompt_text, 'VAD MAN SKA FÖRBERED.', 'VAD MAN SKA FÖRBEREDA.'),
    'KALLELSE TIL BUDGETMÖTE',
    'KALLELSE TILL BUDGETMÖTE'
)
from public.catalog_prompts prompt
where prompt.id = variant.prompt_id
  and prompt.slug = 'kallelse';

update public.catalog_prompt_variants variant
set prompt_text = replace(
    variant.prompt_text,
    '   ⚠️ Skriv personnummer utan bindestreck',
    '   Kontrollera att ärendenumret är korrekt'
)
from public.catalog_prompts prompt
where prompt.id = variant.prompt_id
  and prompt.slug = 'rutin';

update public.catalog_prompt_variants variant
set prompt_text = replace(
    variant.prompt_text,
    '1. Använd korta meningar (8–12 ord per mening)',
    '1. Sikta på korta meningar, ofta omkring 8–12 ord, men variera när tydligheten kräver det'
)
from public.catalog_prompts prompt
where prompt.id = variant.prompt_id
  and prompt.slug = 'klarsprak';

update public.catalog_prompt_variants variant
set prompt_text = replace(
    variant.prompt_text,
    '- Använd: juridiska termer, "avses", "verksamheten", passiv form',
    '- Använd korrekta facktermer när de behövs, aktiv form och sakligt klarspråk'
)
from public.catalog_prompts prompt
where prompt.id = variant.prompt_id
  and prompt.slug = 'tvaversioner';
