# Delningsbar länk för promptpaket Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paket i den öppna katalogen (`promptbanken.html`) kan öppnas via en delningsbar URL (`?package=<slug>`) och delas via en Dela-knapp i detaljvyn.

**Architecture:** Ren frontend-ändring i `script.js`/`promptbanken.html`/`style.css` — läser/skriver `location.search` och `history` runt den redan existerande `openCatalogPackageDetail(slug)`-funktionen. En ny Supabase-migration lägger till `package_share` som tillåtet `event_type` i `library_usage_events` så delningsklick kan loggas via befintlig `track_library_usage_event`-RPC.

**Tech Stack:** Vanilla JS (`script.js`, ej modul/bundlad), statisk HTML, Supabase Postgres-migration (SQL).

## Global Constraints

- `script.js` är inte bundlad av Vite — inga `import`-satser, håll allt självständigt (CLAUDE.md).
- Prompt-/paketinnehåll (`prompts/*.txt`, JSON-register) rörs inte av denna feature.
- Ingen server-side rendering läggs till (statiska SEO-sidor är uttryckligen utanför scope, se spec).
- Ingen AdSense/annonsering läggs till.
- MCP-servern (`mcp-server/`) rörs inte — detta är enbart webbappen.
- Design-spec: `docs/superpowers/specs/2026-08-11-package-share-link-design.md` — varje krav där ska ha en task nedan.

---

### Task 1: Supabase-migration — tillåt `package_share`-event

**Files:**
- Create: `supabase/migrations/20260812090000_library_usage_package_share_event.sql`
- Reference (läs, ändra inte): `supabase/migrations/20260729082734_open_library_usage_events.sql`
- Reference (läs, ändra inte): `supabase/tests/verify_library_usage_events.sql`

**Interfaces:**
- Consumes: befintlig tabell `public.library_usage_events` och funktion
  `public.track_library_usage_event(p_source text, p_event_type text, p_outcome text default 'success', p_prompt_slug text default null, p_package_slug text default null, p_context_keys text[] default null, p_area text default null, p_risk_level text default null, p_result_count integer default null, p_catalog_version text default null, p_metadata jsonb default '{}'::jsonb) returns jsonb`
  (definierad i `20260729082734_open_library_usage_events.sql:143`).
- Produces: samma RPC-signatur, men `p_event_type` accepterar även `'package_share'`. Task 3 anropar detta via `callCatalogRpc('track_library_usage_event', { p_event_type: 'package_share', ... })`.

- [ ] **Step 1: Skriv migrationen**

```sql
-- supabase/migrations/20260812090000_library_usage_package_share_event.sql
-- Lägger till 'package_share' som tillåtet event_type för
-- library_usage_events, för att kunna logga klick på "Dela paket" i
-- öppna katalogen. Se docs/superpowers/specs/2026-08-11-package-share-link-design.md.

alter table public.library_usage_events
    drop constraint library_usage_event_type_check;

alter table public.library_usage_events
    add constraint library_usage_event_type_check
      check (event_type in (
        'prompt_view', 'prompt_copy', 'prompt_get', 'prompt_list',
        'package_view', 'package_get', 'package_list', 'package_prompts_list',
        'package_share',
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
        'package_share',
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

    return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.track_library_usage_event(
    text, text, text, text, text, text[], text, text, integer, text, jsonb
) to anon, authenticated;
```

- [ ] **Step 2: Verifiera constraint och RPC lokalt/mot staging**

Kör (kräver `psql`-anslutning eller Supabase SQL-editor mot staging, inte prod
direkt — se AGENTS.md för miljöval):

```sql
select public.track_library_usage_event(
    p_source := 'web',
    p_event_type := 'package_share',
    p_package_slug := 'test-slug'
);
```

