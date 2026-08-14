# Statiska paketsidor och paketförst-IA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Varje publicerat promptpaket får en indexerbar statisk sida på `/paket/<slug>/`, genererad vid build från Supabase, plus en `/paket/`-översikt, genererad sitemap och paketförst-navigation i katalogen.

**Architecture:** Statisk multipage-site (Vite → GitHub Pages). Ett nytt Node-script körs efter `vite build` och skriver HTML-filer till `dist/` genom att läsa publicerat katalogdata via befintliga publika Supabase-RPC:er med anon-nyckeln. En additiv migration lägger till redaktionella fält. Ingen server, ingen SSR, inga nya hemligheter.

**Tech Stack:** Node 20 (ESM, `node --test`), Vite 7, `@supabase/supabase-js` 2.84 (redan dependency), Supabase Postgres, GitHub Actions.

## Global Constraints

- Designspec: `docs/superpowers/specs/2026-08-15-statiska-paketsidor-seo-design.md`. Vid konflikt mellan plan och spec — fråga, ändra inte tyst.
- `script.js` är inte bundlad av Vite och får inte ha `import`-satser.
- Alla migrationer är **additiva**: nya nullable-kolumner, nya fält sist i RPC:ers returtabell. Inga borttagna eller omdöpta fält, inga ändrade parameterlistor. Den separata MCP-servern (`mcp_promptbanken`) läser samma RPC:er och får inte gå sönder.
- Migrationer appliceras **inte** mot produktion av en implementerande agent. Skapa filen, verifiera resonemanget, rapportera att prod-körning återstår.
- All text från databasen escapas innan den skrivs till HTML.
- Alla slugs valideras mot mönstret `/^[a-z0-9]+(?:-[a-z0-9]+)*$/` innan de används i filsökvägar eller URL:er.
- Kanonisk bas-URL: `https://app.promptbanken.se`.
- Svensk text i allt användarsynligt gränssnitt.
- Efter varje kodändring: `npm run build` ska lyckas.

---

### Task 1: Migration — redaktionella fält och utökade läs-RPC:er

**Files:**
- Create: `supabase/migrations/20260815090000_catalog_package_seo_fields.sql`
- Create: `supabase/tests/verify_catalog_package_seo_fields.sql`
- Reference (läs, ändra inte): `supabase/migrations/20260725100000_catalog_read_context_arrays.sql` (innehåller nuvarande `list_published_packages`)
- Reference (läs, ändra inte): `supabase/migrations/20260725133000_catalog_parameter_schemas.sql` (innehåller nuvarande `get_published_package`)

**Interfaces:**
- Produces: kolumnerna `problem_text`, `when_to_use`, `outcome_text` på `public.catalog_package_variants`; `area`, `tags`, `is_indexable` på `public.catalog_packages`. RPC:erna `public.list_published_packages(text[], text)` och `public.get_published_package(text, text[])` returnerar dessa fält **sist** i sin returtabell, med oförändrade parameterlistor. Task 3 och Task 8 konsumerar dem.

- [ ] **Step 1: Skriv kolumn-delen av migrationen**

Skapa filen med detta som första del:

```sql
-- 20260815090000_catalog_package_seo_fields.sql
-- Redaktionella fält för statiska, indexerbara paketsidor.
-- Se docs/superpowers/specs/2026-08-15-statiska-paketsidor-seo-design.md.
-- Additiv: alla kolumner nullable, RPC-fält läggs sist i returtabellen.

alter table public.catalog_package_variants
    add column if not exists problem_text text,
    add column if not exists when_to_use text,
    add column if not exists outcome_text text;

alter table public.catalog_packages
    add column if not exists area text,
    add column if not exists tags text[],
    add column if not exists is_indexable boolean;

comment on column public.catalog_packages.is_indexable is
    'null = använd innehållströskeln (intro_text ifyllt och minst tre prompts), true/false = tvinga.';
```

- [ ] **Step 2: Lägg till de utökade RPC:erna**

Öppna `supabase/migrations/20260725100000_catalog_read_context_arrays.sql` och läs
`create or replace function public.list_published_packages(...)` i sin helhet.
Kopiera den **verbatim** in i din nya migration, och gör exakt tre tillägg:

1. I `returns table (...)`, efter `audience_label text`, lägg till:
   ```sql
    problem_text text,
    when_to_use text,
    outcome_text text,
    area text,
    tags text[],
    is_indexable boolean
   ```
2. I select-listan, efter raden `coalesce(matched.audience_label, fallback.audience_label) as audience_label`, lägg till (observera kommatecknet på föregående rad):
   ```sql
    coalesce(matched.problem_text, fallback.problem_text) as problem_text,
    coalesce(matched.when_to_use, fallback.when_to_use) as when_to_use,
    coalesce(matched.outcome_text, fallback.outcome_text) as outcome_text,
    cpkg.area,
    cpkg.tags,
    cpkg.is_indexable
   ```
3. Behåll `revoke`/`grant`-raderna exakt som de står i källfilen.

Gör motsvarande för `public.get_published_package(...)`, men läs den från
`supabase/migrations/20260725133000_catalog_parameter_schemas.sql` (den är
senare och innehåller `parameter_schema`, `default_bindings`,
`binding_overrides` — de måste följa med). Lägg de sex nya fälten **sist**
i returtabellen, efter `binding_overrides`, och motsvarande i select-listan
med `v.problem_text`, `v.when_to_use`, `v.outcome_text`, `cpkg.area`,
`cpkg.tags`, `cpkg.is_indexable`.

**Kritiskt:** transkribera inte funktionskropparna ur minnet. Öppna
källfilerna, kopiera, lägg bara till. Ett tidigare arbete i detta repo
införde av misstag en beteendeändring genom att skriva av en funktionskropp
felaktigt.

- [ ] **Step 3: Läs igenom din migration mot källfilerna**

Jämför rad för rad: parameterlistor, `language sql`, `stable`,
`security definer`, `set search_path = ''`, where-villkor, order by,
revoke/grant. Enda skillnaderna ska vara de sex nya fälten på de två
ställena per funktion. Rätta avvikelser.

- [ ] **Step 4: Skriv verifieringsfilen**

