# Globalt Kontextfilter Implementation Plan

**Status 2026-07-27:** Implementerad på `main`. Planen sparas som
genomförandehistorik; aktuell verifiering och kvarvarande arbete följs i
`TODO.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gör kontextvalet till ett globalt enkelval för hela `promptbanken.html`, så att prompts, öppna katalogprompts och paket följer samma UX och fallback blir synlig.

**Architecture:** Första versionen hålls i samma vanliga statiska frontendlager som idag: `promptbanken.html` för struktur, `style.css` för layout/states och `script.js` för filterstate, render och Supabase-anrop. Den befintliga Supabase-fallbacken i read-RPC:erna behålls, men frontend byter från fler-vals-checkboxar till ett aktivt profilval i taget och märker upp poster som visas via generell fallback. Statiska prompts får en lättviktig kontextklassning i klientkoden så hela sidan kan styras av samma val utan ny backend.

**Tech Stack:** vanilla JS i `script.js`, statisk HTML i `promptbanken.html`, CSS i `style.css`, befintliga Supabase REST-RPC:er (`list_published_prompts`, `get_published_prompt`, `list_published_packages`, `get_published_package`).

## Global Constraints

- Hela sidan ska använda exakt en aktiv kontext åt gången: `Alla` eller `Generell`, `Kommun`, `Skola`, `Företag`, `Förening`, `Privat`.
- Kontextvalet ska påverka promptlistor på sidan, öppna katalogprompts från Supabase, och paket och arbetssätt från Supabase.
- Kontextfiltret ska flyttas från den nedre katalogsektionen till en tydlig plats högre upp i sidan, nära den huvudsakliga katalogintroduktionen och innan större resultatlistor.
- Sidan ska upplevas som en enda katalog med sektioner, inte två separata system.
- Datamodellen ska fortsatt få falla tillbaka till `generell` när vald kontext saknar egen variant, men fallback ska märkas diskret för användaren.
- De befintliga statiska promptarna i `prompts.json` behöver en enkel kontextklassning så att även de kan filtreras av det globala profilvalet.
- Det aktiva profilvalet ska fortsatt persisteras lokalt, men modellen blir ett enskilt värde i stället för en lista.
- Standardläget ska aldrig kännas tomt.
- Profilväxling ska ge synlig effekt i listan.
- Om en sektion saknar innehåll helt ska den visa en begriplig tomstatus, inte en blank yta.
- `script.js` får inga `import`-satser (repo-regel).
- Vid frontendändringar: kör minst `npm run build`.

---

### Task 1: Flytta filtret till global placering och byt till enkelval

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/promptbanken.html`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/style.css`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`

**Interfaces:**
- Consumes: befintlig `CATALOG_CONTEXT_PROFILES`, `renderCatalogProfileFilters()`, `getCatalogProfileSelection()`, `saveCatalogProfileSelection()`.
- Produces:
  - `getActiveContextKey(): string`
  - `loadGlobalContextSelection(): string`
  - `saveGlobalContextSelection(key: string): void`
  - global UI-container för kontextval och aktiv statusrad

- [ ] **Step 1: Lägg till den nya globala filtercontainern i HTML**

Flytta bort kontextfiltren från att vara semantiskt bundna till bara `#catalog-section` och lägg i stället in en ny global container högre upp i `promptbanken.html`, nära katalogintroduktionen.

Markup att lägga in:

```html
<section class="context-filter-bar" aria-labelledby="context-filter-heading">
  <div class="context-filter-copy">
    <h2 id="context-filter-heading">Anpassa innehåll efter din kontext</h2>
    <p>Välj vilken kontext du vill att hela katalogen ska utgå från.</p>
  </div>
  <div class="context-filter-options" id="catalog-profile-filters" role="radiogroup" aria-label="Kontextval"></div>
  <p class="context-filter-status" id="catalog-profile-status">Visar innehåll för: Alla</p>
</section>
```

- [ ] **Step 2: Gör enkelvalet tydligt i CSS**

Ersätt checkbox-känslan med pill-knappar som visuellt beter sig som ett exklusivt val.