Förväntat: `{"ok": true}`, ingen exception. Kör därefter samma anrop med
`p_event_type := 'package_share_x'` och förvänta `Ogiltig statistiktyp.`-fel
(bekräftar att whitelisten fortfarande är strikt, inte bara öppnad för allt).

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260812090000_library_usage_package_share_event.sql
git commit -m "feat: allow package_share event type for library usage tracking"
```

**OBS till exekverande agent:** applicera inte migrationen mot produktion
utan uttrycklig bekräftelse från användaren — den är hard-to-reverse
(DDL på delad tabell). Verifiera mot staging/länkad utvecklingsdatabas
enligt Step 2, flagga sedan till användaren att prod-migrationen väntar.

---

### Task 2: HTML/CSS — Dela-knapp och felbanner-markup

**Files:**
- Modify: `promptbanken.html:295-303`
- Modify: `style.css` (nära `.catalog-detail-close`-blocket, `style.css:5959-5981`)

**Interfaces:**
- Produces: DOM-element `#catalog-detail-share` (knapp, alltid i markupen,
  synlighet styrs av JS i Task 3 via `hidden`-attribut) och
  `#catalog-package-link-error` (banner, `hidden` som default). Task 3
  och Task 4 refererar till dessa id:n.

- [ ] **Step 1: Lägg till felbanner ovanför paketgridden**

I `promptbanken.html`, rad 294-295, lägg till bannern direkt före
`catalog-package-grid`:

```html
                    <h3>Paket och arbetssätt</h3>
                    <div class="catalog-package-link-error" id="catalog-package-link-error" hidden role="alert">
                        Paketet kunde inte hittas eller är inte längre publicerat.
                    </div>
                    <div class="catalog-grid" id="catalog-package-grid"></div>
```

- [ ] **Step 2: Lägg till Dela-knappen i detaljpanelen**

I `promptbanken.html`, rad 297-303, lägg till knappen mellan panel-div och
stängknappen (den renderas till vänster om krysset via CSS `right`-offset,
se Step 4):

```html
                    <div class="catalog-prompt-detail" id="catalog-prompt-detail" hidden>
                        <div class="catalog-detail-panel">
                            <button type="button" class="catalog-detail-share" id="catalog-detail-share" aria-label="Kopiera länk till paketet" hidden>🔗</button>
                            <button type="button" class="catalog-detail-close" id="catalog-detail-close" aria-label="Stäng">×</button>
                            <div class="catalog-detail-tabs" id="catalog-detail-tabs"></div>
                            <div class="catalog-detail-body" id="catalog-detail-body"></div>
                        </div>
                    </div>
```

- [ ] **Step 3: CSS för felbannern**

Lägg till i `style.css`, direkt efter `.catalog-empty-state`-blocket
(runt rad 5804 — sök `.catalog-empty-state {` och infoga efter dess
avslutande `}`):

```css
.catalog-package-link-error {
    background: #fdecea;
    color: #611a15;
    border: 1px solid #f5c6cb;
    border-radius: 6px;
    padding: 0.75rem 1rem;
    margin-bottom: 1rem;
}
```

- [ ] **Step 4: CSS för Dela-knappen**

Lägg till i `style.css` direkt efter `.catalog-detail-close:hover`-blocket
(efter rad 5981):

```css
.catalog-detail-share {
    position: absolute;
    top: 0.75rem;
    right: 3.25rem;
    background: none;
    border: none;
    font-size: 1.1rem;
    line-height: 1;
    cursor: pointer;
    color: #666;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 4px;
    transition: background-color 0.2s ease, color 0.2s ease;
}

.catalog-detail-share:hover {
    background-color: #f0f0f0;
    color: #1a1a1a;
}

.catalog-detail-share.copied {
    color: #1a7f37;
}
```

- [ ] **Step 5: Manuell koll**

Öppna `promptbanken.html` lokalt (`npm run web:dev`), bekräfta att sidan
laddar utan konsolfel och att knappen/bannern (dolda som default) inte
stör layouten. Ingen synlig skillnad förväntas ännu — knapp och banner är
`hidden`.

- [ ] **Step 6: Commit**

