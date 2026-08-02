# Enhetlig sök/filter över legacy- och katalogrutnätet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gör så att sökfält, kategori-, målgrupp- och riskfilter på `index.html` ger konsekventa resultat över både det statiska `prompts.json`-rutnätet och det Supabase-drivna katalogrutnätet (prompts + paket), istället för att katalogkorten bara reagerar på fritext-sökning och ignorerar alla andra filter.

**Architecture:** All kod ligger i den enda filen `script.js` (ingen bundling, vanilla JS, inga moduler för denna del). Tre nya modul-lokala lookup-maps byggs när katalogdata laddas (`catalogPromptsById`, `catalogAreaLabels`/`catalogLabelToArea`, `catalogRiskLabels`). `applyCatalogSearchFilter()` ersätts av två nya funktioner (`applyCatalogPromptFilters()`, `applyCatalogPackageFilters()`) som matchar samma globala filtervariabler (`activeCategoryFilter` m.fl.) som redan styr legacy-rutnätet. En ny `applyAllFilters()`-wrapper anropar alla tre filterfunktioner (legacy + katalogprompts + katalogpaket) och ersätter de spridda direktanropen till `applyPromptFilters()`.

**Tech Stack:** Vanilla JavaScript (`script.js`, oprocessad, ingen build för denna fil), Vite dev-server (`npm run web:dev`) för manuell browserverifiering, Playwright MCP-verktyg för att köra och inspektera sidan under utveckling.

## Global Constraints

- Rollfilter ska INTE påverka katalogprompts eller paket — katalogdata saknar rollfält, och att gissa (t.ex. via `tags`) vore fel semantik. Katalogkort/paket förblir synliga oavsett valt rollfilter.
- Kategori-, risk- och rollfilter ska INTE påverka paketkort — paket saknar `area`/`risk_level` helt i databasen. Bara sökfältet (mot titel + sammanfattning + `audience_label`) filtrerar paket.
- Katalogens `risk_level` lagras som engelska nycklar (`low`/`medium`/`high`); legacy-filtrets värden är svenska strängar (`Låg risk`/`Medelrisk`/`Hög risk`). All matchning måste gå via en nyckel↔etikett-map, aldrig direkt strängjämförelse.
- Katalogens `area` är en maskinslug (t.ex. `"forandringsledning"`); den läsbara etiketten kommer från `catalog_packages.slug`→`catalog_packages.title` (samma `area`-slug återanvänds som paketets `slug`). All matchning måste gå via samma slug↔etikett-map som används för visning, aldrig gissad strängjämförelse.
- Ingen sammanslagning av datamodeller/rutnät — legacy `.prompt-card` och katalogens `.catalog-card` förblir separata DOM-strukturer och renderfunktioner. Detta scope rör bara filtrering.
- `script.js` bundlas inte av Vite och får inga `import`-satser.
- Ingen automatiserad JS-testsvit finns i detta repo — verifiering sker manuellt i webbläsare (`npm run web:dev`), inte via `pytest`/`jest`-stil TDD. Playwright MCP-verktyget används för att navigera och inspektera under utveckling.

---

### Task 1: Lookup-maps för katalogmetadata (prompt-id, kategori-etiketter, risk-etiketter)

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js:694-757` (`createCatalogPromptCard`, `loadCatalogPrompts`)
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js:1016-1066` (`createCatalogPackageCard`, `loadCatalogPackages`)

**Interfaces:**
- Produces: modul-scope `catalogPromptsById` (`Map<string, object>`, nyckel = `prompt.id`), `catalogAreaLabels` (`Map<string, string>`, nyckel = `area`-slug, värde = läsbar etikett), `catalogLabelToArea` (`Map<string, string>`, omvänd av `catalogAreaLabels`), `catalogRiskLabels` (plain object `{low: 'Låg risk', medium: 'Medelrisk', high: 'Hög risk'}`). Dessa konsumeras av Task 2 och Task 3.

- [ ] **Step 1: Lägg till modul-scope-variablerna**

I `script.js`, direkt före `function createCatalogPromptCard(prompt) {` (rad 694), lägg till:

```javascript
const catalogPromptsById = new Map();
const catalogAreaLabels = new Map();
const catalogLabelToArea = new Map();
const catalogRiskLabels = { low: 'Låg risk', medium: 'Medelrisk', high: 'Hög risk' };
```

- [ ] **Step 2: Fyll `catalogPromptsById` när katalogprompts laddas**

