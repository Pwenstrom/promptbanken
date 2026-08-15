# Creator-profiler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inloggade användare kan skapa och publicera en egen creator-profil som får en statisk, SEO-indexerbar sida på `/creator/<slug>/`.

**Architecture:** Ny tabell `creator_profiles` med RLS och `SECURITY DEFINER`-RPC:er i katalogens befintliga mönster. Den statiska sidan genereras av det befintliga byggsteget (`scripts/generate-catalog-pages.mjs`), utökat med profiler. Ny appsida `creator.html` för redigering och en adminmodul för de två privilegierade ingreppen.

**Tech Stack:** Node 20 (ESM, `node --test`), Vite 7, `@supabase/supabase-js`, Supabase Postgres, GitHub Actions.

## Global Constraints

- Designspec: `docs/superpowers/specs/2026-08-16-creator-profiler-design.md`. Vid konflikt mellan plan och spec — fråga, ändra inte tyst.
- **Migrationer appliceras inte mot produktion av en implementerande agent.** Skapa filen, verifiera resonemanget, rapportera att prod-körning återstår. Detta gäller även om du har `mcp__supabase__*`-verktyg — det enda anslutna projektet är produktion.
- **Merga inte till `main` och pusha inte.** Arbetet stannar på featuregrenen.
- `script.js` är inte bundlad av Vite och får inte ha `import`-satser. Nya appmoduler läggs i `src/` och byggs av Vite.
- Lägg ingen ny kod i `src/admin.js` (2953 rader, dessutom oanvänd — `admin.html` refererar den inte längre).
- Allt användargenererat innehåll escapas innan det skrivs till HTML.
- Alla slugs valideras mot `/^[a-z0-9]+(?:-[a-z0-9]+)*$/` innan de används i filsökvägar eller URL:er.
- Skriv-RPC:er följer mönstret i `supabase/migrations/20260728120000_admin_catalog_authoring.sql`: `app_private`-funktion med `security definer` och `set search_path = ''`, plus tunn `public`-wrapper med `revoke all ... from public` och `grant execute ... to authenticated`.
- Kanonisk bas-URL: `https://app.promptbanken.se`.
- Svensk text i allt användarsynligt gränssnitt.
- Efter varje kodändring: `npm test` och `npm run build` ska lyckas.

---

### Task 1: Migration — tabell, RLS och RPC:er

**Files:**
- Create: `supabase/migrations/20260816090000_creator_profiles.sql`
- Create: `supabase/tests/verify_creator_profiles.sql`
- Reference (läs, ändra inte): `supabase/migrations/20260728120000_admin_catalog_authoring.sql` (RPC-mönstret, `app_private.current_user_is_platform_owner()`)
- Reference (läs, ändra inte): `supabase/migrations/20260612121000_rls_policies.sql` (RLS-mönstret)

**Interfaces:**
- Produces: tabellen `public.creator_profiles` enligt spec, plus RPC:erna
  `upsert_my_creator_profile`, `publish_my_creator_profile`,
  `unpublish_my_creator_profile`, `get_my_creator_profile`,
  `list_published_creator_profiles`, `get_published_creator_profile(text)`,
  `admin_update_creator_profile_slug(uuid, text)`,
  `admin_unpublish_creator_profile(uuid)`. Task 3, 5 och 6 konsumerar dem.

- [ ] **Step 1: Läs mönsterfilerna**

Öppna `20260728120000_admin_catalog_authoring.sql` och läs hur en
`app_private`-funktion och dess `public`-wrapper är uppbyggda, inklusive
`revoke`/`grant`-raderna. Öppna `20260612121000_rls_policies.sql` och läs
hur RLS-policyer formuleras i detta projekt. Följ de mönstren exakt.

- [ ] **Step 2: Skriv tabellen, index och RLS**