```sql
-- supabase/tests/verify_catalog_package_seo_fields.sql
-- Kör mot staging eller länkad utvecklingsdatabas efter migrationen.

-- 1. Kolumnerna finns
select 'catalog_package_variants saknar kolumn' as fel, c.expected
  from (values ('problem_text'), ('when_to_use'), ('outcome_text')) as c(expected)
 where not exists (
     select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'catalog_package_variants'
        and column_name = c.expected
 );

select 'catalog_packages saknar kolumn' as fel, c.expected
  from (values ('area'), ('tags'), ('is_indexable')) as c(expected)
 where not exists (
     select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'catalog_packages'
        and column_name = c.expected
 );

-- 2. RPC:erna returnerar de nya fälten
select 'list_published_packages saknar fält' as fel
 where not exists (
     select 1
       from information_schema.parameters
      where specific_schema = 'public'
        and parameter_name = 'is_indexable'
        and specific_name like 'list_published_packages%'
 );

select 'get_published_package saknar fält' as fel
 where not exists (
     select 1
       from information_schema.parameters
      where specific_schema = 'public'
        and parameter_name = 'is_indexable'
        and specific_name like 'get_published_package%'
 );

-- 3. RPC:erna går fortfarande att anropa med oförändrad signatur
select count(*) >= 0 as list_ok
  from public.list_published_packages(array['generell'], null);
```

Alla fyra `select`-satserna ska returnera noll rader vid godkänt resultat.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260815090000_catalog_package_seo_fields.sql supabase/tests/verify_catalog_package_seo_fields.sql
git commit -m "feat: add editorial and SEO fields to catalog packages"
```

Applicera **inte** mot produktion. Rapportera att prod-migrationen återstår.

---

### Task 2: Generatorns rena funktioner + tester

**Files:**
- Create: `scripts/catalog-page-lib.mjs`
- Create: `scripts/catalog-page-lib.test.mjs`
- Modify: `package.json` (lägg till `test`-script)

**Interfaces:**
- Produces (alla exporterade från `scripts/catalog-page-lib.mjs`):
  - `SAFE_SLUG` — `RegExp`
  - `isSafeSlug(value: unknown): boolean`
  - `escapeHtml(value: unknown): string`
  - `isIndexable(pkg: {intro_text?: string|null, is_indexable?: boolean|null}, promptCount: number): boolean`
  - `buildSitemap(urls: string[]): string`
  - `packageUrl(slug: string): string` — returnerar `/paket/<slug>/`
  - `absoluteUrl(path: string): string` — returnerar `https://app.promptbanken.se` + path
  - `groupPackagesByArea(packages: Array<{area?: string|null}>): Array<{area: string|null, label: string, packages: Array<object>}>`
  - `areaAnchor(area: string|null): string` — returnerar `omrade-<slug>` eller `omrade-ovriga`
- Task 3 och Task 4 importerar dessa.

- [ ] **Step 1: Skriv de failande testerna**

```javascript
// scripts/catalog-page-lib.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import {
    isSafeSlug,
    escapeHtml,
    isIndexable,
    buildSitemap,
    packageUrl,
    absoluteUrl,
    groupPackagesByArea,
    areaAnchor
} from './catalog-page-lib.mjs';

test('isSafeSlug accepterar normala slugs', () => {
    assert.equal(isSafeSlug('ai-for-hr'), true);
    assert.equal(isSafeSlug('paket1'), true);
});

test('isSafeSlug avvisar sökvägsmanipulation och skräp', () => {
    assert.equal(isSafeSlug('../../etc/passwd'), false);
    assert.equal(isSafeSlug('a/b'), false);
    assert.equal(isSafeSlug('AI-FOR-HR'), false);
    assert.equal(isSafeSlug('-leading'), false);
    assert.equal(isSafeSlug('trailing-'), false);
    assert.equal(isSafeSlug(''), false);
    assert.equal(isSafeSlug(null), false);
    assert.equal(isSafeSlug(undefined), false);
});

test('escapeHtml neutraliserar taggar och attribut', () => {
    assert.equal(
        escapeHtml('<script>alert("x")</script>'),
        '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;'
    );
    assert.equal(escapeHtml("O'Brien & co"), 'O&#39;Brien &amp; co');
});

test('escapeHtml hanterar tomma värden', () => {
    assert.equal(escapeHtml(null), '');
    assert.equal(escapeHtml(undefined), '');
    assert.equal(escapeHtml(0), '0');
});

test('isIndexable kräver intro_text och minst tre prompts', () => {
    assert.equal(isIndexable({ intro_text: 'En text' }, 3), true);
    assert.equal(isIndexable({ intro_text: 'En text' }, 2), false);
    assert.equal(isIndexable({ intro_text: '' }, 5), false);
    assert.equal(isIndexable({ intro_text: null }, 5), false);
    assert.equal(isIndexable({ intro_text: '   ' }, 5), false);
});

test('is_indexable åsidosätter tröskeln i båda riktningarna', () => {
    assert.equal(isIndexable({ intro_text: '', is_indexable: true }, 0), true);
    assert.equal(isIndexable({ intro_text: 'En text', is_indexable: false }, 9), false);
    assert.equal(isIndexable({ intro_text: 'En text', is_indexable: null }, 3), true);
});

test('packageUrl och absoluteUrl bygger rätt adresser', () => {
    assert.equal(packageUrl('ai-for-hr'), '/paket/ai-for-hr/');
    assert.equal(absoluteUrl('/paket/ai-for-hr/'), 'https://app.promptbanken.se/paket/ai-for-hr/');
});

test('buildSitemap ger giltig XML med alla URL:er', () => {
    const xml = buildSitemap(['https://app.promptbanken.se/', 'https://app.promptbanken.se/paket/x/']);
    assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?>/);
    assert.match(xml, /<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9">/);
    assert.match(xml, /<url><loc>https:\/\/app\.promptbanken\.se\/<\/loc><\/url>/);
    assert.match(xml, /<url><loc>https:\/\/app\.promptbanken\.se\/paket\/x\/<\/loc><\/url>/);
    assert.match(xml, /<\/urlset>\s*$/);
});

test('buildSitemap dedupar och bevarar ordning', () => {
    const xml = buildSitemap(['https://a/', 'https://b/', 'https://a/']);
    assert.equal(xml.match(/<loc>https:\/\/a\/<\/loc>/g).length, 1);
    assert.ok(xml.indexOf('https://a/') < xml.indexOf('https://b/'));
});

test('groupPackagesByArea grupperar och lägger områdeslösa sist', () => {
    const grupper = groupPackagesByArea([
        { slug: 'a', area: 'ledarskap' },
        { slug: 'b', area: null },
        { slug: 'c', area: 'ledarskap' },
        { slug: 'd', area: 'kommunikation' }
    ]);
    assert.equal(grupper.at(-1).area, null);
    assert.equal(grupper.at(-1).label, 'Övriga paket');
    assert.equal(grupper.at(-1).packages.length, 1);
    const ledarskap = grupper.find((g) => g.area === 'ledarskap');
    assert.equal(ledarskap.packages.length, 2);
});

test('areaAnchor ger stabila ankare', () => {
    assert.equal(areaAnchor('ledarskap'), 'omrade-ledarskap');
    assert.equal(areaAnchor(null), 'omrade-ovriga');
});
```