I `loadCatalogPrompts()` (rad 724-757), ersätt raden `grid.innerHTML = '';` (rad 738) och forEach-blocket (rad 746-752) med:

```javascript
        grid.innerHTML = '';
        catalogPromptsById.clear();
        if (!prompts.length) {
            renderCatalogEmptyState(grid, 'prompter');
            return;
        }
        // List-RPC:n returnerar inte context_key i den komprimerade listvyn ännu,
        // så icke-generella lägen markeras heuristiskt tills read-RPC:n kan
        // skilja exakt mellan matchad och generell variant.
        prompts
            .map((prompt) => ({
                ...prompt,
                isFallback: activeContextKey !== DEFAULT_CONTEXT_KEY && (!prompt.context_key || prompt.context_key === DEFAULT_CONTEXT_KEY),
                fallbackLabel: prompt.context_key ? 'Generell version' : 'Kan vara generell version'
            }))
            .forEach((prompt) => {
                catalogPromptsById.set(prompt.id, prompt);
                grid.appendChild(createCatalogPromptCard(prompt));
            });
```

(Endast `catalogPromptsById.clear()` tillagt före tom-kontrollen, och forEach-kroppen utökad med `catalogPromptsById.set(...)` — resten oförändrat.)

- [ ] **Step 3: Sätt `dataset.catalogPromptId` på kortet**

I `createCatalogPromptCard(prompt)` (rad 694-722), lägg till en rad direkt efter `card.dataset.catalogPromptSlug = prompt.slug;` (rad 697):

```javascript
    card.dataset.catalogPromptSlug = prompt.slug;
    card.dataset.catalogPromptId = prompt.id;
```

- [ ] **Step 4: Fyll `catalogAreaLabels`/`catalogLabelToArea` när paket laddas**

I `loadCatalogPackages()` (rad 1036-1066), ersätt raden `grid.innerHTML = '';` (rad 1051) och forEach-blocket (rad 1056-1062) med:

```javascript
        grid.innerHTML = '';
        catalogAreaLabels.clear();
        catalogLabelToArea.clear();
        if (!packages.length) {
            renderCatalogEmptyState(grid, 'paket eller arbetssätt');
            return;
        }
        packages
            .map((pkg) => ({
                ...pkg,
                isFallback: activeContextKey !== DEFAULT_CONTEXT_KEY && (!pkg.context_key || pkg.context_key === DEFAULT_CONTEXT_KEY),
                fallbackLabel: pkg.context_key ? 'Generell version' : 'Kan vara generell version'
            }))
            .forEach((pkg) => {
                if (pkg.slug && pkg.title) {
                    catalogAreaLabels.set(pkg.slug, pkg.title);
                    catalogLabelToArea.set(pkg.title, pkg.slug);
                }
                grid.appendChild(createCatalogPackageCard(pkg));
            });
```

- [ ] **Step 5: Verifiera i webbläsaren**

Kör:

```powershell
npm run web:dev
```

Öppna `index.html`, öppna dev-konsolen, kör i konsolen:

```javascript
console.log(catalogPromptsById.size, catalogAreaLabels.size, catalogLabelToArea.size)
```

Förväntat: alla tre > 0 (matchar antalet laddade katalogprompts respektive paket). Om `catalogAreaLabels.size` är 0, kontrollera att `loadCatalogPackages()` hann köra (asynkront) innan konsolkommandot körs.

- [ ] **Step 6: Commit**

```powershell
git add script.js
git commit -m "feat(web): build catalog metadata lookup maps for prompt id, area labels, risk labels"
```

---

### Task 2: Katalogens kategorier syns i kategori-filtret

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js:1404-1410` (`populateFilterOptions`)
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js:1036-1066` (`loadCatalogPackages`, lägg till omanrop)

**Interfaces:**
- Consumes: `catalogAreaLabels` (Task 1).
- Produces: `populateFilterOptions(prompts)` tar nu även med katalogens kategori-etiketter i `#category-filter`-dropdownen och sidopanelens kategori-knappar (om sådana finns via `data-category-filter`). Signaturen är oförändrad — funktionen läser `catalogAreaLabels` direkt (modul-scope), ingen ny parameter.

- [ ] **Step 1: Utöka `populateFilterOptions` med katalogkategorier**

I `script.js`, ersätt `populateFilterOptions` (rad 1404-1410):