```sql
-- 20260816090000_creator_profiles.sql
-- Creator-profiler: publika, SEO-indexerbara presentationssidor.
-- Se docs/superpowers/specs/2026-08-16-creator-profiler-design.md.
--
-- Obs: public.profiles är arbetsyte-roller, inte visningsprofiler.
-- creator_profiles är knuten till en person (auth.users), inte en workspace.

create table if not exists public.creator_profiles (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null unique references auth.users(id) on delete cascade,
    slug text not null unique,
    display_name text not null,
    bio_short text,
    bio_long text,
    competence_areas text[],
    organisation text,
    website_url text,
    linkedin_url text,
    -- Reserverad. Används inte förrän filuppladdning finns: en extern
    -- bild-URL på en publik sida läcker besökarens IP till tredje part.
    avatar_url text,
    status text not null default 'draft' check (status in ('draft', 'published')),
    published_at timestamptz,
    slug_locked boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint creator_profiles_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
    constraint creator_profiles_published_at_check check (
        (status = 'published' and published_at is not null)
        or status <> 'published'
    )
);

alter table public.creator_profiles enable row level security;

drop policy if exists "creator_profiles_select_own" on public.creator_profiles;
create policy "creator_profiles_select_own"
    on public.creator_profiles for select
    using (user_id = auth.uid());

drop policy if exists "creator_profiles_select_published" on public.creator_profiles;
create policy "creator_profiles_select_published"
    on public.creator_profiles for select
    using (status = 'published');

-- Ingen insert/update/delete-policy: all skrivning går via
-- SECURITY DEFINER-RPC:erna nedan.

create index if not exists creator_profiles_status_idx
    on public.creator_profiles (status)
    where status = 'published';
```

- [ ] **Step 3: Skriv hjälpfunktionerna för slug och validering**

```sql
-- Reserverade namn: en självbetjäningsprofil på en indexerbar sida under
-- plattformens egen domän får inte kunna utge sig för att vara officiell.
create or replace function app_private.creator_slug_is_reserved(p_value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select lower(trim(coalesce(p_value, ''))) = any (array[
        'promptbanken', 'admin', 'support', 'official', 'kontakt', 'system',
        'hoglandsforbundet', 'api', 'mcp', 'paket', 'creator', 'creators',
        'workshop', 'valvet'
    ]);
$$;

-- Samma svenska normalisering som areaAnchor i scripts/catalog-page-lib.mjs.
create or replace function app_private.creator_slugify(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
    select nullif(
        trim(both '-' from
            regexp_replace(
                regexp_replace(
                    lower(translate(coalesce(p_value, ''), 'åäöÅÄÖéèüÉÈÜ', 'aaoAAOeeuEEU')),
                    '[^a-z0-9]+', '-', 'g'
                ),
                '-+', '-', 'g'
            )
        ),
        ''
    );
$$;

create or replace function app_private.creator_url_is_valid(p_value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select p_value is null
        or trim(p_value) = ''
        or trim(p_value) ~* '^https?://[^\s<>"]+$';
$$;
```

- [ ] **Step 4: Skriv skriv-RPC:erna**

Följ mönstret från mönsterfilen: `app_private`-funktion + `public`-wrapper +
`revoke`/`grant`. Funktionerna ska ha dessa signaturer och beteenden:

```sql
create or replace function app_private.upsert_my_creator_profile(
    p_display_name text,
    p_slug text default null,
    p_bio_short text default null,
    p_bio_long text default null,
    p_competence_areas text[] default null,
    p_organisation text default null,
    p_website_url text default null,
    p_linkedin_url text default null
)
returns public.creator_profiles
```

Regler i funktionskroppen:
- `auth.uid()` måste finnas, annars `raise exception 'Du måste vara inloggad.'`
- `p_display_name` får inte vara tom efter trim → `'Visningsnamn krävs.'`
- Om `app_private.creator_slug_is_reserved(p_display_name)` → `'Det namnet är reserverat.'`
- Slug: använd `p_slug` om angiven, annars `app_private.creator_slugify(p_display_name)`. Om resultatet är null → `'Kunde inte skapa en giltig adress från namnet.'` Om `creator_slug_is_reserved(slug)` → `'Den adressen är reserverad.'`
- Om raden redan finns och `slug_locked` är true ignoreras inkommande slug helt (befintlig behålls).
- URL-validering: både `p_website_url` och `p_linkedin_url` måste klara `app_private.creator_url_is_valid`, annars `'Ogiltig länk. Använd en adress som börjar med http:// eller https://.'`
- Tomma strängar normaliseras till null.
- Upsert på `user_id`. Vid uppdatering skrivs alla angivna fält; utelämnade (`null`) fält lämnas orörda med `coalesce` mot befintlig kolumn — utom `p_display_name` som alltid är obligatorisk.
- `updated_at = now()`.