- [ ] **Step 2: Lägg till test-scriptet och kör testerna för att se dem faila**

I `package.json`, lägg till i `"scripts"`:

```json
    "test": "node --test scripts/",
```

Kör: `npm test`
Förväntat: FAIL — `Cannot find module ... catalog-page-lib.mjs`.

- [ ] **Step 3: Implementera modulen**

```javascript
// scripts/catalog-page-lib.mjs
// Rena hjälpfunktioner för generatorn av statiska katalogsidor.
// Se docs/superpowers/specs/2026-08-15-statiska-paketsidor-seo-design.md.

export const SITE_ORIGIN = 'https://app.promptbanken.se';

export const SAFE_SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function isSafeSlug(value) {
    return typeof value === 'string' && SAFE_SLUG.test(value);
}

export function escapeHtml(value) {
    if (value === null || value === undefined) return '';
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// Tröskeln finns för att undvika tunna landningssidor: ett paket måste ha
// redaktionell inledning och tillräckligt innehåll för att förtjäna
// indexering. is_indexable låter admin åsidosätta i båda riktningarna.
export function isIndexable(pkg, promptCount) {
    if (pkg?.is_indexable === true) return true;
    if (pkg?.is_indexable === false) return false;
    const hasIntro = typeof pkg?.intro_text === 'string' && pkg.intro_text.trim() !== '';
    return hasIntro && promptCount >= 3;
}

export function packageUrl(slug) {
    return `/paket/${slug}/`;
}

export function absoluteUrl(path) {
    return `${SITE_ORIGIN}${path}`;
}

export function buildSitemap(urls) {
    const unique = [...new Set(urls)];
    const entries = unique.map((url) => `  <url><loc>${escapeHtml(url)}</loc></url>`).join('\n');
    return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${entries}
</urlset>
`;
}

export function areaAnchor(area) {
    return area ? `omrade-${area}` : 'omrade-ovriga';
}

export function groupPackagesByArea(packages) {
    const byArea = new Map();
    const withoutArea = [];

    for (const pkg of packages) {
        const area = pkg?.area || null;
        if (!area) {
            withoutArea.push(pkg);
            continue;
        }
        if (!byArea.has(area)) byArea.set(area, []);
        byArea.get(area).push(pkg);
    }

    const groups = [...byArea.entries()]
        .sort(([a], [b]) => a.localeCompare(b, 'sv'))
        .map(([area, items]) => ({ area, label: area, packages: items }));

    if (withoutArea.length) {
        groups.push({ area: null, label: 'Övriga paket', packages: withoutArea });
    }

    return groups;
}
```

- [ ] **Step 4: Kör testerna igen**

Kör: `npm test`
Förväntat: PASS, alla tester gröna.

- [ ] **Step 5: Commit**

```bash
git add scripts/catalog-page-lib.mjs scripts/catalog-page-lib.test.mjs package.json
git commit -m "feat: add pure helpers and tests for static catalog page generation"
```

---

### Task 3: Sidmall för `/paket/<slug>/` + tester

**Files:**
- Create: `scripts/catalog-page-template.mjs`
- Create: `scripts/catalog-page-template.test.mjs`
- Reference (läs, ändra inte): `promptbanken.html` rad 1–40 (head-mönster: favicons, meta, OG, canonical)

**Interfaces:**
- Consumes: `escapeHtml`, `packageUrl`, `absoluteUrl`, `areaAnchor` från `scripts/catalog-page-lib.mjs` (Task 2).
- Produces: `renderPackagePage({ pkg, prompts, related, indexable }): string` och `renderPackageIndexPage({ groups }): string`, båda returnerar komplett HTML-dokument. Task 4 anropar dem.
  - `pkg`: objekt från `get_published_package` (fälten `slug`, `title`, `summary`, `intro_text`, `audience_label`, `problem_text`, `when_to_use`, `outcome_text`, `area`, `tags`).
  - `prompts`: array från `list_published_package_prompts`, sorterad på `sort_order`, fälten `prompt_slug`, `title`, `summary`, `step_title`, `step_intro`.
  - `related`: array av `{ slug, title, summary }`.
  - `indexable`: boolean.
  - `groups`: resultatet av `groupPackagesByArea`.

- [ ] **Step 1: Skriv de failande testerna**

```javascript
// scripts/catalog-page-template.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { renderPackagePage, renderPackageIndexPage } from './catalog-page-template.mjs';

const basePkg = {
    slug: 'ai-for-hr',
    title: 'AI för HR',
    summary: 'Sju arbetsflöden för HR-arbete.',
    intro_text: 'Det här paketet hjälper HR att komma igång.',
    audience_label: 'HR-specialister',
    problem_text: 'HR lägger tid på återkommande textarbete.',
    when_to_use: 'Vid rekrytering och medarbetarsamtal.',
    outcome_text: 'Färdiga underlag på minuter.',
    area: 'ledarskap',
    tags: ['hr', 'rekrytering']
};

const basePrompts = [
    { prompt_slug: 'a', title: 'Steg ett', summary: 'Sammanfattning ett', step_title: 'Förbered', step_intro: 'Börja här.' },
    { prompt_slug: 'b', title: 'Steg två', summary: 'Sammanfattning två', step_title: null, step_intro: null }
];

function render(overrides = {}) {
    return renderPackagePage({
        pkg: basePkg,
        prompts: basePrompts,
        related: [],
        indexable: true,
        ...overrides
    });
}

test('sidan har korrekt dokumentstruktur och H1', () => {
    const html = render();
    assert.match(html, /^<!DOCTYPE html>/);
    assert.match(html, /<html lang="sv">/);
    assert.match(html, /<h1[^>]*>AI för HR<\/h1>/);
});