```javascript
        function populateFilterOptions(prompts) {
            const metadata = prompts.map(getPromptMeta);
            const legacyCategories = metadata.map((meta) => meta.category);
            const catalogCategories = Array.from(catalogAreaLabels.values());
            setFilterOptions('category-filter', [...legacyCategories, ...catalogCategories], 'Alla kategorier');
            setFilterOptions('audience-filter', metadata.flatMap((meta) => meta.audiences), 'Alla målgrupper');
            setFilterOptions('role-filter', metadata.flatMap((meta) => meta.roles), 'Alla roller');
            setFilterOptions('risk-filter', metadata.map((meta) => meta.risk), 'Alla risknivåer');
        }
```

- [ ] **Step 2: Kör om `populateFilterOptions` när katalogpaket blivit klara**

I `loadCatalogPackages()` (efter ändringen i Task 1 Step 4), lägg till en rad direkt efter forEach-blockets stängande `);` (dvs. efter `catalogLabelToArea`-fyllningen, innan `catch`-blocket):

```javascript
                grid.appendChild(createCatalogPackageCard(pkg));
            });
        populateFilterOptions(allPrompts);
    } catch (error) {
```

(`populateFilterOptions(allPrompts)` läggs till som en ny rad mellan forEach-anropet och `} catch`. `allPrompts` är den redan existerande modul-variabeln för legacy-prompts, oförändrad av detta steg — om `loadCatalogPackages()` körs innan `loadPrompts()` hunnit fylla `allPrompts` är den bara en tom array här, vilket är ofarligt: `populateFilterOptions` körs igen naturligt varje gång `loadPrompts()` själv anropar den, se rad 1896/1937/1941.)

- [ ] **Step 3: Verifiera i webbläsaren**

Med dev-servern igång, öppna kategori-dropdownen (`#category-filter`) i webbläsaren. Förväntat: innehåller nu både legacy-kategorier (t.ex. "Beslut och rutiner") och katalog-kategorier (paketens titlar, t.ex. "Förändringsledning och införande").

- [ ] **Step 4: Commit**

```powershell
git add script.js
git commit -m "feat(web): include catalog categories in the category filter dropdown"
```

---