```sql
create or replace function app_private.publish_my_creator_profile()
returns public.creator_profiles
```
- Kräver inloggad användare och att profilen finns → `'Ingen profil att publicera.'`
- Tröskeln: `display_name` och `bio_short` båda icke-tomma efter trim. Annars `raise exception 'Fyll i namn och en kort presentation innan du publicerar.'`
- Sätter `status = 'published'`, `published_at = coalesce(published_at, now())`, `slug_locked = true`, `updated_at = now()`.

```sql
create or replace function app_private.unpublish_my_creator_profile()
returns public.creator_profiles
```
- Sätter `status = 'draft'`, `updated_at = now()`. `slug_locked` och `published_at` lämnas orörda.

- [ ] **Step 5: Skriv läs-RPC:erna**

```sql
create or replace function public.get_my_creator_profile()
returns setof public.creator_profiles
language sql
stable
security definer
set search_path = ''
as $$
    select * from public.creator_profiles where user_id = auth.uid();
$$;

revoke all on function public.get_my_creator_profile() from public;
grant execute on function public.get_my_creator_profile() to authenticated;
```

`list_published_creator_profiles()` och `get_published_creator_profile(p_slug text)`
returnerar bara publicerade rader och **utelämnar `avatar_url` och
`user_id`** ur returtabellen — de behövs inte publikt. Returnera:
`slug`, `display_name`, `bio_short`, `bio_long`, `competence_areas`,
`organisation`, `website_url`, `linkedin_url`, `published_at`.
Båda `stable`, `security definer`, `set search_path = ''`,
`grant execute ... to anon, authenticated` (generatorn använder anon-nyckeln).

- [ ] **Step 6: Skriv admin-RPC:erna**

`admin_update_creator_profile_slug(p_user_id uuid, p_slug text)` och
`admin_unpublish_creator_profile(p_user_id uuid)`, båda gated med
`if not app_private.current_user_is_platform_owner() then raise exception 'Endast plattformsägare kan hantera creator-profiler.'; end if;`
Slug-varianten validerar mot både formatmönstret och
`creator_slug_is_reserved`. Wrappers grantas till `authenticated`.

- [ ] **Step 7: Skriv verifieringsfilen**

`supabase/tests/verify_creator_profiles.sql` ska kontrollera, var och en som
en `select` som returnerar noll rader vid godkänt:
- tabellen finns med alla kolumner enligt spec
- RLS är aktiverad på tabellen (`pg_class.relrowsecurity`)
- båda select-policyerna finns
- alla åtta RPC:erna finns i rätt schema
- `app_private.creator_slugify('Anna Andersson')` ger `'anna-andersson'`
- `app_private.creator_slugify('Åsa Öberg')` ger `'asa-oberg'`
- `app_private.creator_slug_is_reserved('Promptbanken')` ger true
- `app_private.creator_url_is_valid('javascript:alert(1)')` ger false
- `app_private.creator_url_is_valid('https://example.com')` ger true

- [ ] **Step 8: Läs igenom migrationen en gång till**

Kontrollera att varje `public`-wrapper har både `revoke` och `grant`, att
varje funktion har `set search_path = ''`, och att ingen skriv-RPC saknar
kontroll av `auth.uid()`.

- [ ] **Step 9: Commit**

```bash
git add supabase/migrations/20260816090000_creator_profiles.sql supabase/tests/verify_creator_profiles.sql
git commit -m "feat: add creator_profiles table, RLS and RPCs"
```

Applicera **inte** mot produktion. Rapportera att prod-migrationen återstår.

---

### Task 2: Rena hjälpfunktioner för creator-sidor + tester

**Files:**
- Create: `scripts/creator-page-lib.mjs`
- Create: `scripts/creator-page-lib.test.mjs`
- Reference (läs, ändra inte): `scripts/catalog-page-lib.mjs`

**Interfaces:**
- Consumes: `escapeHtml`, `absoluteUrl`, `isSafeSlug` från `scripts/catalog-page-lib.mjs`.
- Produces:
  - `creatorUrl(slug: string): string` → `/creator/<slug>/`
  - `isProfileIndexable(profile: {display_name?, bio_short?}): boolean`
  - `initialsFrom(displayName: string): string` — max två versaler
  - `safeExternalUrl(value: unknown): string | null` — returnerar värdet bara om det är en http/https-URL, annars null