test('metadata, canonical och OG är korrekta', () => {
    const html = render();
    assert.match(html, /<link rel="canonical" href="https:\/\/app\.promptbanken\.se\/paket\/ai-for-hr\/">/);
    assert.match(html, /<meta name="description" content="Sju arbetsflöden för HR-arbete\.">/);
    assert.match(html, /<meta property="og:url" content="https:\/\/app\.promptbanken\.se\/paket\/ai-for-hr\/">/);
    assert.match(html, /<meta property="og:title" content="AI för HR \| Promptbanken">/);
    assert.match(html, /<meta property="og:image" content="https:\/\/app\.promptbanken\.se\/brand-mark\.png">/);
});

test('indexerbar sida saknar noindex, icke-indexerbar har det', () => {
    assert.doesNotMatch(render(), /noindex/);
    assert.match(render({ indexable: false }), /<meta name="robots" content="noindex">/);
});

test('källraden anger Promptbanken', () => {
    assert.match(render(), /Av Promptbanken/);
});

test('alla redaktionella sektioner renderas när fälten är ifyllda', () => {
    const html = render();
    assert.match(html, /Vilket problem paketet löser/);
    assert.match(html, /HR lägger tid på återkommande textarbete\./);
    assert.match(html, /Vem det är för/);
    assert.match(html, /HR-specialister/);
    assert.match(html, /När det passar/);
    assert.match(html, /Vid rekrytering och medarbetarsamtal\./);
    assert.match(html, /Vad du får ut/);
    assert.match(html, /Färdiga underlag på minuter\./);
});

test('tomma redaktionella fält utelämnas helt', () => {
    const html = render({
        pkg: { ...basePkg, problem_text: null, when_to_use: '', outcome_text: undefined }
    });
    assert.doesNotMatch(html, /Vilket problem paketet löser/);
    assert.doesNotMatch(html, /När det passar/);
    assert.doesNotMatch(html, /Vad du får ut/);
    assert.match(html, /Vem det är för/);
});

test('innehållsförteckningen visar stegen i ordning med falltillbaka-titel', () => {
    const html = render();
    assert.ok(html.indexOf('Förbered') < html.indexOf('Steg två'));
    assert.match(html, /Börja här\./);
    assert.match(html, /Steg två/);
});

test('åtgärdslänken pekar på appens paketvy', () => {
    assert.match(render(), /href="\/promptbanken\.html\?package=ai-for-hr"/);
});

test('relaterade paket renderas, och sektionen utelämnas när listan är tom', () => {
    const medRelaterade = render({
        related: [{ slug: 'battre-moten', title: 'Bättre möten', summary: 'Om möten.' }]
    });
    assert.match(medRelaterade, /Relaterade paket/);
    assert.match(medRelaterade, /href="\/paket\/battre-moten\/"/);
    assert.doesNotMatch(render(), /Relaterade paket/);
});

test('taggar länkar till översiktens områdesankare', () => {
    assert.match(render(), /href="\/paket\/#omrade-ledarskap"/);
});

test('JSON-LD innehåller BreadcrumbList och ItemList men inte HowTo', () => {
    const html = render();
    assert.match(html, /"@type":\s*"BreadcrumbList"/);
    assert.match(html, /"@type":\s*"ItemList"/);
    assert.doesNotMatch(html, /HowTo/);
});

test('all databastext escapas', () => {
    const html = render({
        pkg: { ...basePkg, title: '<img src=x onerror=alert(1)>', summary: '"citat" & co' }
    });
    assert.doesNotMatch(html, /<img src=x/);
    assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt;/);
    assert.match(html, /&quot;citat&quot; &amp; co/);
});

test('översiktssidan grupperar per område med ankare', () => {
    const html = renderPackageIndexPage({
        groups: [
            { area: 'ledarskap', label: 'ledarskap', packages: [{ slug: 'a', title: 'A', summary: 'Om A' }] },
            { area: null, label: 'Övriga paket', packages: [{ slug: 'b', title: 'B', summary: 'Om B' }] }
        ]
    });
    assert.match(html, /id="omrade-ledarskap"/);
    assert.match(html, /id="omrade-ovriga"/);
    assert.match(html, /Övriga paket/);
    assert.match(html, /href="\/paket\/a\/"/);
    assert.match(html, /<link rel="canonical" href="https:\/\/app\.promptbanken\.se\/paket\/">/);
});
```

- [ ] **Step 2: Kör testerna för att se dem faila**

Kör: `npm test`
Förväntat: FAIL — `Cannot find module ... catalog-page-template.mjs`.

- [ ] **Step 3: Implementera mallen**

```javascript
// scripts/catalog-page-template.mjs
// HTML-mallar för statiska katalogsidor. Återanvänder style.css och samma
// head-mönster som övriga sidor, så sidorna ärver designsystemet.

import { escapeHtml, packageUrl, absoluteUrl, areaAnchor } from './catalog-page-lib.mjs';

function hasText(value) {
    return typeof value === 'string' && value.trim() !== '';
}

function head({ title, description, canonicalPath, indexable }) {
    const fullTitle = `${title} | Promptbanken`;
    return `<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${escapeHtml(fullTitle)}</title>
    <link rel="icon" href="/favicon.ico" sizes="any">
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    <meta name="description" content="${escapeHtml(description)}">
    ${indexable ? '<meta name="robots" content="index,follow">' : '<meta name="robots" content="noindex">'}
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="Promptbanken">
    <meta property="og:title" content="${escapeHtml(fullTitle)}">
    <meta property="og:description" content="${escapeHtml(description)}">
    <meta property="og:url" content="${escapeHtml(absoluteUrl(canonicalPath))}">
    <meta property="og:image" content="${escapeHtml(absoluteUrl('/brand-mark.png'))}">
    <meta name="twitter:card" content="summary">
    <link rel="canonical" href="${escapeHtml(absoluteUrl(canonicalPath))}">
    <link rel="stylesheet" href="/style.css">
</head>`;
}

function siteHeader() {
    return `<header class="landing-topbar">
        <a class="landing-brand" href="/index.html" aria-label="Promptbanken startsida">Promptbanken</a>
        <nav class="landing-nav" aria-label="Huvudlänkar">
            <a href="/paket/">Paket</a>
            <a href="/promptbanken.html">Katalog</a>
            <a href="/about.html">Om</a>
        </nav>
    </header>`;
}