Lägg till/justera regler enligt mönstret:

```css
.context-filter-bar {
    margin: 1.5rem 0 2rem;
    padding: 1rem 1.1rem;
    border: 1px solid var(--border-color, #d8dee7);
    border-radius: 14px;
    background: #f8fbff;
}

.context-filter-options {
    display: flex;
    flex-wrap: wrap;
    gap: 0.6rem;
    margin-top: 0.85rem;
}

.context-filter-option[aria-checked="true"] {
    border-color: #0052a3;
    background: #e8f1ff;
    color: #003b75;
}

.context-filter-status {
    margin-top: 0.8rem;
    color: #475467;
    font-size: 0.95rem;
}
```

- [ ] **Step 3: Byt storage-modellen från lista till en aktiv profil**

I `script.js`, ersätt dagens listmodell:

```js
function getCatalogProfileSelection() { ... }
function saveCatalogProfileSelection(keys) { ... }
function getActiveContextKeys() { ... }
```

med enkelvalsmodellen:

```js
const DEFAULT_CONTEXT_KEY = 'generell';

function loadGlobalContextSelection() {
    const stored = localStorage.getItem(CATALOG_PROFILE_STORAGE_KEY);
    return stored || DEFAULT_CONTEXT_KEY;
}

function saveGlobalContextSelection(key) {
    localStorage.setItem(CATALOG_PROFILE_STORAGE_KEY, key || DEFAULT_CONTEXT_KEY);
}

function getActiveContextKey() {
    return loadGlobalContextSelection();
}
```

- [ ] **Step 4: Rendera filtervalen som ett radiogroup-liknande enkelval**

Byt `renderCatalogProfileFilters()` till att skriva en exklusiv lista med `Alla` först och sedan profilerna.

Målstruktur:

```js
const GLOBAL_CONTEXT_OPTIONS = [
    { key: 'generell', label: 'Alla' },
    { key: 'kommun', label: 'Kommun' },
    { key: 'skola', label: 'Skola' },
    { key: 'företag', label: 'Företag' },
    { key: 'förening', label: 'Förening' },
    { key: 'privat', label: 'Privat' }
];
```

Varje knapp ska:
- ha `type="button"`
- ha klass `context-filter-option`
- ha `role="radio"`
- sätta `aria-checked="true"` bara på aktivt val
- vid klick spara valet och trigga omrendering av hela sidan

- [ ] **Step 5: Uppdatera statusraden**

Lägg till en helper som visar aktivt val:

```js
function renderGlobalContextStatus() {
    const status = document.getElementById('catalog-profile-status');
    if (!status) return;
    const active = GLOBAL_CONTEXT_OPTIONS.find((item) => item.key === getActiveContextKey());
    status.textContent = `Visar innehåll för: ${active ? active.label : 'Alla'}`;
}
```

Anropa den från samma init- och clickflöde som `renderCatalogProfileFilters()`.

- [ ] **Step 6: Verifiera UI-flytten lokalt**

Run:

```powershell
npm run build
```

Expected:
- bygget går grönt
- `promptbanken.html` innehåller den nya globala filterbaren
- inga JS-fel om saknade gamla checkbox-element

- [ ] **Step 7: Commit**

```bash
git add promptbanken.html style.css script.js
git commit -m "feat(web): move context filter to a global single-select bar"
```