- Task 3 och 4 importerar dessa.

- [ ] **Step 1: Skriv de failande testerna**

```javascript
// scripts/creator-page-lib.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { creatorUrl, isProfileIndexable, initialsFrom, safeExternalUrl } from './creator-page-lib.mjs';

test('creatorUrl bygger rätt sökväg', () => {
    assert.equal(creatorUrl('anna-andersson'), '/creator/anna-andersson/');
});

test('isProfileIndexable kräver namn och kort presentation', () => {
    assert.equal(isProfileIndexable({ display_name: 'Anna', bio_short: 'Konsult' }), true);
    assert.equal(isProfileIndexable({ display_name: 'Anna', bio_short: '' }), false);
    assert.equal(isProfileIndexable({ display_name: 'Anna', bio_short: '   ' }), false);
    assert.equal(isProfileIndexable({ display_name: '', bio_short: 'Konsult' }), false);
    assert.equal(isProfileIndexable({}), false);
});

test('initialsFrom ger max två versaler', () => {
    assert.equal(initialsFrom('Anna Andersson'), 'AA');
    assert.equal(initialsFrom('anna'), 'A');
    assert.equal(initialsFrom('Anna Maria Andersson'), 'AA');
    assert.equal(initialsFrom('Åsa Öberg'), 'ÅÖ');
    assert.equal(initialsFrom(''), '');
    assert.equal(initialsFrom(null), '');
});

test('safeExternalUrl släpper bara igenom http och https', () => {
    assert.equal(safeExternalUrl('https://example.com'), 'https://example.com');
    assert.equal(safeExternalUrl('http://example.com/x?y=1'), 'http://example.com/x?y=1');
    assert.equal(safeExternalUrl('javascript:alert(1)'), null);
    assert.equal(safeExternalUrl('data:text/html,x'), null);
    assert.equal(safeExternalUrl('//evil.com'), null);
    assert.equal(safeExternalUrl('/relativ'), null);
    assert.equal(safeExternalUrl(''), null);
    assert.equal(safeExternalUrl(null), null);
    assert.equal(safeExternalUrl(undefined), null);
});
```

- [ ] **Step 2: Kör testerna och se dem faila**

Kör: `npm test`
Förväntat: FAIL — `Cannot find module ... creator-page-lib.mjs`.

- [ ] **Step 3: Implementera modulen**

```javascript
// scripts/creator-page-lib.mjs
// Rena hjälpfunktioner för statiska creator-profilsidor.
// Se docs/superpowers/specs/2026-08-16-creator-profiler-design.md.

export function creatorUrl(slug) {
    return `/creator/${slug}/`;
}

function hasText(value) {
    return typeof value === 'string' && value.trim() !== '';
}

// Samma princip som paketens tröskel: en profil med bara ett namn är inget
// att skicka till en sökmotor.
export function isProfileIndexable(profile) {
    return hasText(profile?.display_name) && hasText(profile?.bio_short);
}

export function initialsFrom(displayName) {
    if (!hasText(displayName)) return '';
    return displayName
        .trim()
        .split(/\s+/)
        .slice(0, 2)
        .map((part) => part.charAt(0).toUpperCase())
        .join('');
}

// Bara http/https får renderas. Utan den här spärren kan en
// självbetjäningsprofil injicera javascript:- eller data:-länkar, och
// protokollrelativa adresser (//evil.com) blir tysta utgångar från domänen.
export function safeExternalUrl(value) {
    if (typeof value !== 'string' || value.trim() === '') return null;
    const trimmed = value.trim();
    if (!/^https?:\/\//i.test(trimmed)) return null;
    return trimmed;
}
```

- [ ] **Step 4: Kör testerna igen**