function siteFooter() {
    return `<footer class="landing-footer">
        <p>Promptbanken — öppet bibliotek för arbete med AI.</p>
        <p><a href="/privacy.html">Integritet</a> · <a href="/terms.html">Villkor</a></p>
    </footer>`;
}

function breadcrumbs(trail) {
    const items = trail
        .map((item, index) => {
            const isLast = index === trail.length - 1;
            return isLast
                ? `<li aria-current="page">${escapeHtml(item.name)}</li>`
                : `<li><a href="${escapeHtml(item.path)}">${escapeHtml(item.name)}</a></li>`;
        })
        .join('\n            ');

    return `<nav class="breadcrumbs" aria-label="Brödsmulor">
        <ol>
            ${items}
        </ol>
    </nav>`;
}

function breadcrumbJsonLd(trail) {
    return JSON.stringify({
        '@context': 'https://schema.org',
        '@type': 'BreadcrumbList',
        itemListElement: trail.map((item, index) => ({
            '@type': 'ListItem',
            position: index + 1,
            name: item.name,
            item: absoluteUrl(item.path)
        }))
    });
}

function itemListJsonLd(prompts) {
    return JSON.stringify({
        '@context': 'https://schema.org',
        '@type': 'ItemList',
        itemListElement: prompts.map((prompt, index) => ({
            '@type': 'ListItem',
            position: index + 1,
            name: prompt.step_title || prompt.title || ''
        }))
    });
}

function section(heading, body) {
    if (!hasText(body)) return '';
    return `<section class="paket-section">
            <h2>${escapeHtml(heading)}</h2>
            <p>${escapeHtml(body)}</p>
        </section>`;
}

export function renderPackagePage({ pkg, prompts, related, indexable }) {
    const trail = [
        { name: 'Hem', path: '/' },
        { name: 'Paket', path: '/paket/' },
        { name: pkg.title, path: packageUrl(pkg.slug) }
    ];

    const editorialSections = [
        section('Vilket problem paketet löser', pkg.problem_text),
        section('Vem det är för', pkg.audience_label),
        section('När det passar', pkg.when_to_use),
        section('Vad du får ut', pkg.outcome_text)
    ].filter(Boolean).join('\n        ');

    const promptItems = prompts
        .map((prompt, index) => `<li class="paket-step">
                <h3>${escapeHtml(prompt.step_title || prompt.title || `Steg ${index + 1}`)}</h3>
                ${hasText(prompt.step_intro) ? `<p>${escapeHtml(prompt.step_intro)}</p>` : ''}
                ${hasText(prompt.summary) ? `<p class="paket-step-summary">${escapeHtml(prompt.summary)}</p>` : ''}
            </li>`)
        .join('\n            ');

    const relatedSection = related.length
        ? `<section class="paket-section paket-related">
            <h2>Relaterade paket</h2>
            <ul>
                ${related.map((item) => `<li><a href="${escapeHtml(packageUrl(item.slug))}">${escapeHtml(item.title)}</a>${hasText(item.summary) ? ` — ${escapeHtml(item.summary)}` : ''}</li>`).join('\n                ')}
            </ul>
        </section>`
        : '';

    const tagList = Array.isArray(pkg.tags) && pkg.tags.length
        ? `<p class="paket-tags">${pkg.tags.map((tag) => `<a href="/paket/#${escapeHtml(areaAnchor(pkg.area))}">${escapeHtml(tag)}</a>`).join(' · ')}</p>`
        : '';

    return `<!DOCTYPE html>
<html lang="sv">
${head({
        title: pkg.title,
        description: pkg.summary || '',
        canonicalPath: packageUrl(pkg.slug),
        indexable
    })}
<body class="paket-page">
    ${siteHeader()}
    <main>
        ${breadcrumbs(trail)}
        <article class="paket-article">
            <h1>${escapeHtml(pkg.title)}</h1>
            <p class="paket-lead">${escapeHtml(pkg.summary)}</p>
            <p class="paket-source">Av Promptbanken</p>
            ${hasText(pkg.intro_text) ? `<p class="paket-intro">${escapeHtml(pkg.intro_text)}</p>` : ''}
        ${editorialSections}
        <section class="paket-section paket-contents">
            <h2>Det här ingår</h2>
            <ol class="paket-steps">
            ${promptItems}
            </ol>
        </section>
        <p class="paket-cta">
            <a class="landing-primary" href="/promptbanken.html?package=${escapeHtml(pkg.slug)}">Öppna paketet i Promptbanken</a>
        </p>
        ${relatedSection}
        ${tagList}
        </article>
    </main>
    ${siteFooter()}
    <script type="application/ld+json">${breadcrumbJsonLd(trail)}</script>
    <script type="application/ld+json">${itemListJsonLd(prompts)}</script>
</body>
</html>
`;
}

export function renderPackageIndexPage({ groups }) {
    const trail = [
        { name: 'Hem', path: '/' },
        { name: 'Paket', path: '/paket/' }
    ];

    const groupSections = groups
        .map((group) => `<section class="paket-group" id="${escapeHtml(areaAnchor(group.area))}">
            <h2>${escapeHtml(group.label)}</h2>
            <ul class="paket-group-list">
                ${group.packages.map((pkg) => `<li>
                    <a href="${escapeHtml(packageUrl(pkg.slug))}">${escapeHtml(pkg.title)}</a>
                    ${hasText(pkg.summary) ? `<p>${escapeHtml(pkg.summary)}</p>` : ''}
                </li>`).join('\n                ')}
            </ul>
        </section>`)
        .join('\n        ');

    return `<!DOCTYPE html>
<html lang="sv">
${head({
        title: 'Promptpaket och AI-arbetssätt',
        description: 'Färdiga promptpaket och AI-arbetssätt för riktiga arbetsuppgifter, sorterade efter område.',
        canonicalPath: '/paket/',
        indexable: true
    })}
<body class="paket-index-page">
    ${siteHeader()}
    <main>
        ${breadcrumbs(trail)}
        <h1>Promptpaket och AI-arbetssätt</h1>
        <p class="paket-lead">Färdiga paket för riktiga arbetsuppgifter — välj område nedan.</p>
        ${groupSections}
    </main>
    ${siteFooter()}
    <script type="application/ld+json">${breadcrumbJsonLd(trail)}</script>
</body>
</html>
`;
}
```

- [ ] **Step 4: Kör testerna**

Kör: `npm test`
Förväntat: PASS, alla tester i båda testfilerna gröna.

- [ ] **Step 5: Commit**

```bash
git add scripts/catalog-page-template.mjs scripts/catalog-page-template.test.mjs
git commit -m "feat: add HTML templates for static package pages"
```

---

### Task 4: Generatorn — hämta data, skriv filer, bygg sitemap

**Files:**
- Create: `scripts/generate-catalog-pages.mjs`
- Modify: `package.json` (`build`-scriptet)
- Reference (läs, ändra inte): `sitemap.xml` (nuvarande statiska URL-lista)

**Interfaces:**
- Consumes: allt från `scripts/catalog-page-lib.mjs` (Task 2) och `renderPackagePage`/`renderPackageIndexPage` från `scripts/catalog-page-template.mjs` (Task 3). RPC:erna från Task 1.
- Produces: `dist/paket/<slug>/index.html`, `dist/paket/index.html`, `dist/sitemap.xml`.

- [ ] **Step 1: Skriv generatorn**

```javascript
// scripts/generate-catalog-pages.mjs
// Genererar statiska paketsidor efter `vite build`.
// I CI (env satt) failar scriptet bygget vid fel — hellre stoppat bygge än
// en deployad sajt utan paketsidor och med amputerad sitemap.
// Lokalt utan env hoppar det över med varning.

