-- 20260725123000_backfill_catalog_variants_and_items.sql
-- Backfyller katalogvarianter och paketinnehåll för seedade legacy-poster.
-- Behövs som uppföljning till 20260725120000 då prompt/paket-raderna skapades
-- men varianter och package_items inte persisterades i produktion.

with package_seed as (
    select *
    from (
        values
            (
                'kommunikation',
                'Kommunikation och publicering',
                'Samlade mallar för kommunikation, publicering och målgruppsanpassning.',
                'Mallar för att skriva, granska och paketera information för olika målgrupper.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'forandringsledning',
                'Förändringsledning och införande',
                'Samlade mallar för införande, förankring och förändringsarbete.',
                'Mallar för att planera, förankra, testa och följa upp förändringar i en verksamhet.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'processer',
                'Verksamhetsutveckling och processer',
                'Samlade mallar för rutiner, processer och strukturerat förbättringsarbete.',
                'Mallar för att beskriva nuläge, ansvar, flöden och återkommande arbetssätt.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'beslutsberedning',
                'Tjänstemannastöd och beslutsberedning',
                'Samlade mallar för beslutsunderlag, konsekvensanalys och genomförandeplanering.',
                'Mallar för att bedöma beslutsmognad, alternativ och risker inför formella beslut.',
                array['generell', 'kommun', 'skola', 'förening']::text[]
            ),
            (
                'visuellt',
                'Visuellt stöd och informationsbilder',
                'Samlade mallar för infografik, bildidéer och tillgängliga visuella förklaringar.',
                'Mallar för att göra information begriplig i bild, ikon, alt-text eller visuell struktur.',
                array['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']::text[]
            ),
            (
                'ledarskap',
                'Ledarskap och styrning',
                'Samlade mallar för ledning, prioritering och uppföljning.',
                'Mallar för att förtydliga uppdrag, förbereda samtal och skapa lägesbilder eller uppföljning.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'arbetsbank',
                'Egen AI-arbetsbank',
                'Samlade mallar för att bygga, förbättra och kvalitetssäkra egna AI-mallar.',
                'Meta-mallar för att utveckla egna prompts och arbetsflöden oavsett verksamhet.',
                array['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']::text[]
            )
    ) as p (
        area,
        package_title,
        package_summary,
        intro_text,
        context_keys
    )
),
template_seed as (
    select
        t.area,
        t.area_label,
        t.title,
        t.syfte,
        t.output_format,
        t.prompt_text,
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
        end as context_keys
    from public.pro_prompt_templates t
)
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
    cp.id,
    ctx.context_key,
    ts.title,
    ts.syfte,
    ts.prompt_text,
    ts.area_label,
    ts.output_format
from template_seed ts
join public.catalog_prompts cp on cp.slug = ts.slug
cross join lateral unnest(ts.context_keys) as ctx(context_key)
on conflict (prompt_id, context_key) do nothing;

with package_seed as (
    select *
    from (
        values
            (
                'kommunikation',
                'Kommunikation och publicering',
                'Samlade mallar för kommunikation, publicering och målgruppsanpassning.',
                'Mallar för att skriva, granska och paketera information för olika målgrupper.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'forandringsledning',
                'Förändringsledning och införande',
                'Samlade mallar för införande, förankring och förändringsarbete.',
                'Mallar för att planera, förankra, testa och följa upp förändringar i en verksamhet.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'processer',
                'Verksamhetsutveckling och processer',
                'Samlade mallar för rutiner, processer och strukturerat förbättringsarbete.',
                'Mallar för att beskriva nuläge, ansvar, flöden och återkommande arbetssätt.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'beslutsberedning',
                'Tjänstemannastöd och beslutsberedning',
                'Samlade mallar för beslutsunderlag, konsekvensanalys och genomförandeplanering.',
                'Mallar för att bedöma beslutsmognad, alternativ och risker inför formella beslut.',
                array['generell', 'kommun', 'skola', 'förening']::text[]
            ),
            (
                'visuellt',
                'Visuellt stöd och informationsbilder',
                'Samlade mallar för infografik, bildidéer och tillgängliga visuella förklaringar.',
                'Mallar för att göra information begriplig i bild, ikon, alt-text eller visuell struktur.',
                array['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']::text[]
            ),
            (
                'ledarskap',
                'Ledarskap och styrning',
                'Samlade mallar för ledning, prioritering och uppföljning.',
                'Mallar för att förtydliga uppdrag, förbereda samtal och skapa lägesbilder eller uppföljning.',
                array['generell', 'kommun', 'skola', 'företag', 'förening']::text[]
            ),
            (
                'arbetsbank',
                'Egen AI-arbetsbank',
                'Samlade mallar för att bygga, förbättra och kvalitetssäkra egna AI-mallar.',
                'Meta-mallar för att utveckla egna prompts och arbetsflöden oavsett verksamhet.',
                array['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']::text[]
            )
    ) as p (
        area,
        package_title,
        package_summary,
        intro_text,
        context_keys
    )
)
insert into public.catalog_package_variants (
    package_id,
    context_key,
    title,
    summary,
    intro_text,
    audience_label
)
select
    cpkg.id,
    ctx.context_key,
    ps.package_title,
    ps.package_summary,
    ps.intro_text,
    ps.package_title
from package_seed ps
join public.catalog_packages cpkg on cpkg.slug = ps.area
cross join lateral unnest(ps.context_keys) as ctx(context_key)
on conflict (package_id, context_key) do nothing;

with template_seed as (
    select
        t.area,
        t.title,
        t.syfte,
        t.sort_order,
        'legacy-' || t.area || '-' || lpad(t.sort_order::text, 2, '0') as slug
    from public.pro_prompt_templates t
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
    ts.sort_order,
    ts.title,
    ts.syfte,
    true
from template_seed ts
join public.catalog_packages cpkg on cpkg.slug = ts.area
join public.catalog_prompts cp on cp.slug = ts.slug
on conflict (package_id, prompt_id) do nothing;