Kör: `npm test`
Förväntat: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/creator-page-lib.mjs scripts/creator-page-lib.test.mjs
git commit -m "feat: add pure helpers for creator profile pages"
```

---

### Task 3: Sidmallar för creator-profil och översikt + tester

**Files:**
- Create: `scripts/creator-page-template.mjs`
- Create: `scripts/creator-page-template.test.mjs`
- Reference (läs, ändra inte): `scripts/catalog-page-template.mjs` — följ dess struktur för `head()`, `siteHeader()`, `siteFooter()`, `breadcrumbs()` och JSON-LD-escaping

**Interfaces:**
- Consumes: `escapeHtml`, `absoluteUrl` från `catalog-page-lib.mjs`; `creatorUrl`, `initialsFrom`, `safeExternalUrl` från `creator-page-lib.mjs`.
- Produces: `renderCreatorPage({ profile, indexable }): string` och `renderCreatorIndexPage({ profiles, indexable }): string`. Task 4 anropar dem.

- [ ] **Step 1: Skriv de failande testerna**

```javascript
// scripts/creator-page-template.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { renderCreatorPage, renderCreatorIndexPage } from './creator-page-template.mjs';

const baseProfile = {
    slug: 'anna-andersson',
    display_name: 'Anna Andersson',
    bio_short: 'AI-konsult och utbildare.',
    bio_long: 'Arbetar med införande av AI i offentlig sektor.',
    competence_areas: ['Ledarskap', 'Förändringsledning'],
    organisation: 'Exempelbolaget AB',
    website_url: 'https://example.com',
    linkedin_url: 'https://linkedin.com/in/anna'
};

function render(overrides = {}) {
    return renderCreatorPage({ profile: baseProfile, indexable: true, ...overrides });
}

test('sidan har dokumentstruktur, H1 och canonical', () => {
    const html = render();
    assert.match(html, /^<!DOCTYPE html>/);
    assert.match(html, /<html lang="sv">/);
    assert.match(html, /<h1[^>]*>Anna Andersson<\/h1>/);
    assert.match(html, /<link rel="canonical" href="https:\/\/app\.promptbanken\.se\/creator\/anna-andersson\/">/);
});

test('sidan markerar tydligt att innehållet är från en creator', () => {
    assert.match(render(), /Creator på Promptbanken/);
});

test('initialer renderas i stället för avatarbild', () => {
    const html = render();
    assert.match(html, /AA/);
    assert.doesNotMatch(html, /<img/);
});

test('externa länkar har nofollow och noopener', () => {
    const html = render();
    assert.match(html, /href="https:\/\/example\.com"[^>]*rel="nofollow noopener"/);
    assert.match(html, /href="https:\/\/linkedin\.com\/in\/anna"[^>]*rel="nofollow noopener"/);
});

test('farliga länkar renderas inte alls', () => {
    const html = render({
        profile: { ...baseProfile, website_url: 'javascript:alert(1)', linkedin_url: '//evil.com' }
    });
    assert.doesNotMatch(html, /javascript:/);
    assert.doesNotMatch(html, /evil\.com/);
});

test('nollägessektioner finns för paket, prompts och krediter', () => {
    const html = render();
    assert.match(html, /Publicerade paket/);
    assert.match(html, /Publicerade prompts/);
    assert.match(html, /Workshopkrediter/);
    assert.match(html, /Inget publicerat ännu/);
});

test('icke-indexerbar profil får noindex', () => {
    assert.doesNotMatch(render(), /noindex/);
    assert.match(render({ indexable: false }), /<meta name="robots" content="noindex">/);
});

test('all profiltext escapas', () => {
    const html = render({
        profile: { ...baseProfile, display_name: '<script>alert(1)</script>', organisation: '"co" & co' }
    });
    assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
    assert.match(html, /&lt;script&gt;/);
    assert.match(html, /&quot;co&quot; &amp; co/);
});

test('JSON-LD innehåller Person och BreadcrumbList och kan inte bryta ut', () => {
    const html = render({ profile: { ...baseProfile, display_name: 'A</script><b>' } });
    assert.match(html, /"@type":\s*"Person"/);
    assert.match(html, /"@type":\s*"BreadcrumbList"/);
    assert.doesNotMatch(html, /A<\/script><b>/);
});

test('tomma valfria fält utelämnas', () => {
    const html = render({
        profile: { slug: 'x', display_name: 'X', bio_short: 'Kort' }
    });
    assert.doesNotMatch(html, /Organisation/);
    assert.doesNotMatch(html, /Kompetensområden/);
});

