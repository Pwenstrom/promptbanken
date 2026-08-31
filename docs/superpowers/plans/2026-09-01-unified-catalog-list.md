# Enhetlig promptkatalog i webben (Fas A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gör "Alla prompter" till en sammanhållen lista utan
dubblerad rendering av egna prompter, med källmärkning och enhetlig
knappstorlek över statiska och katalog-baserade kort.

**Architecture:** Ren frontend-ändring i `promptbanken.html`/`script.js`/
`style.css`. Ingen backend-ändring — de RPC:er och det "redan
tillagd i biblioteket"-tillstånd specen ursprungligen beskrev
(`add_catalog_prompt_to_library`, `add_catalog_package_to_library`,
`markCatalogPromptInLibrary`/`markCatalogPackageInLibrary`,
`libraryReferencePromptIds`/`libraryReferencePackageIds`) är **redan
skarpt levererade** på `main` (se "Redan levererat, INTE del av detta
bygge" nedan) — upptäckt vid worktree-uppsättningen 2026-09-01, efter
att specen och den ursprungliga versionen av denna plan skrevs mot en
äldre branch. Kvarvarande arbete är tre fristående, mindre ändringar:
ta bort en dubblerad rendering, lägg till en källbadge, och slå ihop
två griddar visuellt.

**Tech Stack:** Vanilla JS (`script.js`, ingen bundling), Supabase JS-
klient (`promptbanken.html`s inline `<script type="module">`), rå CSS.

**Spec:** `docs/superpowers/specs/2026-09-01-unified-catalog-list-design.md`
(bakgrund/motivering fortfarande giltig; dess avsnitt "Ny fråga: vad är
redan tillagt" och paket-lägg-till-delen är nu redan byggda — se notan
nedan)

## Redan levererat, INTE del av detta bygge

Verifierat i kod på `main` (commits `6001e89`, `a9bf4a5`, `7c6d542`,
`c8b51fd`) vid uppsättningen av denna plans worktree:

- Beständigt "redan tillagd"-tillstånd på katalogpromptkort
  (`script.js`: `libraryReferencePromptIds`, `markCatalogPromptInLibrary`,
  läses/sätts redan vid sidladdning i `promptbanken.html:672-687`).
- Samma för paket (`libraryReferencePackageIds`,
  `markCatalogPackageInLibrary`).
- Paketkort har redan "Öppna paket" + "Lägg till i Mitt bibliotek"
  staplade (`script.js`, `createCatalogPackageCard`).
- En toast-liknande bekräftelse (`showLibraryConfirmation`,
  `promptbanken.html:744-754`) och en länk till "Mitt bibliotek"
  (`creator.html`) finns redan.

Rör INGET av detta i denna plan — det är redan i produktion och
fungerar.

## Global Constraints

- Rör INTE: `privacy.html`, `privacy-mcp.html`, `mcp.html`, `terms.html`,
  `/paket/<slug>/`-permalänkar, paketets query-param-djuplänk
  (`openCatalogPackageDetail`), `mcp_promptbanken`-repot.
- Ingen ny Supabase-migration, ingen ny RPC.
- Ingen dedupe mellan `prompts.json` och Supabase-katalogen — de
  renderas som separata, korrekt märkta kort om de råkar överlappa i
  innehåll.
- Paketgridden (`#catalog-package-grid`) flyttas INTE i denna fas —
  flytt till egen flik är Fas B.
- All ny färg/typografi återanvänder befintliga tokens i `style.css`.

---

### Task 1: Ta bort den dubblerande "Dina prompter"-hyllan

**Files:**
- Modify: `promptbanken.html:199-212` (ta bort sektionen, flytta kvotmätaren)
- Modify: `promptbanken.html:707-742` (`loadMyPrompts`, sista delen)

**Interfaces:**
- Consumes: `window.registerOwnPrompts` (`script.js`, orörd — lägger
  redan egna prompter i `#prompt-grid` via `createPromptCard`),
  `registerAndSelectLibraryItem` (`src/creatorLibrary.js`, orörd).
- Produces: inget nytt — detta är en borttagning.

**Bakgrund:** `registerOwnPrompts(items)` (anropas via
`registerAndSelectLibraryItem` i `promptbanken.html:736-741`) lägger
redan varje egen prompt i `allPrompts` och renderar den som ett
vanligt `.prompt-card.own-prompt-card` i `#prompt-grid` (amber
vänsterkant, `.own-chip`-etikett "Din prompt · Privat/Delad" — se
`style.css:5487-5499`). `<section id="my-prompts-rail">` visar SAMMA
objekt en gång till som separata liggande "tiles" via
`renderMyPromptsTiles` (`promptbanken.html:734`, körs OMEDELBART före
`registerAndSelectLibraryItem` på nästa rad). Det är den bokstavliga
renderings-dubbletten. Ren borttagning av den överflödiga andra
renderingen — ingen ny sammanslagningslogik.

- [ ] **Step 1: Ta bort hylle-sektionen ur `promptbanken.html`**

Ta bort rad 199-212 i sin helhet:

```html
                <section class="my-prompts-rail" id="my-prompts-rail" hidden aria-label="Dina egna prompter">
                    <div class="my-prompts-header">
                        <h2>Dina prompter</h2>
                        <div class="plan-meter my-prompts-meter" id="my-prompts-meter" hidden>
                            <div class="plan-meter-row">
                                <span class="plan-meter-label">Aktiva prompter</span>
                                <span class="plan-meter-value" id="my-prompts-meter-value">0 / 3</span>
                            </div>
                            <div class="plan-meter-track"><div class="plan-meter-fill" id="my-prompts-meter-fill" style="width:0%"></div></div>
                        </div>
                        <a class="my-prompts-manage-link" href="admin.html">Hantera i workspace →</a>
                    </div>
                    <div id="my-prompts-body"></div>
                </section>
```

Ersätt den med en fristående, kompakt kvotmätare (samma tre id:n som
`renderMyPromptsMeter` redan skriver till, så den funktionen kräver
INGEN kodändring) direkt efter `page-title-row`-blocket, före
`context-filter-bar`-sektionen:

```html
                <div class="plan-meter my-prompts-meter" id="my-prompts-meter" hidden>
                    <div class="plan-meter-row">
                        <span class="plan-meter-label">Aktiva egna prompter</span>
                        <span class="plan-meter-value" id="my-prompts-meter-value">0 / 3</span>
                    </div>
                    <div class="plan-meter-track"><div class="plan-meter-fill" id="my-prompts-meter-fill" style="width:0%"></div></div>
                </div>
```

- [ ] **Step 2: Ta bort den dubblerande renderingen i `loadMyPrompts()`**

Nuvarande kod (`promptbanken.html:707-742`):

```javascript
        const rail = document.getElementById('my-prompts-rail');
        const body = document.getElementById('my-prompts-body');
        if (!rail || !body) return;

        rail.hidden = false;

        const activeItems = items || [];
        if (!activeItems.length) {
          renderMyPromptsEmpty(body);
          return;
        }

        if (workspace?.max_prompts) {
          renderMyPromptsMeter(activeItems.filter((item) => item.status !== 'archived').length, workspace.max_prompts);
        }

        const mappedItems = activeItems.map((item) => ({
          id: item.id,
          title: item.title,
          description: item.summary || (item.content || '').slice(0, 140),
          content: item.content,
          visibility: item.visibility,
          category: item.category,
          audience: item.audience,
          risk: riskLabels[item.risk_level] || riskLabels.low
        }));

        renderMyPromptsTiles(body, mappedItems);
        const requestedLibraryItem = new URLSearchParams(window.location.search).get('libraryItem');
        await registerAndSelectLibraryItem({
          items: mappedItems,
          requestedId: requestedLibraryItem,
          register: (itemsToRegister) => window.registerOwnPrompts?.(itemsToRegister),
          select: (id, options) => window.selectWorkflowPrompt?.(id, options)
        });
      }
```

Ersätt med (tar bort `rail`/`body`-vakten så registrering aldrig
längre är villkorad av ett DOM-element som inte finns kvar, tar bort
`renderMyPromptsTiles`-anropet, flyttar tomt-läge-kontrollen efter
kvotmätaren så mätaren fortfarande uppdateras även när listan är tom):

```javascript
        const activeItems = items || [];

        if (workspace?.max_prompts) {
          renderMyPromptsMeter(activeItems.filter((item) => item.status !== 'archived').length, workspace.max_prompts);
        }

        if (!activeItems.length) return;

        const mappedItems = activeItems.map((item) => ({
          id: item.id,
          title: item.title,
          description: item.summary || (item.content || '').slice(0, 140),
          content: item.content,
          visibility: item.visibility,
          category: item.category,
          audience: item.audience,
          risk: riskLabels[item.risk_level] || riskLabels.low
        }));

        const requestedLibraryItem = new URLSearchParams(window.location.search).get('libraryItem');
        await registerAndSelectLibraryItem({
          items: mappedItems,
          requestedId: requestedLibraryItem,
          register: (itemsToRegister) => window.registerOwnPrompts?.(itemsToRegister),
          select: (id, options) => window.selectWorkflowPrompt?.(id, options)
        });
      }
```

- [ ] **Step 3: Ta bort de nu oanvända render-hjälparna**

I `promptbanken.html`, ta bort funktionerna `renderMyPromptsEmpty`
(rad 586-593) och `renderMyPromptsTiles` (rad 595-613) i sin helhet —
inget anropar dem längre. Behåll `renderMyPromptsMeter` (rad 615-626),
den används fortfarande av Step 2.

- [ ] **Step 4: Testa manuellt**

Kör `npm run web:dev`, ladda katalogen inloggad som en användare med
minst en egen prompt. Bekräfta: (a) ingen separat amber-hylla visas
längre ovanför arbetsflödet, (b) den egna prompten syns EN gång i
huvudgridden med amber vänsterkant och "Din prompt · Privat/Delad"-
chip, (c) den lilla kvotmätaren ("X / 3") visas där hyllan satt förut,
(d) om URL:en har `?libraryItem=<id>` väljs fortfarande rätt prompt
automatiskt (testa `promptbanken.html?libraryItem=<ett-riktigt-id>`).

- [ ] **Step 5: Commit**

```bash
git add promptbanken.html
git commit -m "fix(catalog): remove duplicate own-prompts rail, keep single grid render

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CxvKYZqHJdUvKDuzHbogqt"
```

---

### Task 2: Källmärkning och enhetlig knappstorlek på statiska kort

**Files:**
- Modify: `script.js:2099-2144` (`createPromptCard`)
- Modify: `promptbanken.html:25-59` (page-scoped `<style>`-block)

**Interfaces:**
- Consumes: `prompt.own` (redan satt av `registerOwnPrompts`, finns
  bara på egna prompter — statiska `prompts.json`-poster saknar
  fältet, vilket är precis den signal som behövs).
- Produces: inget nytt gränssnitt — visuell justering av redan
  existerande kort.

**Bakgrund:** `.prompt-card .card-actions .select-prompt-btn` tvingas
till `width: auto` av den sidspecifika `<style>`-regeln i
`promptbanken.html:52-54`, medan katalogkortens knappar ärver bas-
CSS:ns `width: 100%` (`style.css:670-697`) och därför staplas i full
bredd. Detta är källan till knappstorleks-inkonsekvensen mellan
"Alla prompter"-kort och katalog-/paketkort — ingen ny knappklass
behövs, bara att ta bort overridet.

- [ ] **Step 1: Ta bort bredd-overridet i `promptbanken.html`s `<style>`-block**

Nuvarande (rad 25-59):

```html
    <style>
        .quick-input-header {
            align-items: flex-start;
        }

        .quick-input-header > h3 {
            display: none;
        }

        .prompt-grid .prompt-card {
            position: relative;
            transition: border-color 0.2s ease, box-shadow 0.2s ease;
        }

        .prompt-grid .prompt-card .card-actions {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
            align-items: center;
        }

        .prompt-grid .prompt-card .card-actions .export-btn,
        .prompt-grid .prompt-card .card-actions .copy-btn,
        .prompt-grid .prompt-card .card-actions .local-chat-btn,
        .prompt-grid .prompt-card .card-actions .direct-chat-btn {
            display: none !important;
        }

        .prompt-grid .prompt-card .select-prompt-btn {
            width: auto;
        }

        .prompt-grid .prompt-card .info-btn {
            opacity: 0.78;
        }
    </style>
```

Ersätt med (tar bort `width: auto`-regeln och byter `.card-actions`
till kolumn-stapling så den matchar katalog-/paketkortens resultat
exakt, istället för att förlita sig på att raden är för smal för att
rymma två knappar):

```html
    <style>
        .quick-input-header {
            align-items: flex-start;
        }

        .quick-input-header > h3 {
            display: none;
        }

        .prompt-grid .prompt-card {
            position: relative;
            transition: border-color 0.2s ease, box-shadow 0.2s ease;
        }

        .prompt-grid .prompt-card .card-actions {
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
        }

        .prompt-grid .prompt-card .card-actions .export-btn,
        .prompt-grid .prompt-card .card-actions .copy-btn,
        .prompt-grid .prompt-card .card-actions .local-chat-btn,
        .prompt-grid .prompt-card .card-actions .direct-chat-btn {
            display: none !important;
        }

        .prompt-grid .prompt-card .info-btn {
            opacity: 0.78;
        }
    </style>
```

- [ ] **Step 2: Lägg till källbadge för icke-egna kort i `createPromptCard`**

I `script.js`, funktionen `createPromptCard` (rad 2099-2144) bygger
redan `ownChip`. Nuvarande kod:

```javascript
            const ownChip = prompt.own
                ? `<span class="own-chip">${prompt.ownVisibility === 'workspace' ? 'Din prompt · Delad' : 'Din prompt · Privat'}</span>`
                : '';
```

Lägg till en syskonrad direkt efter:

```javascript
            const ownChip = prompt.own
                ? `<span class="own-chip">${prompt.ownVisibility === 'workspace' ? 'Din prompt · Delad' : 'Din prompt · Privat'}</span>`
                : '';
            const sourceChip = prompt.own
                ? ''
                : `<span class="static-source-chip">Promptbanken</span>`;
```

Ändra sedan `card-tags`-blocket i `card.innerHTML` (samma funktion)
från

```javascript
                <div class="card-tags">
                    ${ownChip}
                    <span class="risk-chip" data-risk="${meta.risk.toLowerCase()}">${meta.risk}</span>
```

till

```javascript
                <div class="card-tags">
                    ${ownChip}${sourceChip}
                    <span class="risk-chip" data-risk="${meta.risk.toLowerCase()}">${meta.risk}</span>
```

`.static-source-chip` behöver ingen ny CSS-regel — `.card-tags span`
(`style.css:3477` och följande) ger den redan den neutrala grå pillen
som resten av taggarna i raden har.

- [ ] **Step 3: Testa manuellt**

Ladda katalogen. Bekräfta: (a) en vanlig, inbyggd prompt (inte din
egen) visar en grå "Promptbanken"-tagg bland sina övriga taggar, (b)
en egen prompt visar fortfarande bara sin amber "Din prompt"-chip,
INTE båda, (c) Välj/Förhandsvisa-knapparna på statiska kort nu är
fullbredd och staplade, likadant utseende som katalog-/paketkortens
knappar.

- [ ] **Step 4: Commit**

```bash
git add script.js promptbanken.html
git commit -m "feat(catalog): add source badge and align button width on static cards

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CxvKYZqHJdUvKDuzHbogqt"
```

---

### Task 3: Slå ihop "Alla prompter" och "Öppen katalog" visuellt till en lista

**Files:**
- Modify: `promptbanken.html:295-307` (ta bort mellanliggande rubrik)
- Modify: `style.css:5642-5646` (ta bort separatorn ovanför sektionen)
- Modify: `style.css:5806-5811` (jämna ut kolumnbredden)

**Interfaces:**
- Consumes: inget nytt.
- Produces: inget nytt — ren visuell sammanslagning. Filter-/
  räknelogiken (`applyAllFilters()`, `script.js`) är redan delad över
  alla källor och rörs inte.

- [ ] **Step 1: Ta bort rubrikblocket mellan de två griddarna**

I `promptbanken.html`, nuvarande rad 295-307:

```html
                <p class="result-count" id="result-count">Visar prompter</p>

                <section class="catalog-section" id="catalog-section">
                    <div class="catalog-section-heading">
                        <h2>Öppen katalog</h2>
                        <p>Publicerade prompts från Promptbanken för din valda kontext.</p>
                    </div>

                    <h3>Enskilda prompts</h3>
                    <div class="catalog-package-link-error" id="catalog-prompt-link-error" hidden role="alert">
                        Prompten kunde inte hittas eller är inte längre publicerad.
                    </div>
                    <div class="catalog-grid" id="catalog-prompt-grid"></div>
```

Ersätt med (behåll `<section>`-taggen — `renderCatalogUnavailableState`
i `script.js` letar upp den via `#catalog-section` och sätter
`hidden`/innehåll på den; behåll även felmeddelande-div:en, den
används fortfarande vid ogiltig djuplänk):

```html
                <p class="result-count" id="result-count">Visar prompter</p>

                <section class="catalog-section" id="catalog-section">
                    <div class="catalog-package-link-error" id="catalog-prompt-link-error" hidden role="alert">
                        Prompten kunde inte hittas eller är inte längre publicerad.
                    </div>
                    <div class="catalog-grid" id="catalog-prompt-grid"></div>
```

- [ ] **Step 2: Ta bort visuell separator ovanför sektionen**

I `style.css`, nuvarande regel (rad 5642-5646):

```css
.catalog-section {
    margin-top: 3rem;
    padding-top: 2rem;
    border-top: 1px solid var(--border-color, #e2e2e2);
}
```

Ändra till:

```css
.catalog-section {
    margin-top: 0;
}
```

- [ ] **Step 3: Jämna ut kolumnbredden mellan de två griddarna**

`#prompt-grid` (`style.css:3388-3392`) använder
`grid-template-columns: repeat(3, minmax(210px, 1fr))`, `.catalog-grid`
(`style.css:5806-5811`, gäller `#catalog-prompt-grid`) använder
`repeat(auto-fill, minmax(260px, 1fr))`. Vid samma containerbredd ger
det olika antal kolumner i de två griddarna, vilket syns som ett hack
i layouten där de möts. Lägg till en riktad regel i `style.css` direkt
under `.catalog-grid`-regeln (rad 5811):

```css
#catalog-prompt-grid {
    grid-template-columns: repeat(3, minmax(210px, 1fr));
}
```

(Endast `#catalog-prompt-grid` — `#catalog-package-grid` behåller sitt
egna `auto-fill`-beteende, den rörs inte i denna fas.)

- [ ] **Step 4: Testa manuellt**

Ladda katalogen utan sökning. Bekräfta: statiska kort och katalogkort
flyter i samma kolumnraster utan synlig rubrik eller kantlinje mellan
dem — det ser ut som EN lista, inte två sektioner. Sök på en term som
bara matchar en katalogprompt. Bekräfta resultatet visas,
`#result-count` visar korrekt antal, `#prompt-grid-empty` INTE visas
samtidigt.

- [ ] **Step 5: Commit**

```bash
git add promptbanken.html style.css
git commit -m "feat(catalog): merge static and catalog prompt grids into one visual list

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CxvKYZqHJdUvKDuzHbogqt"
```

---

## Efter Fas A

Fas B (paket till egen flik) och Fas C (horisontell overflow — språk-
konsekvensen för "Mitt bibliotek" är redan löst, se
`promptbanken.html:638`) är separata, oberoende planer.