import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import {
    isSafeSlug,
    isIndexable,
    buildSitemap,
    packageUrl,
    absoluteUrl,
    groupPackagesByArea
} from './catalog-page-lib.mjs';
import { renderPackagePage, renderPackageIndexPage } from './catalog-page-template.mjs';

const DIST = 'dist';

// Behålls oförändrad från den tidigare handskrivna sitemap.xml.
const STATIC_URLS = [
    '/',
    '/index.html',
    '/promptbanken.html',
    '/about.html',
    '/help.html',
    '/mcp.html',
    '/privacy.html',
    '/terms.html',
    '/prompts.html',
    '/prompts.json',
    '/llms.txt'
];

const supabaseUrl = process.env.VITE_SUPABASE_URL;
const supabaseKey = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!supabaseUrl || !supabaseKey) {
    console.warn(
        '[generate-catalog-pages] VITE_SUPABASE_URL/VITE_SUPABASE_PUBLISHABLE_KEY saknas — hoppar över generering av paketsidor.'
    );
    process.exit(0);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function rpc(name, args) {
    const { data, error } = await supabase.rpc(name, args);
    if (error) {
        throw new Error(`RPC ${name} misslyckades: ${error.message}`);
    }
    return data || [];
}

async function writePage(path, html) {
    await mkdir(join(DIST, path), { recursive: true });
    await writeFile(join(DIST, path, 'index.html'), html, 'utf8');
}

async function main() {
    const packages = await rpc('list_published_packages', {
        p_context_keys: ['generell'],
        p_package_type: null
    });

    const usable = packages.filter((pkg) => {
        if (isSafeSlug(pkg.slug)) return true;
        console.warn(`[generate-catalog-pages] hoppar över paket med osäker slug: ${JSON.stringify(pkg.slug)}`);
        return false;
    });

    const indexableUrls = [];
    const indexablePackages = [];

    for (const pkg of usable) {
        const prompts = await rpc('list_published_package_prompts', {
            p_package_slug: pkg.slug,
            p_context_keys: ['generell']
        });

        const indexable = isIndexable(pkg, prompts.length);

        const related = usable
            .filter((other) => other.slug !== pkg.slug && other.area && other.area === pkg.area)
            .slice(0, 4)
            .map(({ slug, title, summary }) => ({ slug, title, summary }));

        await writePage(
            `paket/${pkg.slug}`,
            renderPackagePage({ pkg, prompts, related, indexable })
        );

        if (indexable) {
            indexableUrls.push(absoluteUrl(packageUrl(pkg.slug)));
            indexablePackages.push(pkg);
        }
    }

    await writePage(
        'paket',
        renderPackageIndexPage({ groups: groupPackagesByArea(indexablePackages) })
    );

    const sitemap = buildSitemap([
        ...STATIC_URLS.map((path) => absoluteUrl(path)),
        absoluteUrl('/paket/'),
        ...indexableUrls
    ]);
    await writeFile(join(DIST, 'sitemap.xml'), sitemap, 'utf8');

    console.log(
        `[generate-catalog-pages] ${usable.length} paketsidor skrivna, varav ${indexableUrls.length} indexerbara.`
    );
}

main().catch((error) => {
    console.error(`[generate-catalog-pages] ${error.message}`);
    process.exit(1);
});
```

- [ ] **Step 2: Koppla in generatorn i bygget**

I `package.json`, ändra `build`-scriptet:

```json
    "build": "vite build && node scripts/generate-catalog-pages.mjs",
```

- [ ] **Step 3: Verifiera att bygget fungerar utan env-variabler**

Kör: `npm run build`
Förväntat: bygget lyckas, och utskriften innehåller
`VITE_SUPABASE_URL/VITE_SUPABASE_PUBLISHABLE_KEY saknas — hoppar över`.
Ingen `dist/paket/`-katalog skapas.

- [ ] **Step 4: Verifiera att generatorn failar högt vid trasig anslutning**

Kör:
```bash
VITE_SUPABASE_URL=https://example.invalid VITE_SUPABASE_PUBLISHABLE_KEY=fel npm run build
```
Förväntat: bygget avslutas med exit-kod skild från 0 och ett
`[generate-catalog-pages]`-felmeddelande.

- [ ] **Step 5: Commit**

```bash
git add scripts/generate-catalog-pages.mjs package.json
git commit -m "feat: generate static package pages and sitemap at build time"
```

---

### Task 5: 404-sida med fallback för paket-URL:er

**Files:**
- Create: `404.html`
- Modify: `vite.config.js` (lägg till `404` i `rollupOptions.input`)

**Interfaces:**
- Produces: `dist/404.html`. Ingen annan task konsumerar den.

- [ ] **Step 1: Skapa 404-sidan**

```html
<!DOCTYPE html>
<html lang="sv">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sidan hittades inte | Promptbanken</title>
    <link rel="icon" href="/favicon.ico" sizes="any">
    <meta name="robots" content="noindex">
    <link rel="stylesheet" href="/style.css">
    <script>
        // Ett nypublicerat paket syns direkt i appen men får sin statiska sida
        // först vid nästa bygge. Fram till dess skickas /paket/<slug>/ vidare
        // till appens paketvy, så delade länkar aldrig landar på en felsida.
        (function () {
            var match = window.location.pathname.match(/^\/paket\/([^/]+)\/?$/);
            if (!match) return;
            var slug = match[1];
            // Strikt validering: utan den blir sidan en öppen redirect.
            if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) return;
            window.location.replace('/promptbanken.html?package=' + encodeURIComponent(slug));
        })();
    </script>