test('översikten listar profiler och länkar rätt', () => {
    const html = renderCreatorIndexPage({
        profiles: [{ slug: 'anna-andersson', display_name: 'Anna Andersson', bio_short: 'Konsult' }],
        indexable: true
    });
    assert.match(html, /href="\/creator\/anna-andersson\/"/);
    assert.match(html, /<link rel="canonical" href="https:\/\/app\.promptbanken\.se\/creator\/">/);
});

test('tom översikt får noindex', () => {
    const html = renderCreatorIndexPage({ profiles: [], indexable: false });
    assert.match(html, /<meta name="robots" content="noindex">/);
});
```

- [ ] **Step 2: Kör testerna och se dem faila**

Kör: `npm test`
Förväntat: FAIL — modulen saknas.

- [ ] **Step 3: Implementera mallmodulen**

Bygg `scripts/creator-page-template.mjs` efter samma struktur som
`scripts/catalog-page-template.mjs`. Läs den filen först och återanvänd dess
`head()`, `siteHeader()`, `siteFooter()`, `breadcrumbs()` och
JSON-LD-hjälpare — kopiera dem in i den nya modulen om de inte är
exporterade, hellre än att ändra den befintliga filen.

Krav:
- Brödsmulor: Hem › Creators › namnet, med `<nav aria-label>` och
  `aria-current="page"` på sista steget.
- `<h1>` = `display_name`. Direkt under: initialer från `initialsFrom` i ett
  element med `aria-hidden="true"` (dekorativt), och raden
  "Creator på Promptbanken".
- `bio_short` som ingress, `bio_long` som brödtext, båda utelämnade om tomma.
- Organisation och kompetensområden bara om ifyllda.
- Länkar renderas bara om `safeExternalUrl` returnerar ett värde, och alltid
  med `rel="nofollow noopener"` och `target="_blank"`.
- Tre nollägessektioner med rubrikerna "Publicerade paket",
  "Publicerade prompts" och "Workshopkrediter", var och en med texten
  "Inget publicerat ännu."
- Metadata: `<title>` = `${display_name} | Promptbanken`, description =
  `bio_short`, canonical mot `creatorUrl(slug)`, OG-taggar i samma form som
  paketsidorna, `noindex` när `indexable` är false.
- JSON-LD: `BreadcrumbList` och `Person` (`name`, och `url` mot den
  absoluta profil-URL:en). Använd samma `<`-escaping som
  `catalog-page-template.mjs` gör.
- `renderCreatorIndexPage({ profiles, indexable })` listar profilerna med
  namn som länk och `bio_short` som beskrivning, canonical mot `/creator/`.

- [ ] **Step 4: Kör testerna**

Kör: `npm test`
Förväntat: PASS, alla tester gröna.

- [ ] **Step 5: Commit**

```bash
git add scripts/creator-page-template.mjs scripts/creator-page-template.test.mjs
git commit -m "feat: add HTML templates for creator profile pages"
```

---

### Task 4: Generatorn genererar creator-sidor

**Files:**
- Modify: `scripts/generate-catalog-pages.mjs`

**Interfaces:**
- Consumes: `list_published_creator_profiles` (Task 1), `renderCreatorPage`/`renderCreatorIndexPage` (Task 3), `creatorUrl`/`isProfileIndexable` (Task 2).
- Produces: `dist/creator/<slug>/index.html`, `dist/creator/index.html`, samt creator-URL:er i `dist/sitemap.xml`.

- [ ] **Step 1: Läs generatorn**

Öppna `scripts/generate-catalog-pages.mjs` och läs hela filen. Notera hur
paketen hämtas, hur `isSafeSlug` filtrerar innan filskrivning, hur
indexerbarhet avgör sitemap-inklusion, och hur `/paket/`-översikten bara
blir indexerbar när minst ett paket kvalificerar. Creator-delen ska följa
exakt samma mönster.

- [ ] **Step 2: Lägg till creator-generering**

Efter paketgenereringen, före sitemap-bygget:

```javascript
    const profiles = await rpc('list_published_creator_profiles', {});

    const usableProfiles = profiles.filter((profile) => {
        if (isSafeSlug(profile.slug)) return true;
        console.warn(`[generate-catalog-pages] hoppar över profil med osäker slug: ${JSON.stringify(profile.slug)}`);
        return false;
    });

    const indexableProfiles = usableProfiles.filter(isProfileIndexable);
    const creatorUrls = indexableProfiles.map((profile) => absoluteUrl(creatorUrl(profile.slug)));

    for (const profile of usableProfiles) {
        await writePage(
            `creator/${profile.slug}`,
            renderCreatorPage({ profile, indexable: isProfileIndexable(profile) })
        );
    }

    // Utan minst en kvalificerad profil är översikten en tom sida -- den ska
    // varken indexeras eller ligga i sitemap.
    const creatorIndexIsIndexable = indexableProfiles.length > 0;
    await writePage(
        'creator',
        renderCreatorIndexPage({ profiles: indexableProfiles, indexable: creatorIndexIsIndexable })
    );
