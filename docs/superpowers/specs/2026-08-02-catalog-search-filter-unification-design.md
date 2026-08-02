# Enhetlig sök och filtrering över legacy- och katalogrutnätet

**Datum:** 2026-08-02
**Status:** Godkänd, redo för implementationsplan.

## Bakgrund

`index.html`/`script.js` visar prompts från två helt separata källor i samma
vy:

- **Legacy-grid** (`#prompt-grid`): statiska prompts från `prompts.json`,
  renderade som `.prompt-card`. Filtreras av `applyPromptFilters()` mot
  sök, kategori, målgrupp, roll, risk och favoriter — allt via `getPromptMeta()`
  som slår upp fördefinierad metadata per prompt-id.
- **Katalog-grid** (`#catalog-prompt-grid`, `#catalog-package-grid`):
  admin-skapat innehåll från Supabase (`catalog_prompts`/`catalog_packages`),
  renderade som `.catalog-card` via `createCatalogPromptCard()` /
  `createCatalogPackageCard()`. Filtreras idag bara av
  `applyCatalogSearchFilter()` — en enkel substrängsökning mot kortets hela
  synliga text (`card.textContent`). Kategori-, målgrupp-, roll- och
  riskfiltren rör inte katalogkorten alls; de förblir synliga oavsett vilket
  filter som väljs. Katalogens egna kategorier (`area`) finns inte heller som
  alternativ i kategori-dropdownen, som bara byggs från legacy-prompternas
  metadata (`populateFilterOptions(allPrompts)`).

Resultatet: en användare som filtrerar på kategori eller risk missar halva
bibliotekets innehåll utan att veta om det, och resultaträknaren
(`Visar X av Y prompter`) räknar bara legacy-grid.

Detta är ett punktfix-scope, inte en sammanslagning av de två datamodellerna/
rutnäten till en gemensam struktur — det bedöms som ett större, separat
architekturbeslut och är medvetet uteslutet här (se
`docs/module-map-2026-07-31.md`-stil TODO om det blir aktuellt senare).

## Mål

Sök, kategori-, målgrupp- och riskfilter ska ge konsekventa, kompletta
resultat oavsett om en prompt kommer från `prompts.json` eller katalogen.
Rollfilter och paketkorten är medvetet undantagna (se nedan) eftersom
datamodellen saknar de fälten — de ska varken dölja eller felaktigt visa
innehåll de inte har underlag för.

## Design

### 1. Katalogkort får tillgänglig metadata

`createCatalogPromptCard(prompt)` sätter redan `dataset.catalogPromptSlug`.
En modul-lokal `catalogPromptsById`-map (nyckel: `prompt.id`) fylls i
`loadCatalogPrompts()` parallellt med att korten skapas, så att
`prompt.area`, `prompt.risk_level`, `prompt.audience_label` och `prompt.tags`
går att slå upp per DOM-kort utan att gräva i `textContent`. Kortet får också
`dataset.catalogPromptId = prompt.id` för uppslaget.

### 2. Kategori-etiketter för katalogens `area`-slugs

`prompt.area` är en maskinslug (`"forandringsledning"`), inte ett läsbart
namn. `loadCatalogPackages()` körs redan vid sidladdning och känner till
paketens titel per område. En `catalogAreaLabels`-map (`Map<area, title>`)
byggs därifrån — samma mönster som redan används i `promptbanken.html`s
`loadProTemplates()` (`areaLabels.get(prompt.area) || prompt.area`). Om
paketen ännu inte laddats när kategori-dropdownen byggs, faller kortet
tillbaka på råslugen som etikett (bättre än att döljas helt).

`setFilterOptions()` sätter idag `<option value="${value}">${value}</option>`
— värde och synlig text är samma sträng, samma mönster som legacy-kategorierna
redan använder (de svenska kategorinamnen är både lagrings- och visningsvärde).
För att inte bryta det mönstret används katalogens **läsbara etiketter**
(från `catalogAreaLabels`) som dropdown-värde, inte råslugsen. En omvänd map
(`catalogLabelToArea`, etikett → slug) byggs samtidigt, så filtermatchningen
i steg 3 kan slå upp rätt `area`-slug från det valda dropdown-värdet.
`populateFilterOptions()` utökas till att ta emot katalogens etiketter,
unionerat med legacy-kategorierna, för både dropdownen och sidopanelens
kategori-knappar.

### 3. Ny filterfunktion för katalogprompts

`applyCatalogSearchFilter()` tas bort och ersätts av
`applyCatalogPromptFilters()`, som körs över `#catalog-prompt-grid
.catalog-card` och matchar mot samma fyra globala filtervariabler som
legacy-griden redan använder (`activeCategoryFilter`, `activeAudienceFilter`,
`activeRiskFilter`, samt sökfältet via `getSearchQuery()`):

- **Sök:** mot titel + sammanfattning + kategori-etikett + `audience_label`,
  gemener, substräng — samma princip som legacy-grids `haystack`.