### Task 3: Nya filterfunktioner för katalogprompts och katalogpaket

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js:543-562` (tar bort `applyCatalogSearchFilter`, lägger till kommentar-referens till spec)

**Interfaces:**
- Consumes: `catalogPromptsById`, `catalogLabelToArea`, `catalogRiskLabels` (Task 1); globala filtervariabler `activeCategoryFilter`, `activeAudienceFilter`, `activeRiskFilter` (redan existerande, definierade rad 1123-1127); `getSearchQuery()` (redan existerande, rad 1412-1414).
- Produces: `applyCatalogPromptFilters()` och `applyCatalogPackageFilters()` — inga parametrar, inga returvärden, itererar DOM direkt (samma mönster som `applyPromptFilters()`). Konsumeras av Task 4.

- [ ] **Step 1: Ta bort `applyCatalogSearchFilter` och skriv de två nya funktionerna**

I `script.js`, ersätt hela blocket rad 543-562 (kommentaren + `applyCatalogSearchFilter`):

```javascript
// Enhetlig katalogfiltrering: se docs/superpowers/specs/
// 2026-08-02-catalog-search-filter-unification-design.md. Katalogprompts
// matchas mot samma globala filtervariabler som legacy-griden
// (activeCategoryFilter/activeAudienceFilter/activeRiskFilter), men rollfilter
// ignoreras medvetet (katalogdata saknar rollfält) och kategori/risk matchas
// via lookup-maps eftersom katalogens lagringsformat (slugs, engelska
// risknycklar) skiljer sig från legacy-griden (svenska etiketter).
document.querySelectorAll('[data-catalog-package-shortcut]').forEach((button) => {
    button.addEventListener('click', () => {
        const slug = button.getAttribute('data-catalog-package-shortcut');
        openCatalogPackageDetail(slug);
        document.getElementById('catalog-package-grid')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
});

function applyCatalogPromptFilters() {
    const query = getSearchQuery();
    document.querySelectorAll('#catalog-prompt-grid .catalog-card').forEach((card) => {
        const prompt = catalogPromptsById.get(card.dataset.catalogPromptId);
        if (!prompt) {
            card.hidden = true;
            return;
        }

        const areaLabel = catalogAreaLabels.get(prompt.area) || '';
        const haystack = `${prompt.title || ''} ${prompt.summary || ''} ${areaLabel} ${prompt.audience_label || ''}`.toLowerCase();
        const matchesSearch = !query || haystack.includes(query);
        const matchesCategory = activeCategoryFilter === 'all'
            || catalogLabelToArea.get(activeCategoryFilter) === prompt.area;
        const matchesAudience = activeAudienceFilter === 'all'
            || (prompt.audience_label || '').toLowerCase().includes(activeAudienceFilter.toLowerCase());
        const matchesRisk = activeRiskFilter === 'all'
            || catalogRiskLabels[prompt.risk_level] === activeRiskFilter;
        // Rollfilter medvetet ignorerat: katalogprompts har inget rollfält.

        card.hidden = !(matchesSearch && matchesCategory && matchesAudience && matchesRisk);
    });
}

function applyCatalogPackageFilters() {
    const query = getSearchQuery();
    document.querySelectorAll('#catalog-package-grid .catalog-card').forEach((card) => {
        const haystack = card.textContent.toLowerCase();
        card.hidden = Boolean(query) && !haystack.includes(query);
    });
}
```

- [ ] **Step 2: Verifiera att `applyCatalogSearchFilter` inte längre refereras någonstans**

Kör:

```powershell
rg -n "applyCatalogSearchFilter" script.js
```

Förväntat: inga träffar (referenser till den tas bort i Task 4).

Obs: det här steget kommer visa kvarvarande träffar tills Task 4 är klar (som byter ut anropen i `initPromptSearch`). Om körd innan Task 4, notera bara att den gamla funktionsdefinitionen är borta men anropet ännu inte uppdaterat — inte en bugg i det här steget.

- [ ] **Step 3: Commit**

```powershell
git add script.js
git commit -m "feat(web): add category/audience/risk-aware filtering for catalog prompt cards"
```

---

### Task 4: Koppla alla filter till katalogfunktionerna via en delad wrapper

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js:1465-1513` (`applyPromptFilters`, lägg till `applyAllFilters` efter)
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js:1515-1610` (`initCategoryFilters`, byt `applyPromptFilters()`-anrop mot `applyAllFilters()`)
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js:2089-2097` (`initPromptSearch`)
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js:1282,1461,1900,1941,2033,2116,3387` (övriga direktanrop av `applyPromptFilters()`)

**Interfaces:**
- Consumes: `applyPromptFilters()` (redan existerande), `applyCatalogPromptFilters()`, `applyCatalogPackageFilters()` (Task 3).
- Produces: `applyAllFilters()` — inga parametrar, inget returvärde. Detta är den nya standardfunktionen alla filter-UI-lyssnare anropar; `applyPromptFilters()` behåller sitt eget namn och sin egen logik oförändrad (bara anropen till den byts, inte funktionen själv).

- [ ] **Step 1: Lägg till `applyAllFilters()` direkt efter `applyPromptFilters()`**

I `script.js`, direkt efter `applyPromptFilters()`s stängande `}` (efter rad 1513, före `function initCategoryFilters() {` på rad 1515), lägg till:

```javascript
        function applyAllFilters() {
            applyPromptFilters();
            applyCatalogPromptFilters();
            applyCatalogPackageFilters();
        }

```

- [ ] **Step 2: Byt ut samtliga direktanrop av `applyPromptFilters()` till `applyAllFilters()`**

Kör (PowerShell, i repo-roten):

```powershell
(Get-Content script.js -Raw) -replace 'applyPromptFilters\(\);', 'applyAllFilters();' | Set-Content script.js -NoNewline
```

Detta byter ut varje `applyPromptFilters();`-anrop (rad 1282, 1461, 1539, 1556, 1564, 1571, 1578, 1599, 1900, 1941, 2033, 2116, 3387 vid tidpunkten planen skrevs — exakta radnummer skiftar av tidigare tasks, därför global replace) mot `applyAllFilters();`. Själva `function applyPromptFilters() {`-definitionen och `function applyAllFilters() {`s egna interna anrop (`applyPromptFilters();` utan efterföljande `;` från en annan sats — de har redan `;`) påverkas INTE av denna replace eftersom de matchar exakt samma mönster och SKA bytas ut förutom just insidan av `applyAllFilters()` själv, som anropar den namngivna funktionen direkt och inte ska bytas rekursivt.

**Viktigt:** kör steg 3 (verifiering) direkt efteråt och inspektera `applyAllFilters()`s egen kropp — om den globala ersättningen råkat träffa raden `applyPromptFilters();` inuti `applyAllFilters()` själv (vilket den kommer göra, eftersom mönstret är identiskt), rätta manuellt tillbaka just den raden till `applyPromptFilters();` (annars blir det oändlig rekursion).

- [ ] **Step 3: Rätta den självrefererande raden manuellt om den bytts**

Öppna `script.js`, sök upp `function applyAllFilters() {` och kontrollera att kroppen är exakt:

```javascript
        function applyAllFilters() {
            applyPromptFilters();
            applyCatalogPromptFilters();
            applyCatalogPackageFilters();
        }
```

Om den första raden i kroppen råkat bli `applyAllFilters();` (rekursion) istället för `applyPromptFilters();`, rätta den manuellt till `applyPromptFilters();`.

- [ ] **Step 4: Byt sökfältets katalogfunktion i `initPromptSearch`**

I `script.js`, i `initPromptSearch()` (runt rad 2089-2097 innan tidigare tasks flyttat rader), ersätt:

```javascript
            ['input', 'keyup', 'search', 'change'].forEach((eventName) => {
                searchInput.addEventListener(eventName, applyPromptFilters);
                searchInput.addEventListener(eventName, applyCatalogSearchFilter);
            });
```

med:

```javascript
            ['input', 'keyup', 'search', 'change'].forEach((eventName) => {
                searchInput.addEventListener(eventName, applyAllFilters);
            });
```

(Ett enda `applyAllFilters`-anrop ersätter de två separata lyssnarna, eftersom `applyAllFilters` redan täcker alla tre rutnät.)

- [ ] **Step 5: Verifiera att inga döda referenser finns kvar**

Kör:

```powershell
rg -n "applyCatalogSearchFilter" script.js
```

Förväntat: inga träffar.

```powershell
rg -n "applyPromptFilters\(\);" script.js
```

Förväntat: exakt en träff kvar (inuti `applyAllFilters()`s egen kropp).

```powershell
node --check script.js
```

Förväntat: ingen output (giltig JS-syntax).

- [ ] **Step 6: Manuell verifiering i webbläsaren**

Med `npm run web:dev` igång, öppna `index.html`:
- Skriv en sökterm i sökfältet som bara matchar en katalogprompt → katalogkortet ska synas, andra katalogkort döljas.
- Välj en kategori som bara finns i katalogen (från Task 2:s utökade dropdown) → matchande katalogprompt-kort visas, icke-matchande legacy- och katalogkort döljs.
- Välj ett rollfilter → legacy-kort filtreras, katalogprompt-kort förblir alla synliga.
- Klicka "Rensa filter" → alla rutnät återgår till fullt synliga.

- [ ] **Step 7: Commit**

```powershell
git add script.js
git commit -m "feat(web): route all filter UI through a shared applyAllFilters that covers both grids"
```

---

### Task 5: Resultaträknaren räknar alla tre rutnät

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js:1465-1513` (`applyPromptFilters`, flytta räkning till `applyAllFilters`)

**Interfaces:**
- Consumes: DOM-state efter `applyPromptFilters()`, `applyCatalogPromptFilters()`, `applyCatalogPackageFilters()` (Task 3/4) har körts.
- Produces: `#result-count`-texten uppdateras nu i `applyAllFilters()` istället för inuti `applyPromptFilters()`, och räknar synliga kort över alla tre grids.

- [ ] **Step 1: Flytta `resultCount`-uppdateringen från `applyPromptFilters` till `applyAllFilters`**

I `script.js`, i `applyPromptFilters()`, ta bort raderna som sätter `#result-count` (den befintliga `const resultCount = document.getElementById('result-count');` + `if (resultCount) { resultCount.textContent = ...; }`-blocket, ca rad 1493-1497) och behåll bara `visibleCount`-räkningen och `emptyState`-hanteringen (som bara rör legacy-griden och ska vara kvar där).

`applyPromptFilters()` behöver nu returnera sitt `visibleCount` så `applyAllFilters()` kan summera. Ändra funktionssignaturen minimalt: lägg till `return visibleCount;` som sista rad i `applyPromptFilters()`, direkt före dess stängande `}`.

- [ ] **Step 2: Räkna synliga katalogkort och uppdatera `applyAllFilters`**

Ersätt `applyAllFilters()` (skriven i Task 4 Step 1) med:

```javascript
        function applyAllFilters() {
            const legacyVisible = applyPromptFilters();
            applyCatalogPromptFilters();
            applyCatalogPackageFilters();

            const catalogPromptVisible = document.querySelectorAll('#catalog-prompt-grid .catalog-card:not([hidden])').length;
            const catalogPackageVisible = document.querySelectorAll('#catalog-package-grid .catalog-card:not([hidden])').length;
            const totalVisible = legacyVisible + catalogPromptVisible + catalogPackageVisible;

            const totalAll = allPrompts.length + catalogPromptsById.size + catalogLabelToArea.size;

            const resultCount = document.getElementById('result-count');
            if (resultCount) {
                resultCount.textContent = `Visar ${totalVisible} av ${totalAll} prompter`;
            }
        }
```

Obs: `catalogLabelToArea.size` används som antal paket eftersom det är en 1:1-map byggd från paketlistan i Task 1 Step 4 (ett `set`-anrop per paket med giltig `slug`+`title`) — om ett paket saknar `slug` eller `title` räknas det inte med i mappen och därmed inte i totalen; det är samma edge case som redan hanteras tyst av `if (pkg.slug && pkg.title)`-villkoret i Task 1.

- [ ] **Step 3: Verifiera i webbläsaren**

Med dev-servern igång, öppna `index.html`, kontrollera att `#result-count`-texten direkt vid sidladdning (efter att katalogen hunnit ladda) visar en högre total än bara legacy-prompternas antal. Rensa alla filter och bekräfta att `Visar X av Y` har `X === Y`.

- [ ] **Step 4: Commit**

```powershell
git add script.js
git commit -m "fix(web): count catalog prompt and package cards in the result counter"
```

---

### Task 6: Fullständig manuell regressionskörning och avslut

**Files:** Inga kodändringar — verifieringssteg.

- [ ] **Step 1: Kör hela testplanen från specen**

Med `npm run web:dev` igång, gå igenom testplanen i
`docs/superpowers/specs/2026-08-02-catalog-search-filter-unification-design.md`
punkt för punkt:

1. Sök en term som bara finns i en katalogprompt → kortet syns, räknas, legacy-kort som inte matchar döljs.
2. Välj en kategori som bara finns i katalogen → matchande katalogkort visas, alla legacy-kort döljs.
3. Välj en riskniva som finns på både legacy- och katalogprompts → korrekt delmängd från båda rutnäten visas samtidigt.
4. Välj ett rollfilter → legacy-grid filtreras, katalogprompts och paket förblir alla synliga.
5. Klicka "Rensa filter" → alla tre rutnät återgår till fullt synliga, räknaren stämmer.

- [ ] **Step 2: Kontrollera att inget annat i sidan gått sönder**

Öppna dev-konsolen, ladda om sidan, kontrollera att inga nya JS-fel loggas (jämför mot ett känt referensläge — ett `favicon.ico 404` är förväntat och ofarligt, inget annat ska synas).

- [ ] **Step 3: Uppdatera octopus-statusen**

Logga i `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/octopus/STATUS.md` under `promptbanken` att sök/kategori-enhetligheten mellan legacy- och katalogrutnätet är klar, med commit-hashar från Task 1-5.

## Self-Review

- **Spec coverage:** Alla sju designpunkter i specen har en task: (1) katalogkort får metadata → Task 1; (2) kategori-etiketter → Task 2; (3) ny filterfunktion för katalogprompts inkl. risk/kategori-nyckelmappning → Task 3; (4) paketkort oförändrad enklare filtrering → Task 3 (`applyCatalogPackageFilters`); (5) koppla filtren ihop → Task 4; (6) resultaträknare → Task 5; (7) feltålighet → redan uppfylld av att filterfunktionerna bara itererar faktiska `.catalog-card`-element (ingen extra kod behövs, verifierat i Task 3 Step 1:s implementation som inte antar att grids är icke-tomma).
- **Placeholder scan:** Inga TBD/TODO. Task 4 Step 2 (global sed-replace) har en ovanligt lång förklaring eftersom det är den enda platsen i planen med en risk för självintroducerad bugg (rekursion) — flaggat explicit med ett eget rättningssteg (Step 3) istället för att gömmas som en outtalad risk.
- **Type consistency:** `applyPromptFilters()` byter från att inte returnera nåt (`undefined`) till att returnera `visibleCount` (Task 5 Step 1) — verifierat att den enda anroparen som bryr sig om returvärdet är den nya `applyAllFilters()` (Task 5 Step 2); alla andra befintliga anropsplatser (bytta till `applyAllFilters()` i Task 4) ignorerar redan returvärden från funktionsanrop i den stilen, så ingen annan kod är beroende av att `applyPromptFilters()` returnerar `undefined`.