```

Lägg till importer överst för `creatorUrl`, `isProfileIndexable`,
`renderCreatorPage` och `renderCreatorIndexPage`.

I sitemap-bygget, lägg till efter paketets URL:er:

```javascript
        ...(creatorIndexIsIndexable ? [absoluteUrl('/creator/')] : []),
        ...creatorUrls,
```

Uppdatera slututskriften så den även nämner antalet profiler.

- [ ] **Step 3: Verifiera att bygget fortfarande beter sig rätt**

Kör: `npm run build`
Förväntat: exit 0, utskriften nämner att generering hoppas över (inga
env-variabler lokalt).

Kör: `CI=1 npm run build`
Förväntat: exit skild från 0 med tydligt felmeddelande.

Kör: `npm test`
Förväntat: alla tester gröna.

- [ ] **Step 4: Commit**

```bash
git add scripts/generate-catalog-pages.mjs
git commit -m "feat: generate static creator profile pages at build time"
```

---

### Task 5: Appsida för att redigera och publicera profilen

**Files:**
- Create: `creator.html`
- Create: `src/creatorProfile.js`
- Modify: `vite.config.js` (lägg till `creator` i `rollupOptions.input`)
- Reference (läs, ändra inte): `src/adminPackageSeo.js` — följ dess struktur för Supabase-anrop, felhantering och formulärhantering
- Reference (läs, ändra inte): `src/auth.js`, `login.html`

**Interfaces:**
- Consumes: `get_my_creator_profile`, `upsert_my_creator_profile`, `publish_my_creator_profile`, `unpublish_my_creator_profile` (Task 1).
- Produces: inget som andra tasks konsumerar.

- [ ] **Step 1: Läs mönsterfilerna**

Läs `src/adminPackageSeo.js` i sin helhet och `src/auth.js`. Följ deras
konventioner för sessionshantering, Supabase-klient, felmeddelanden och
DOM-uppbyggnad. Titta också på hur `admin.html` är uppbyggd som sida.

- [ ] **Step 2: Bygg sidan**

`creator.html` med samma head-mönster som övriga appsidor (favicons,
`style.css`), `<meta name="robots" content="noindex">` (det här är en
inloggad arbetsyta, inte en publik sida), och ett formulär med fälten:
visningsnamn, adress/slug, kort presentation, längre presentation,
kompetensområden (kommaseparerat), organisation, webbplats, LinkedIn.

Sidan ska också visa:
- Den publika adressen `app.promptbanken.se/creator/<slug>/`, och när
  profilen är publicerad även en länk dit.
- Ett tydligt statusbesked: utkast eller publicerad.
- Om profilen når publiceringströskeln (namn och kort presentation ifyllda).
  Använd samma regel som `isProfileIndexable` — dubbelkolla mot
  `scripts/creator-page-lib.mjs` så villkoren inte glider isär.
- Att adressen låses vid publicering, innan användaren publicerar.
- Nollstate-sektioner: "Dina paket", "Dina prompts", "Workshopkrediter",
  var och en med en kort förklaring om att funktionen kommer.

- [ ] **Step 3: Bygg modulen**

`src/creatorProfile.js` ska kräva inloggad session (annars visa ett
meddelande med länk till `login.html`), hämta befintlig profil via
`get_my_creator_profile`, fylla formuläret, spara via
`upsert_my_creator_profile`, samt publicera/avpublicera. Fel från RPC:erna
(som är på svenska) visas för användaren som de är.

Kompetensområden skickas som array — dela på komma och trimma.
Tomma fält skickas som tom sträng, inte null, så att de faktiskt kan rensas.

- [ ] **Step 4: Registrera sidan i bygget**

I `vite.config.js`, i `build.rollupOptions.input`, lägg till:

```javascript
        creator: resolve(__dirname, 'creator.html'),