- **Kategori:** `activeCategoryFilter` innehåller (precis som idag för
  legacy-kategorier) den läsbara etiketten, inte en slug. Matchning:
  `catalogLabelToArea.get(activeCategoryFilter) === prompt.area`. Om
  `activeCategoryFilter` inte finns i `catalogLabelToArea` (dvs. det är en
  ren legacy-kategori) matchar inget katalogkort, vilket är korrekt — precis
  som att en katalog-kategori inte ska matcha legacy-kort.
- **Målgrupp:** `audience_label` (fri text, en sträng) matchas med
  `includes()` mot `activeAudienceFilter`, till skillnad från legacy-grids
  exakt-matchning mot en array — katalogens fält är inte samma kontrollerade
  vokabulär.
- **Risk:** katalogens `risk_level` lagras som engelska nycklar
  (`low`/`medium`/`high`), men `activeRiskFilter` innehåller svenska
  visningssträngar (`Låg risk`/`Medelrisk`/`Hög risk`) — samma format som
  redan används i `promptbanken.html`s `riskLabels`-map. En likadan
  `catalogRiskLabels`-map (`{low: 'Låg risk', medium: 'Medelrisk', high:
  'Hög risk'}`) läggs till i `script.js`, och matchningen blir
  `catalogRiskLabels[prompt.risk_level] === activeRiskFilter`. En direkt
  strängjämförelse hade tyst aldrig matchat något katalogkort.
- **Roll:** **ignoreras medvetet.** Katalogprompts har inget rollfält.
  Kortet förblir synligt oavsett vilket rollfilter som är valt, istället för
  att gissa utifrån `tags` (fel semantik) eller döljas helt (skulle se ut
  som att innehållet inte finns).

### 4. Paketkort: oförändrad, enklare filtrering

`applyCatalogPackageFilters()` (ny, ersätter dagens del av
`applyCatalogSearchFilter()` som även rörde `#catalog-package-grid`) filtrerar
bara på sökfältet, mot titel + sammanfattning + `audience_label`. Paket
saknar `area`/`risk_level` helt — kategori-, roll- och riskfiltren rör dem
inte, av samma skäl som rollfiltret för prompts.

### 5. Koppla filtren ihop

Idag anropar `categoryFilter`/`audienceFilter`/`roleFilter`/`riskFilter`-
lyssnarna samt sidopanelens kategori-knappar bara `applyPromptFilters()`.
De utökas till att även anropa `applyCatalogPromptFilters()` och
`applyCatalogPackageFilters()`. `initPromptSearch()`s sökfälts-lyssnare byts
från `applyCatalogSearchFilter` till samma två nya funktioner (ersätter,
inte lägger till).

En delad `applyAllFilters()`-wrapper som anropar alla tre
(`applyPromptFilters`, `applyCatalogPromptFilters`,
`applyCatalogPackageFilters`) ersätter de spridda anropen, så framtida
filter bara behöver kopplas på ett ställe.

### 6. Resultaträknare

`Visar X av Y prompter` (`#result-count`) räknas idag bara från
`allPrompts.length` och legacy-grids synliga kort. Räkningen utökas till att
summera synliga `.catalog-card`-element i både `#catalog-prompt-grid` och
`#catalog-package-grid`, och totalen (`Y`) inkluderar katalogens totala
antal laddade kort. Om katalogen inte hunnit laddas än (async) uppdateras
räknaren igen när `loadCatalogPrompts()`/`loadCatalogPackages()` blir klara,
samma sätt som idag triggas om vid `populateFilterOptions(allPrompts)`.

### 7. Feltålighet

Om katalogen inte är konfigurerad (`isCatalogConfigUsable()` false) visas
redan ett felmeddelande i rutnätet istället för kort — de nya
filterfunktionerna itererar bara över faktiska `.catalog-card`-element och
kraschar inte på ett tomt/felmeddelande-rutnät.

## Testplan (manuell, i webbläsare)

1. Sök en term som bara finns i en katalogprompt (inte i `prompts.json`) →
   kortet ska synas, räknas i `Visar X av Y`, och legacy-korten som inte
   matchar ska döljas som vanligt.
2. Välj en kategori som bara finns i katalogen (inte i legacy-listan) →
   matchande katalogkort visas, alla legacy-kort döljs (ingen legacy-kategori
   matchar), icke-matchande katalogkort döljs.
3. Välj en riskniva som finns på både legacy- och katalogprompts → korrekt
   delmängd från båda rutnäten visas samtidigt.
4. Välj ett rollfilter → legacy-grid filtreras som idag, katalogprompts
   förblir alla synliga (oavsett roll), paket förblir alla synliga.
5. Rensa alla filter (`Rensa filter`-knappen) → alla tre rutnät återgår till
   fullt synliga, räknaren stämmer med totalt antal laddade kort.

## Explicit uteslutet ur detta scope

- Sammanslagning av legacy- och katalog-datamodellerna till en gemensam
  struktur/render-funktion.
- Ett riktigt rollfält på katalogprompts (skulle kräva nytt schema-fält och
  adminverktygsstöd — separat beslut).
- Kategori-/risk-/rollfiltrering av paketkort (inga sådana fält finns på
  paket idag).