```bash
git add promptbanken.html style.css
git commit -m "feat: add share button and link-error banner markup for packages"
```

---

### Task 3: JS — URL-synk, pushState/popstate och stäng-rensning

**Files:**
- Modify: `script.js:1009-1055` (`openCatalogPackageDetail`, stäng-lyssnaren)
- Modify: `script.js:328` (referens, `LIBRARY_USAGE_SAFE_SLUG` — används av
  `getSafeLibraryUsagePackageSlug`, se nedan; ingen ändring av regexen)
- Test: manuell browserverifiering (se Step 6) — `script.js` har ingen
  automatisk testsvit (vanilla, obundlad, se CLAUDE.md).

**Interfaces:**
- Consumes: `setCatalogDetailPanelOpen(open: boolean)` (script.js:604),
  `callCatalogRpc`, `getActiveContextKeys`, `getActiveCatalogContextKeys`,
  `shouldTrackLibraryUsage`, `trackLibraryUsageEvent`, alla oförändrade.
- Produces:
  - `function getPackageSlugFromLocation(): string | null` — läser
    `?package=` från `location.search`.
  - `openCatalogPackageDetail(slug: string): Promise<boolean>` — **ändrad
    signatur**: returnerar nu `true` vid lyckad öppning, `false` vid
    misslyckande (tidigare: `undefined`/`void`). Task 4 använder
    returvärdet.
  - `function closeCatalogDetailPanel(): void` — stänger panelen och
    rensar `?package=`-parametern om den finns.

- [ ] **Step 1: Lägg till `getPackageSlugFromLocation`**

Lägg till strax ovanför `async function openCatalogPackageDetail(slug)`
(script.js:1009):

```javascript
function getPackageSlugFromLocation() {
    return new URLSearchParams(window.location.search).get('package') || null;
}
```

- [ ] **Step 2: Gör `openCatalogPackageDetail` returnera boolean och synka URL**

Ersätt hela funktionen (script.js:1009-1051):

```javascript
async function openCatalogPackageDetail(slug) {
    const panel = document.getElementById('catalog-prompt-detail');
    const tabsContainer = document.getElementById('catalog-detail-tabs');
    if (!panel || !tabsContainer) return false;

    try {
        catalogDetailVariants = (await callCatalogRpc('get_published_package', {
            p_slug: slug,
            p_context_keys: getActiveContextKeys()
        })).map(normalizeCatalogTemplateEntity);
    } catch (error) {
        console.error('Kunde inte ladda paketdetaljer:', error);
        return false;
    }

    if (!catalogDetailVariants.length) return false;

    try {
        catalogDetailPackageItems = await callCatalogRpc('list_published_package_prompts', {
            p_package_slug: slug,
            p_context_keys: getActiveContextKeys()
        });
    } catch (error) {
        console.error('Kunde inte ladda paketets prompter:', error);
        catalogDetailPackageItems = [];
    }

    renderCatalogDetailTabs(catalogDetailVariants);
    renderCatalogDetailVariant(catalogDetailVariants[0]);
    setCatalogDetailPanelOpen(true);

    const desiredSearch = `?package=${encodeURIComponent(slug)}`;
    if (window.location.search !== desiredSearch) {
        window.history.pushState({ catalogPackageSlug: slug }, '', desiredSearch);
    }

    const shareButton = document.getElementById('catalog-detail-share');
    if (shareButton) {
        shareButton.hidden = false;
        shareButton.dataset.catalogPackageSlug = slug;
    }

    const packageViewKey = `package_view:${slug}:${getActiveCatalogContextKeys().join(',')}`;
    if (shouldTrackLibraryUsage(packageViewKey, 60 * 60 * 1000)) {
        const packageType = catalogDetailVariants[0]?.package_type;
        trackLibraryUsageEvent({
            eventType: 'package_view',
            packageSlug: slug,
            metadata: packageType === 'collection' || packageType === 'workflow'
                ? { package_type: packageType }
                : {}
        });
    }

    return true;
}
```