```

- [ ] **Step 5: Verifiera**

Kör: `npm run build` — förväntat: lyckas, `dist/creator.html` finns.
Kör: `npm test` — förväntat: gröna.

Manuell verifiering kräver en databas med Task 1:s migration applicerad.
Om ingen sådan finns: rapportera det tydligt i stället för att påstå att
flödet är testat.

- [ ] **Step 6: Commit**

```bash
git add creator.html src/creatorProfile.js vite.config.js
git commit -m "feat: add creator profile editing page"
```

---

### Task 6: 404-fallback och adminvy

**Files:**
- Modify: `404.html`
- Create: `src/adminCreatorProfiles.js`
- Modify: `admin.html`

**Interfaces:**
- Consumes: `list_published_creator_profiles`, `admin_update_creator_profile_slug`, `admin_unpublish_creator_profile` (Task 1).

- [ ] **Step 1: Utöka 404-sidan**

`404.html` har redan ett inline-script som fångar `/paket/<slug>/` och
skickar vidare till appen. Lägg till en gren för `/creator/<slug>/`.

Till skillnad från paket finns ingen appvy att skicka vidare till, så gör
ingen omdirigering. Visa i stället ett eget meddelande på sidan:
"Profilen publiceras inom ett dygn." Slugen valideras mot samma strikta
mönster som paketgrenen redan använder, och får **aldrig** skrivas till
DOM:en som HTML — visa ett fast meddelande, injicera inte slugen i texten.

- [ ] **Step 2: Bygg adminmodulen**

`src/adminCreatorProfiles.js` listar creator-profiler och erbjuder exakt två
åtgärder: avpublicera och ändra slug. Följ mönstret i
`src/adminPackageSeo.js` för anrop, felhantering och behörighetsbesked
(RPC:erna vägrar för icke-plattformsägare, och felet visas för användaren).

Lägg till en `<section>` i `admin.html` med id `creator-profiler` och en
nav-länk i samma mönster som `#paket-seo`, plus
`<script type="module" src="/src/adminCreatorProfiles.js"></script>`.

Lägg **ingen** kod i `src/admin.js`.

- [ ] **Step 3: Verifiera**

Kör: `npm run build` — förväntat: lyckas.
Kör: `npm test` — förväntat: gröna.

Kontrollera i den byggda `dist/404.html` att creator-grenen finns och att
ingen slug skrivs in i sidans text.

- [ ] **Step 4: Commit**

```bash
git add 404.html src/adminCreatorProfiles.js admin.html
git commit -m "feat: add creator 404 fallback and admin moderation view"
```

---

## Self-review

**Spec coverage:**
- Tabell, RLS, RPC:er, reserverade namn, URL-validering, slug-låsning → Task 1.
- Indexerbarhetströskel → Task 2 (`isProfileIndexable`), tillämpad i Task 3, 4, 5.
- Profilsida med källrad, nollägen, nofollow-länkar, Person-JSON-LD → Task 3.
- `/creator/`-översikt och sitemap → Task 3, Task 4.
- Statisk generering i befintligt byggsteg → Task 4.
- Appsida för redigering och publicering → Task 5.
- 404-fallback → Task 6.
- Admin: avpublicera och ändra slug → Task 6.
- Avatarer medvetet oanvända → Task 1 (kolumn med kommentar), Task 3 (initialer, test som förbjuder `<img>`).

**Type consistency:** `creatorUrl(slug)`, `isProfileIndexable(profile)`,
`initialsFrom(displayName)`, `safeExternalUrl(value)`,
`renderCreatorPage({profile, indexable})`,
`renderCreatorIndexPage({profiles, indexable})` — samma namn och signaturer i
Task 2, 3, 4 och 5.

**Placeholders:** Task 1, 3, 5 och 6 beskriver delar i prosa i stället för
fullständig kod, eftersom implementationen måste följa mönster i namngivna
befintliga filer (`20260728120000_admin_catalog_authoring.sql`,
`catalog-page-template.mjs`, `adminPackageSeo.js`). Alla mönsterfiler och
alla regler är namngivna exakt; inga TBD.