</head>
<body class="landing-page">
    <header class="landing-topbar">
        <a class="landing-brand" href="/index.html" aria-label="Promptbanken startsida">Promptbanken</a>
    </header>
    <main>
        <h1>Sidan hittades inte</h1>
        <p>Adressen finns inte, eller så har sidan flyttat.</p>
        <ul>
            <li><a href="/">Till startsidan</a></li>
            <li><a href="/paket/">Alla promptpaket</a></li>
            <li><a href="/promptbanken.html">Öppna katalogen</a></li>
        </ul>
    </main>
</body>
</html>
```

- [ ] **Step 2: Lägg till sidan i Vite-bygget**

I `vite.config.js`, i `build.rollupOptions.input`, lägg till efter raden för `index`:

```javascript
        '404': resolve(__dirname, '404.html'),
```

- [ ] **Step 3: Verifiera**

Kör: `npm run build`
Förväntat: bygget lyckas och `dist/404.html` finns.

Starta `npm run preview` och kontrollera manuellt:
- `/paket/finns-inte/` → hamnar i `promptbanken.html?package=finns-inte`
- `/nagot-helt-annat` → visar 404-sidan utan omdirigering
- `/paket/..%2F..%2Fnagot/` → ingen omdirigering sker

(Notera: `vite preview` serverar inte nödvändigtvis 404.html för okända
sökvägar på samma sätt som GitHub Pages. Om preview inte visar sidan,
öppna `/404.html` direkt och verifiera redirect-logiken genom att
tillfälligt testa mönstret i devtools-konsolen istället — och notera i
rapporten att fullständig verifiering kräver deploy.)

- [ ] **Step 4: Commit**

```bash
git add 404.html vite.config.js
git commit -m "feat: add 404 page with package URL fallback"
```

---

### Task 6: Nattlig ombyggnad i GitHub Actions

**Files:**
- Modify: `.github/workflows/deploy.yml`

**Interfaces:**
- Produces: inget som andra tasks konsumerar.

- [ ] **Step 1: Lägg till schemalagd körning**

I `.github/workflows/deploy.yml`, ersätt `on:`-blocket:

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:
  schedule:
    # 03:15 UTC varje natt — plockar upp paket som publicerats under dagen.
    - cron: '15 3 * * *'
```

Inget annat i filen ändras. Secrets och byggsteg är oförändrade.

- [ ] **Step 2: Verifiera YAML-syntaxen**

Kör:
```bash
node -e "const fs=require('fs');const s=fs.readFileSync('.github/workflows/deploy.yml','utf8');if(!/schedule:/.test(s)||!/cron: '15 3 \* \* \*'/.test(s))throw new Error('schedule saknas');console.log('ok')"
```
Förväntat: `ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: rebuild site nightly so new packages get static pages"
```

---

### Task 7: Paketförst i katalogen och länk från startsidan

**Files:**
- Modify: `promptbanken.html` (katalogsektionen, runt rad 285–304)
- Modify: `index.html` (hero-actions runt rad 57–70, och `landing-nav` runt rad 36)
- Modify: `script.js` (`createCatalogPackageCard`, runt rad 1057)

**Interfaces:**
- Consumes: `packageUrl`-formen `/paket/<slug>/` från Task 2 (men `script.js` får inte importera — bygg strängen inline).
- Produces: inget som andra tasks konsumerar.

- [ ] **Step 1: Flytta paketgriden före promptgriden**

I `promptbanken.html`, i `<section class="catalog-section" id="catalog-section">`, byt ordning så att paketblocket kommer först. Resultatet ska se ut så här (behåll `catalog-package-link-error`-bannern på sin plats direkt före paketgriden):

```html
                    <h2>Paket och arbetssätt</h2>
                    <p class="catalog-section-lead">Färdiga AI-arbetssätt för riktiga arbetsuppgifter. <a href="/paket/">Se alla paket</a>.</p>
                    <div class="catalog-package-link-error" id="catalog-package-link-error" hidden role="alert">
                        Paketet kunde inte hittas eller är inte längre publicerat.
                    </div>
                    <div class="catalog-grid" id="catalog-package-grid"></div>

                    <h3>Enskilda prompts</h3>
                    <div class="catalog-grid" id="catalog-prompt-grid"></div>
```

Behåll `catalog-prompt-detail`-panelen oförändrad efter griderna. Ändra inga id:n — `script.js` slår upp dem.

- [ ] **Step 2: Lägg till länk till den statiska sidan på paketkorten**

I `script.js`, i `createCatalogPackageCard`, lägg till en länk i kortets markup. Ersätt `card.innerHTML`-tilldelningen med:

```javascript
    card.innerHTML = `
        <h4>${title}</h4>
        <p>${summary}</p>
        <span class="catalog-package-type">${typeLabel}</span>
        ${fallbackBadge}
        <p class="catalog-package-permalink"><a href="/paket/${encodeURIComponent(pkg.slug)}/">Läs mer om paketet</a></p>
    `;
```

Lägg sedan till, direkt före `return card;`, så att länkklick inte också öppnar detaljvyn:

```javascript
    card.querySelector('.catalog-package-permalink a')?.addEventListener('click', (event) => {
        event.stopPropagation();
    });
```

- [ ] **Step 3: Länka till `/paket/` från startsidan**

I `index.html`, i `<nav class="landing-nav">`, lägg till som första länk:

```html
            <a href="/paket/">Paket</a>
```

I `<div class="landing-actions">`, lägg till efter den befintliga primära knappen:

```html
                    <a class="landing-secondary" href="/paket/">
                        Bläddra bland promptpaket
                    </a>
```

- [ ] **Step 4: Verifiera**

Kör: `npm run build`
Förväntat: bygget lyckas.

