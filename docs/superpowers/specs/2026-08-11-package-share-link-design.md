# Delningsbar länk för promptpaket — design

Datum: 2026-08-11
Status: godkänd, redo för implementationsplan

## Syfte

Promptpaket i katalogen (`promptbanken.html`) ska kunna delas via en URL som
öppnar rätt paket direkt i detaljvyn. I dag öppnas paket bara via klick i
gridden (`openCatalogPackageDetail(slug)`), utan koppling till URL.

## Scope

Ingår:
- Deep-link via query-param (`?package=<slug>`) som öppnar paketets
  detaljvy vid sidladdning.
- `history.pushState`/`replaceState` så adressfältet speglar öppen/stängd
  vy, och bakåtknappen fungerar.
- "Dela"-knapp i detaljvyn som kopierar länken till urklipp.
- Felhantering för länkar till paket som inte hittas/är opublicerade.
- Usage-tracking av delningsklick, i linje med befintlig
  `trackLibraryUsageEvent`.

Ingår inte (separat framtida feature, avstämt med användaren):
- Statiskt genererade HTML-sidor per paket för sökmotorindexering/social
  preview (kräver build-time-generering från Supabase, egen spec).
- AdSense eller annan annonsering.

## Nuvarande kodläge (referens)

- `promptbanken.html` innehåller katalog-UI:t. `catalog-prompt-detail`
  (script.js:297 i promptbanken.html) är panelen som delas mellan
  prompt- och paketdetaljer.
- `openCatalogPackageDetail(slug)` (script.js:1009) hämtar paketdata via
  `callCatalogRpc('get_published_package', ...)` och
  `list_published_package_prompts`, renderar via `renderCatalogDetailVariant`,
  öppnar panelen med `setCatalogDetailPanelOpen(true)`.
- `setCatalogDetailPanelOpen(open)` (script.js:604) togglar `hidden`/
  `aria-hidden`/`inert` på panelen.
- Stängknapp: `#catalog-detail-close` click-listener (script.js:1053) anropar
  `setCatalogDetailPanelOpen(false)`.
- `loadCatalogPackages()` (script.js:1077) hämtar och renderar
  paketgridden vid sidstart (anropas script.js:215).
- Kopiera-mönster finns redan i `copyCatalogEntityText` (script.js:700):
  `navigator.clipboard.writeText`, byt knapptext till "Kopierat" +
  `.copied`-klass i 2s, `trackLibraryUsageEvent` vid lyckad kopiering.
- `renderCatalogEmptyState(grid, label)` (script.js ~438) finns redan för
  tomma/fel-lägen i gridden — samma mönster återanvänds för fel-notisen.

## Beteende

### 1. Deep-link vid sidladdning

Vid DOMContentLoaded/init, efter att `loadCatalogPackages()` är klar: läs
`new URLSearchParams(location.search).get('package')`. Om satt, kör samma
öppningslogik som klick i gridden (`openCatalogPackageDetail(slug)`), utan
att lägga till en ny history-post (använd `replaceState` inte `pushState`
för detta initiala fall, eftersom URL:en redan har rätt param).

### 2. URL-synk vid interaktion i UI:t

- `openCatalogPackageDetail(slug)`: efter lyckad laddning, om nuvarande
  `location.search` inte redan matchar `?package=<slug>`, gör
  `history.pushState(null, '', '?package=' + encodeURIComponent(slug))`.
- Stängning (`#catalog-detail-close`-klicket samt escape/overlay-klick om
  sådan finns): om `location.search` innehåller `package`-param, gör
  `history.replaceState(null, '', location.pathname)` (ren URL, ingen
  extra history-post — undviker att bakåtknappen studsar mellan öppen/stängd
  för samma användarhandling).
- `popstate`-lyssnare: om ny `location.search` saknar `package`-param och
  panelen är öppen, stäng panelen (`setCatalogDetailPanelOpen(false)`) utan
  att själv skriva historik. Om den innehåller en annan slug än den öppna,
  öppna det paketet.

Detta ger: framåt-navigering (klicka paket A, sen paket B) skapar två
history-poster, bakåt går A→gridden→bort från sidan, vilket är förutsägbart
utan att bygga en fullständig historik-stack för öppna/stäng.

### 3. Dela-knapp

Ny ikonknapp `#catalog-detail-share` i `catalog-detail-panel`, placerad
bredvid `#catalog-detail-close` (samma rad, före stäng-krysset). Ikon: 🔗
eller enkel SVG-länk-ikon, `aria-label="Kopiera länk till paketet"`.

Klick:
1. Bygg `location.origin + location.pathname + '?package=' + encodeURIComponent(slug)`.
2. `navigator.clipboard.writeText(url)`.
3. Vid lyckad kopiering: byt knappens innehåll/text till "Länk kopierad"
   + `.copied`-klass i 2s (samma tajming/mönster som `copyCatalogEntityText`).
4. `trackLibraryUsageEvent({ eventType: 'package_share', packageSlug: slug })`.
5. Vid fel (clipboard nekad): `console.error` + `alert('Kunde inte kopiera länken. Kopiera adressen från adressfältet istället.')`,
   samma felmönster som `copyCatalogEntityText`.

Knappen är bara relevant för paket, inte enskilda prompter (prompter har
egen "Kopiera prompt"-knapp med annat syfte) — döljs/visas villkorat på
`!isPrompt` i `renderCatalogDetailVariant`, likt `packageItemsHtml`.

### 4. Fel: paket hittas inte

Om `get_published_package` för slug från URL:en ger tomt resultat eller
kastar fel:
- Rensa URL:en (`history.replaceState(null, '', location.pathname)`).
- Visa en kort banner ovanför `catalog-package-grid`, samma DOM-mönster som
  `renderCatalogEmptyState` men med egen text: "Paketet kunde inte hittas
  eller är inte längre publicerat." Bannern försvinner vid nästa lyckade
  grid-render eller kan klickas bort (räcker med att den ersätts nästa gång
  `loadCatalogPackages()` kör).
- Katalogen (gridden) visas som vanligt i övrigt — ingen trasig modal.

Detta gäller bara det initiala deep-link-fallet (steg 1), eftersom klick i
UI:t (steg 2) alltid utgår från paket som redan finns i gridden.

## Testning

Ingen automatiserad testsvit för `script.js` idag (vanilla, ej bundlad).
Verifiera manuellt i browser enligt AGENTS.md-konventionen:
- Öppna `promptbanken.html?package=<giltig-slug>` → modal öppen med rätt
  innehåll direkt.
- Öppna `promptbanken.html?package=finns-inte` → felbanner, ren URL, grid
  synlig.
- Klicka paket i gridden → URL uppdateras, bakåtknapp stänger modal och
  återställer URL.
- Klicka Dela → urklipp innehåller korrekt URL, knapp visar
  "Länk kopierad" i 2s.
- Kontrollera att `package_share`-event dyker upp i usage-tracking (samma
  väg som befintliga `package_view`-events).