(`isPrompt`-döljningen av Dela-knappen för promptvyn hanteras i Task 4,
Step 1, inuti `renderCatalogDetailVariant`.)

- [ ] **Step 3: Ersätt stäng-lyssnaren med `closeCatalogDetailPanel`**

Ersätt (script.js:1053-1055):

```javascript
document.getElementById('catalog-detail-close')?.addEventListener('click', () => {
    setCatalogDetailPanelOpen(false);
});
```

med:

```javascript
function closeCatalogDetailPanel() {
    setCatalogDetailPanelOpen(false);
    const shareButton = document.getElementById('catalog-detail-share');
    if (shareButton) shareButton.hidden = true;
    if (getPackageSlugFromLocation()) {
        window.history.replaceState(null, '', window.location.pathname);
    }
}

document.getElementById('catalog-detail-close')?.addEventListener('click', () => {
    closeCatalogDetailPanel();
});
```

- [ ] **Step 4: Lägg till `popstate`-lyssnare**

Lägg till direkt efter blocket från Step 3:

```javascript
window.addEventListener('popstate', () => {
    const slug = getPackageSlugFromLocation();
    const panel = document.getElementById('catalog-prompt-detail');
    if (!slug) {
        if (panel && !panel.hidden) {
            setCatalogDetailPanelOpen(false);
            const shareButton = document.getElementById('catalog-detail-share');
            if (shareButton) shareButton.hidden = true;
        }
        return;
    }
    openCatalogPackageDetail(slug);
});
```

- [ ] **Step 5: Manuell verifiering i browser**

`npm run web:dev`, öppna `promptbanken.html`. Klicka ett paket i
"Paket och arbetssätt" — bekräfta i devtools att `location.search` blir
`?package=<slug>`. Klicka stäng — bekräfta att `location.search` töms.
Klicka paketet igen, tryck webbläsarens bakåtknapp — bekräfta att panelen
stängs och URL:en rensas utan att sidan laddas om.

- [ ] **Step 6: Commit**

```bash
git add script.js
git commit -m "feat: sync package detail URL with history state"
```

---

### Task 4: JS — Dela-knapp, initial deep-link och felbanner

**Files:**
- Modify: `script.js:895-944` (`renderCatalogDetailVariant`)
- Modify: `script.js:3488-3504` (init-lyssnaren)

**Interfaces:**
- Consumes: `openCatalogPackageDetail(slug): Promise<boolean>` och
  `getPackageSlugFromLocation()` från Task 3; `trackLibraryUsageEvent`
  (script.js:393) med nytt `eventType: 'package_share'`.
- Produces: inget nytt som andra tasks konsumerar — detta är sista tasken
  i kedjan.

- [ ] **Step 1: Dölj Dela-knappen för promptvyn i `renderCatalogDetailVariant`**

I `renderCatalogDetailVariant` (script.js:895-928), lägg till direkt efter
raden `const isPrompt = 'prompt_text' in normalizedVariant;` (script.js:899):

```javascript
    const shareButton = document.getElementById('catalog-detail-share');
    if (shareButton) {
        shareButton.hidden = isPrompt;
        if (!isPrompt) shareButton.dataset.catalogPackageSlug = normalizedVariant.slug || '';
    }
```

(Detta täcker även fallet då `openCatalogPromptDetail` återanvänder samma
panel — knappen döljs där, precis som spec kräver.)

- [ ] **Step 2: Klick-lyssnare för Dela-knappen**

Lägg till som ny funktion, placerad direkt efter
`closeCatalogDetailPanel`-blocket (Task 3, Step 3):