Kör `npm run web:dev` och kontrollera i browser:
- I katalogen ligger "Paket och arbetssätt" ovanför "Enskilda prompts".
- Ett paketkort öppnar fortfarande detaljvyn vid klick på kortet.
- Klick på "Läs mer om paketet" öppnar inte detaljvyn.
- Startsidan har "Paket" i menyn och en knapp till `/paket/`.

- [ ] **Step 5: Commit**

```bash
git add promptbanken.html index.html script.js
git commit -m "feat: put packages before prompts and link static package pages"
```

---

### Task 8: Admin-UI för de redaktionella fälten

**Files:**
- Create: `src/adminPackageSeo.js`
- Modify: `admin.html` (lägg till modulens container och script-import)
- Modify: `vite.config.js` endast om `admin.html` inte redan drar in modulen via `src/admin.js` — kontrollera först

**Interfaces:**
- Consumes: RPC-fälten från Task 1. Skrivning sker via befintlig
  `upsert_catalog_package_variant` för variantfälten. För paketfälten
  (`area`, `tags`, `is_indexable`) finns **ingen** befintlig skriv-RPC — läs
  `supabase/migrations/20260728120000_admin_catalog_authoring.sql` och följ
  dess mönster (`app_private`-funktion + tunn `public`-wrapper med
  rollkontroll) för en ny `upsert_catalog_package_metadata`.
- Produces: inget som andra tasks konsumerar.

- [ ] **Step 1: Lägg till skriv-RPC:n**

Skapa `supabase/migrations/20260815091000_admin_package_seo_metadata.sql`.
Läs först `supabase/migrations/20260728120000_admin_catalog_authoring.sql`
och kopiera dess mönster exakt: `app_private`-funktion med
`security definer` och `set search_path = ''`, rollkontroll mot
`platform_owner`, plus en `public`-wrapper med `revoke`/`grant to authenticated`.

Funktionen ska ha signaturen:

```sql
create or replace function app_private.upsert_catalog_package_metadata(
    p_package_id uuid,
    p_area text,
    p_tags text[],
    p_is_indexable boolean
)
returns void
```

och uppdatera `public.catalog_packages` för det angivna id:t. Utelämnade
värden ska inte nolla befintliga — följ samma
`coalesce`/omitted-field-hantering som
`20260729090000_catalog_variant_upsert_preserve_omitted_fields.sql` använder,
läs den filen och matcha dess mönster.

- [ ] **Step 2: Bygg modulen**

`src/adminPackageSeo.js` ska:
- hämta paketlistan via `list_published_packages` (fälten från Task 1),
- rendera ett formulär per valt paket med `problem_text`, `when_to_use`,
  `outcome_text` (textareor), `area` (text), `tags` (kommaseparerat fält)
  och `is_indexable` (trelägesval: Auto / Alltid / Aldrig),
- visa en tydlig statusrad: **"Indexerbar: ja/nej"** beräknad med samma
  regel som generatorn (intro_text ifyllt och minst tre prompts, om inte
  `is_indexable` är satt) så kvalitetskravet syns vid redigering,
- spara variantfälten via `upsert_catalog_package_variant` och paketfälten
  via den nya `upsert_catalog_package_metadata`.

Följ mönstren i `src/admin.js` för Supabase-anrop, felhantering och
DOM-uppbyggnad, men lägg **ingen** ny kod i den filen — den är redan 2953
rader.

- [ ] **Step 3: Koppla in modulen i admin.html**

Lägg till en container och `<script type="module" src="/src/adminPackageSeo.js"></script>`
i `admin.html`, i samma mönster som befintliga admin-moduler laddas.

- [ ] **Step 4: Verifiera**

Kör: `npm run build` — förväntat: bygget lyckas och modulen kommer med i
`dist/assets/`.

Manuellt (kräver inloggning som `platform_owner` mot en databas där Task 1
och Step 1 ovan är applicerade): öppna admin, välj ett paket, fyll i
fälten, spara, ladda om och bekräfta att värdena finns kvar samt att
statusraden för indexerbarhet ändras när villkoren uppfylls.

Om ingen sådan databas är tillgänglig: rapportera det tydligt istället för
att påstå att flödet är verifierat.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260815091000_admin_package_seo_metadata.sql src/adminPackageSeo.js admin.html
git commit -m "feat: add admin editing for package SEO and editorial fields"
```

---

## Self-review

**Spec coverage:**
- URL-struktur `/paket/<slug>/`, generell variant → Task 4.
- Nya redaktionella fält + area/tags/is_indexable → Task 1, redigerbara i Task 8.
- Indexerbarhetströskel med åsidosättning → Task 2 (`isIndexable`), tillämpad i Task 4, synlig i Task 8.
- Generator med fail-i-CI / skip-lokalt → Task 4, Step 1, 3, 4.
- Sitemap byggd av statiska + genererade URL:er → Task 2 (`buildSitemap`), Task 4.
- Sidmall med källa-slot, redaktionella sektioner, innehållsförteckning, CTA, relaterade, taggar → Task 3.
- Metadata, canonical, OG, noindex → Task 3 (`head`).
- JSON-LD BreadcrumbList + ItemList, inget HowTo → Task 3, verifierat i test.
- `/paket/`-översikt med områdesgrupper och "Övriga paket" → Task 2 (`groupPackagesByArea`), Task 3, Task 4.
- 404-fallback med slugvalidering → Task 5.
- Nattlig ombyggnad → Task 6.
- Paket före prompts, länkar från startsidan → Task 7.
- Escaping och slugvalidering → Task 2 (testad), använd genomgående i Task 3–5.
- `node --test` som första JS-testsvit → Task 2, utökad i Task 3.
- SQL-verifieringsfil → Task 1, Step 4.

**Type consistency:** `isIndexable(pkg, promptCount)`, `packageUrl(slug)`,
`absoluteUrl(path)`, `areaAnchor(area)`, `groupPackagesByArea(packages)`,
`buildSitemap(urls)`, `renderPackagePage({pkg, prompts, related, indexable})`,
`renderPackageIndexPage({groups})` — samma namn och signaturer i Task 2, 3
och 4.

**Placeholders:** inga TBD. Task 8 beskriver modulens innehåll i prosa
snarare än fullständig kod, eftersom den måste följa mönster i två
befintliga migrationer och i `src/admin.js` som implementeraren behöver
läsa; alla filer och mönster som ska följas är namngivna exakt.