### Task 2: Låt statiska prompts på sidan följa samma kontextval

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/prompts.json` (endast om kontext måste lagras där; annars håll klassningen i JS)

**Interfaces:**
- Consumes: befintliga `loadPrompts()`, `createPromptCard()`, `allPrompts`, prompt-id:n i `prompts.json`.
- Produces:
  - `STATIC_PROMPT_CONTEXTS: Record<string, string[]>`
  - `matchesGlobalContext(promptId: string, activeContextKey: string): boolean`

- [ ] **Step 1: Skriv en lättviktig kontextklassning för statiska prompts**

Lägg i `script.js` nära övrig promptmetadata:

```js
const STATIC_PROMPT_CONTEXTS = {
    tydlighetskoll: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    klarsprak: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    mejl: ['generell', 'kommun', 'företag', 'förening', 'privat'],
    faq: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    checklista: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    kallelse: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    beslutsunderlag: ['generell', 'kommun', 'skola', 'förening'],
    rutin: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    tvaversioner: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    reflektion: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    samtalskompas: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    sammanfattning: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    anteckningar: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    diskussionsfragor: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    nyckelord: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    informationsutskick: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    enkel_infografik: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    illustration_informationsutskick: ['generell', 'kommun', 'skola', 'företag', 'förening'],
    ikon_symbolbild: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    presentationstitelbild: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat'],
    alt_text_bild: ['generell', 'kommun', 'skola', 'företag', 'förening', 'privat']
};
```

- [ ] **Step 2: Lägg till en enkel matchningsfunktion**

```js
function matchesGlobalContext(promptId, activeContextKey) {
    const contexts = STATIC_PROMPT_CONTEXTS[promptId] || ['generell'];
    return activeContextKey === 'generell' || contexts.includes(activeContextKey);
}
```

- [ ] **Step 3: Filtrera statiska prompts innan rendering**

I den kodväg som renderar de vanliga promptkorten från `prompts.json`, filtrera datan före `createPromptCard(...)`.

Målmönster:

```js
const activeContextKey = getActiveContextKey();
const visiblePrompts = prompts.filter((prompt) => matchesGlobalContext(prompt.id, activeContextKey));
```

Sedan renderas `visiblePrompts` i stället för hela listan.

- [ ] **Step 4: Lägg till tomstatus om en statisk sektion blir tom**

Om det statiska promptgridden blir tom efter filtrering, visa en begriplig tomrad i samma stil som katalogens tomstatus, till exempel:

```js
grid.innerHTML = '<div class="catalog-empty-state">Inga prompts matchar vald kontext just nu.</div>';
```

- [ ] **Step 5: Verifiera att profilbyte påverkar den vanliga promptlistan**

Run:

```powershell
npm run build
```

Manual check i browser:
- välj `Privat` och bekräfta att minst någon del av den vanliga promptlistan ändras
- växla tillbaka till `Alla` och bekräfta att fler prompts syns igen

- [ ] **Step 6: Commit**

```bash
git add script.js prompts.json
git commit -m "feat(web): apply global context filter to static prompts"
```

### Task 3: Anpassa Supabase-katalogen till enkelval och gör fallback synlig

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`

**Interfaces:**
- Consumes: `list_published_prompts`, `get_published_prompt`, `list_published_packages`, `get_published_package`.
- Produces:
  - `getActiveContextKeys(): string[]` som wrapper över ett enda aktivt val
  - `createCatalogPromptCard(prompt, activeContextKey)`
  - `createCatalogPackageCard(pkg, activeContextKey)`
  - fallback-badge i korten när listsvaret använder generell variant

- [ ] **Step 1: Behåll RPC-signaturen som array, men generera bara ett värde**

Eftersom databasen redan förväntar sig `p_context_keys text[]`, använd en tunn adapter i frontend:

```js
function getActiveContextKeys() {
    return [getActiveContextKey()];
}
```

Detta låter resten av RPC-koden fortsätta fungera utan databasmigrering.

- [ ] **Step 2: Lägg till fallback-detektion i listkorten**

Använd listsvaret och aktivt kontextval för att märka upp fallback.

Regel:
- om `activeContextKey === 'generell'` visas ingen fallbackbadge
- om aktivt val är något annat, och listkortet kommer från generell variant, visa badge

Första versionen får använda enkel frontendmarkering via ett extra fält i JS-objektet när listor byggs, till exempel:

```js
const normalizedPrompt = {
    ...prompt,
    isFallback: activeContextKey !== 'generell' && !prompt.context_key
};
```

och i kortet:

```js
${prompt.isFallback ? '<span class="catalog-context-badge">Generell version</span>' : ''}
```

Om list-RPC:n ännu inte returnerar `context_key`, lägg som första implementation en generell fallbackbadge på icke-generell vyer och markera i koden med en kommentar att en senare DB-utökning kan göra märkningen exakt.