```javascript
document.getElementById('catalog-detail-share')?.addEventListener('click', async (event) => {
    const button = event.currentTarget;
    const slug = button.dataset.catalogPackageSlug;
    if (!slug) return;

    const url = `${window.location.origin}${window.location.pathname}?package=${encodeURIComponent(slug)}`;
    try {
        await navigator.clipboard.writeText(url);
        trackLibraryUsageEvent({ eventType: 'package_share', packageSlug: slug });
        const originalContent = button.textContent;
        button.textContent = '✓';
        button.classList.add('copied');
        button.setAttribute('aria-label', 'Länk kopierad');
        setTimeout(() => {
            button.textContent = originalContent;
            button.classList.remove('copied');
            button.setAttribute('aria-label', 'Kopiera länk till paketet');
        }, 2000);
    } catch (error) {
        console.error('Kunde inte kopiera länken:', error);
        alert('Kunde inte kopiera länken. Kopiera adressen från adressfältet istället.');
    }
});
```

- [ ] **Step 3: Initial deep-link vid sidladdning**

Ersätt init-blocket (script.js:3488-3504):

```javascript
        // Load prompts on page load
        window.addEventListener('DOMContentLoaded', async () => {
            initAdvancedToggle();
            initFavoritesToggle();
            initLocalChatToggle();
            initGlobalRenderControls();
            initPromptSearch();
            initPromptSort();
            initCategoryFilters();
            loadPrompts();
            renderCatalogProfileFilters();
            renderGlobalContextStatus();
            loadCatalogPrompts();
            await loadCatalogPackages();
            loadExportSettings();
            registerExportSettingsListeners();

            const initialPackageSlug = getPackageSlugFromLocation();
            if (initialPackageSlug) {
                const opened = await openCatalogPackageDetail(initialPackageSlug);
                if (!opened) {
                    window.history.replaceState(null, '', window.location.pathname);
                    const errorBanner = document.getElementById('catalog-package-link-error');
                    if (errorBanner) errorBanner.hidden = false;
                }
            }
        });
```

- [ ] **Step 4: Manuell verifiering — lyckad delning**

`npm run web:dev`, öppna ett paket, klicka Dela-knappen. Bekräfta:
knappen visar ✓ i 2s och återgår, urklipp innehåller en URL i formen
`http://<host>/promptbanken.html?package=<slug>`. Klistra in URL:en i en
ny flik — bekräfta att paketets detaljvy öppnas direkt vid load.

- [ ] **Step 5: Manuell verifiering — trasig länk**

Öppna `promptbanken.html?package=finns-definitivt-inte` manuellt.
Bekräfta: felbannern ("Paketet kunde inte hittas...") syns ovanför
paketgridden, URL:en är rensad till `promptbanken.html`, och resten av
katalogen (prompts + paket-grid) renderas normalt.

- [ ] **Step 6: Manuell verifiering — prompt-detaljvyn påverkas inte**

Klicka "Förhandsvisa" på en enskild prompt (inte paket) i
`catalog-prompt-grid`. Bekräfta att Dela-knappen är dold i den panelen och
att `location.search` inte ändras.

- [ ] **Step 7: Commit**

```bash
git add script.js
git commit -m "feat: add package share button and deep-link handling"
```

---

## Self-review

**Spec coverage:**
- Deep-link vid load → Task 4, Step 3.
- pushState/replaceState vid interaktion + popstate → Task 3, Step 2–4.
- Dela-knapp med kopiera + feedback → Task 2, Task 4 Step 1–2.
- Fel-fall (paket saknas) → Task 2 Step 1 (banner-markup), Task 4 Step 3+5.
- Tracking (`package_share`) → Task 1 (DB-stöd) + Task 4 Step 2 (anrop).
- Knappen bara för paket, inte prompt → Task 4 Step 1.

**Type consistency:** `openCatalogPackageDetail` returnerar `boolean`
konsekvent i Task 3 och konsumeras så i Task 4. `getPackageSlugFromLocation`
har samma namn/signatur i alla tre användningsställen (Task 3 Step 1, 3, 4;
Task 4 Step 3). `#catalog-detail-share` och `#catalog-package-link-error`
id:n matchar mellan HTML (Task 2) och JS (Task 3, 4).

**Placeholders:** inga TBD/TODO; alla steg har fullständig kod.
