-- 20260725120000_seed_catalog_from_existing_templates.sql
-- Seedar den nya katalogplattformen från befintliga pro_prompt_templates och
-- deras sju områden. Syftet är att öppna katalogens read-RPC:er med verkligt
-- innehåll direkt, utan manuell handpåläggning per post.
--
-- Seedningen är idempotent:
-- - katalogprompts/paket identifieras via stabila sluggar
-- - varianter läggs bara till om de saknas
-- - befintliga manuella redaktionella ändringar skrivs inte över

with package_seed as (
    select *
    from (
        values
            (
                'kommunikation',
                'Kommunikation och publicering',
                'collection',
                'message',
                'blue',
                'Samlade mallar för kommunikation, publicering och målgruppsanpassning.',
                'Mallar för att skriva, granska och paketera information för olika målgrupper.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'forandringsledning',
                'Förändringsledning och införande',
                'collection',
                'sparkles',
                'amber',
                'Samlade mallar för införande, förankring och förändringsarbete.',
                'Mallar för att planera, förankra, testa och följa upp förändringar i en verksamhet.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'processer',
                'Verksamhetsutveckling och processer',
                'collection',
                'list',
                'teal',
                'Samlade mallar för rutiner, processer och strukturerat förbättringsarbete.',
                'Mallar för att beskriva nuläge, ansvar, flöden och återkommande arbetssätt.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'beslutsberedning',
                'Tjänstemannastöd och beslutsberedning',
                'collection',
                'clipboard',
                'slate',
                'Samlade mallar för beslutsunderlag, konsekvensanalys och genomförandeplanering.',
                'Mallar för att bedöma beslutsmognad, alternativ och risker inför formella beslut.',
                array['generell', 'kommun', 'skola', 'förening']::text[]
            ),
            (
                'visuellt',
                'Visuellt stöd och informationsbilder',
                'collection',
                'image',
                'orange',
                'Samlade mallar för infografik, bildidéer och tillgängliga visuella förklaringar.',
                'Mallar för att göra information begriplig i bild, ikon, alt-text eller visuell struktur.',
                array['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']::text[]
            ),
            (
                'ledarskap',
                'Ledarskap och styrning',
                'collection',
                'users',
                'green',
                'Samlade mallar för ledning, prioritering och uppföljning.',
                'Mallar för att förtydliga uppdrag, förbereda samtal och skapa lägesbilder eller uppföljning.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'arbetsbank',
                'Egen AI-arbetsbank',
                'collection',
                'library',
                'indigo',
                'Samlade mallar för att bygga, förbättra och kvalitetssäkra egna AI-mallar.',
                'Meta-mallar för att utveckla egna prompts och arbetsflöden oavsett verksamhet.',
                array['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']::text[]
            )
    ) as p (
        area,
        package_title,
        package_type,
        icon_key,
        color_theme,
        package_summary,
        intro_text,
        context_keys
    )
),
template_seed as (
    select
        t.id as template_id,
        t.area,
        t.area_label,
        t.title,
        t.syfte,
        t.output_format,
        t.prompt_text,
        t.tags,
        t.sort_order,
        'legacy-' || t.area || '-' || lpad(t.sort_order::text, 2, '0') as slug,
        case
            when t.title = 'Svårt medborgarsvar' then array['generell', 'kommun']::text[]
            when t.title in ('Kommunikationspaket', 'Kommunikationsrisk', 'Målgruppsväxlare', 'Driftstörningsinformation', 'Publiceringscheck') then
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            when t.area = 'forandringsledning' then
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            when t.area = 'processer' then
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            when t.area = 'beslutsberedning' then
                array['generell', 'kommun', 'skola', 'förening']::text[]
            when t.area = 'visuellt' then
                array['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']::text[]
            when t.area = 'ledarskap' then
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            when t.area = 'arbetsbank' then
                array['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']::text[]
            else array['generell', 'kommun']::text[]
        end as context_keys,
        case t.area
            when 'kommunikation' then 'message'
            when 'forandringsledning' then 'sparkles'
            when 'processer' then 'list'
            when 'beslutsberedning' then 'clipboard'
            when 'visuellt' then 'image'
            when 'ledarskap' then 'users'
            when 'arbetsbank' then 'library'
            else null
        end as icon_key,
        case t.area
            when 'kommunikation' then 'blue'
            when 'forandringsledning' then 'amber'
            when 'processer' then 'teal'
            when 'beslutsberedning' then 'slate'
            when 'visuellt' then 'orange'
            when 'ledarskap' then 'green'
            when 'arbetsbank' then 'indigo'
            else null
        end as color_theme
    from public.pro_prompt_templates t
),
insert_prompts as (
    insert into public.catalog_prompts (
        slug,
        status,
        prompt_kind,
        icon_key,
        color_theme
    )
    select
        s.slug,
        'published',
        'prompt',
        s.icon_key,
        s.color_theme
    from template_seed s
    on conflict (slug) do update
        set status = excluded.status
    returning id, slug
),
prompt_lookup as (
    select cp.id, s.*
    from template_seed s
    join public.catalog_prompts cp on cp.slug = s.slug
),
insert_prompt_variants as (
    insert into public.catalog_prompt_variants (
        prompt_id,
        context_key,
        title,
        summary,
        prompt_text,
        audience_label,
        tone_hint
    )
    select
        p.id,
        ctx.context_key,
        p.title,
        p.syfte,
        p.prompt_text,
        p.area_label,
        p.output_format
    from prompt_lookup p
    cross join lateral unnest(p.context_keys) as ctx(context_key)
    on conflict (prompt_id, context_key) do nothing
    returning prompt_id
),
insert_packages as (
    insert into public.catalog_packages (
        slug,
        status,
        package_type,
        icon_key,
        color_theme
    )
    select
        ps.area,
        'published',
        ps.package_type,
        ps.icon_key,
        ps.color_theme
    from package_seed ps
    on conflict (slug) do update
        set status = excluded.status
    returning id, slug
),
package_lookup as (
    select cpkg.id, ps.*
    from package_seed ps
    join public.catalog_packages cpkg on cpkg.slug = ps.area
),
insert_package_variants as (
    insert into public.catalog_package_variants (
        package_id,
        context_key,
        title,
        summary,
        intro_text,
        audience_label
    )
    select
        p.id,
        ctx.context_key,
        p.package_title,
        p.package_summary,
        p.intro_text,
        p.package_title
    from package_lookup p
    cross join lateral unnest(p.context_keys) as ctx(context_key)
    on conflict (package_id, context_key) do nothing
    returning package_id
)
insert into public.catalog_package_items (
    package_id,
    prompt_id,
    sort_order,
    step_title,
    step_intro,
    is_required
)
select
    cpkg.id,
    cp.id,
    s.sort_order,
    s.title,
    s.syfte,
    true
from template_seed s
join public.catalog_packages cpkg
  on cpkg.slug = s.area
join public.catalog_prompts cp
  on cp.slug = s.slug
on conflict (package_id, prompt_id) do nothing;