- [ ] **Step 3: Uppdatera `createCatalogPromptCard()` och `createCatalogPackageCard()`**

Byt signaturerna så de kan rendera kontextbadge:

```js
function createCatalogPromptCard(prompt) { ... }
function createCatalogPackageCard(pkg) { ... }
```

ska få markup i stil med:

```js
card.innerHTML = `
    <h4>${title}</h4>
    <p>${summary}</p>
    ${prompt.isFallback ? '<span class="catalog-context-badge">Generell version</span>' : ''}
`;
```

- [ ] **Step 4: Låt paketsektionen ligga kvar i samma flöde men tydligare under globalt filter**

Ingen ny separat logik för paket behövs. Säkerställ bara att `loadCatalogPackages()` triggas från samma globala profilval som övrigt innehåll och att rubriken/sektionen visuellt läses som del av samma katalogflöde.

- [ ] **Step 5: Verifiera att filtervalet faktiskt ändrar katalogsektionerna**

Manual check i browser:
- `Alla` visar full katalog
- `Privat` visar färre statiska prompts och fortfarande katalogkort, med fallbackbadge där relevant
- `Företag` ändrar både statiska prompts och katalogsektionens upplevda innehåll

- [ ] **Step 6: Commit**

```bash
git add script.js
git commit -m "feat(web): apply global single-select context to catalog sections"
```

### Task 4: Rensa regressionsstöd, localStorage-test och slutverifiering

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/style.css`

**Interfaces:**
- Consumes: existerande regressionstestloggar i `script.js`.
- Produces:
  - uppdaterat lokalt roundtrip-test för enkelvals-storage
  - slutgiltig UI-klass för fallbackbadge

- [ ] **Step 1: Uppdatera regressionstestet för storage**

Byt `testCatalogProfileStorage()` från lista till enkelvärde:

```js
function testCatalogProfileStorage() {
    const realValue = localStorage.getItem(CATALOG_PROFILE_STORAGE_KEY);
    const testKey = 'skola';
    saveGlobalContextSelection(testKey);
    const roundTripped = loadGlobalContextSelection();

    if (realValue === null) {
        localStorage.removeItem(CATALOG_PROFILE_STORAGE_KEY);
    } else {
        localStorage.setItem(CATALOG_PROFILE_STORAGE_KEY, realValue);
    }

    return roundTripped === testKey;
}
```

- [ ] **Step 2: Lägg till en liten fallbackbadge-stil**

I `style.css`:

```css
.catalog-context-badge {
    display: inline-block;
    margin-top: 0.55rem;
    padding: 0.15rem 0.5rem;
    border-radius: 999px;
    background: #f2f4f7;
    color: #475467;
    font-size: 0.74rem;
    font-weight: 600;
}
```

- [ ] **Step 3: Kör slutverifiering**

Run:

```powershell
npm run build
```

Expected:
- build grönt
- inga nya console-fel i `script.js`

Manual browser verification:
- profilvalet ligger högt upp
- exakt ett val är aktivt åt gången
- den vanliga promptlistan påverkas
- katalogprompts påverkas
- paket påverkas
- fallbackbadge syns i icke-generella lägen
- inga tomma vita kort eller gamla checkbox-beteenden kvarstår

- [ ] **Step 4: Commit**

```bash
git add script.js style.css
git commit -m "fix(web): finalize global context filter UX"
```

## Self-Review

- **Spec coverage:** Planen täcker alla beslut i specen: global placering, enkelval, hela sidan påverkas, fallback synlig, prompts och paket kvar som sektioner, localStorage som enkelvärde. Ingen separat URL/deep-linking-task lades till eftersom specen säger att det inte är krav i första versionen.
- **Placeholder scan:** Inga `TODO`, `TBD` eller ospecificerade “lägg till validering senare”-steg finns kvar. Alla steg pekar på konkreta filer, funktioner eller kodblock.
- **Type consistency:** Enkelvals-API:t använder konsekvent `loadGlobalContextSelection()`, `saveGlobalContextSelection(key)`, `getActiveContextKey()` och RPC-adaptern `getActiveContextKeys()`.
