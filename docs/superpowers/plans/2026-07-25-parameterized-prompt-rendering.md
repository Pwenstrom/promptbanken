# Parameterized Prompt Rendering Implementation Plan

**Status 2026-07-27:** Implementerad på `main` för webb, Supabase-katalog och
hostad MCP. Planen sparas som genomförandehistorik; innehållskvalitet och fler
parameteriserade mallar följs i `TODO.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inför en gemensam parametriserad renderkedja för `kontext`, `roll`, `malgrupp` och `ton` så att Promptbanken kan bygga om prompt- och paketinnehåll utifrån användarens val, först för statiska prompts och sedan för katalog/Supabase.

**Architecture:** Första versionen hålls i befintlig frontendstruktur i `script.js` och `prompts.json`, med ett litet renderlager ovanpå dagens promptladdning. Vi inför en namngiven parameter-/bindingsmodell, en adapter för äldre `[]`, och ett globalt renderstate som används både för filtrering och innehållsrendering. När modellen är stabil utökas den till öppna katalogen och paketdata i Supabase, med samma parameternamn och samma resolveregler.

**Tech Stack:** vanilla JS i `script.js`, statisk JSON i `prompts.json`, texttemplates i `prompts/*.txt`, Supabase JSONB- och read-RPC-ytor i `supabase/migrations/`, MCP-promptkopior i `mcp-server/prompts/` och `mcp-server/skills.json`.

## Global Constraints

- Intern mallsyntax ska vara namngivna platshållare som `{{kontext}}`, `{{roll}}`, `{{malgrupp}}`, `{{ton}}`.
- Bakåtkompatibilitet för befintliga `[]` måste finnas i övergångsfasen.
- Samma logiska modell ska kunna användas i webb, Supabase och MCP.
- Första versionen ska alltid stödja exakt fyra styrande basparametrar: `kontext`, `roll`, `malgrupp`, `ton`.
- `ton` ska vara ett styrt urval, inte ett fritt textfält i första hand.
- Frontend ska fortsatt fungera utan `import`-satser i `script.js`.
- Vid frontendändringar: kör minst `npm run build`.
- Om prompt- eller katalogdata ändras måste webb och MCP inte divergera i betydelse eller parameterbenämning.

---

### Task 1: Inför globalt renderstate och ett rent renderlager i frontend

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`
- Test: manuell verifiering via `promptbanken.html` + `npm run build`

**Interfaces:**
- Consumes: befintliga `getActiveContextKey()`, `replaceInputMarkers()`, `loadPrompts()`, `createPromptCard()`, exportfunktionerna i `script.js`.
- Produces:
  - `getGlobalRenderState(): { kontext: string, roll: string, malgrupp: string, ton: string }`
  - `saveGlobalRenderState(nextState: Partial<...>): void`
  - `resolvePromptBindings(state, schema, defaults, overrides): Record<string, string>`
  - `renderPromptTemplate(template, bindings): string`

- [ ] **Step 1: Skriv ett litet kontrakt i kod för globalt renderstate**

Lägg in konkreta defaultvärden nära övrig katalogstate:

```js
const GLOBAL_RENDER_STATE_KEY = 'promptbankenRenderState';
const DEFAULT_RENDER_STATE = {
    kontext: 'generell',
    roll: 'handläggare',
    malgrupp: 'invånare',
    ton: 'tydlig och vänlig'
};
```

Lägg till funktioner:

```js
function loadGlobalRenderState() { ... }
function saveGlobalRenderState(nextPartialState) { ... }
function getGlobalRenderState() { ... }
```

Regel:
- `kontext` ska alltid speglas från befintligt globalt kontextval
- övriga tre värden ska kunna persisteras i samma stateobjekt

- [ ] **Step 2: Skriv resolver för bindings**

Lägg till minimal ren logik:

```js
function resolvePromptBindings(state, schema, defaults = {}, overrides = []) {
    const bindings = { ...defaults, ...state };
    overrides.forEach((rule) => {
        const matches = Object.entries(rule.when || {}).every(([key, value]) => bindings[key] === value);
        if (matches) Object.assign(bindings, rule.set || {});
    });
    return bindings;
}
```

- [ ] **Step 3: Skriv renderfunktion för namngivna variabler**

Lägg till:

```js
function renderPromptTemplate(template, bindings) {
    return String(template || '').replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_, key) => {
        return Object.prototype.hasOwnProperty.call(bindings, key) ? String(bindings[key] ?? '') : '';
    });
}
```

- [ ] **Step 4: Lägg till adapter för gamla `[]`**

Skapa en explicit adapter i stället för att sprida specialfall:

```js
function adaptLegacyPromptTemplate(template, schema) {
    if (!template.includes('[]')) return template;
    const fallbackField = schema?.legacy_fallback_field || 'input';
    return template.replace('[]', `{{${fallbackField}}}`);
}
```

Första versionen:
- om prompten bara har ett anonymt `[]`, mappa till `{{input}}`
- flera `[]` ska inte “gissas” om till flera olika fält ännu

- [ ] **Step 5: Byt ut dagens direkta markerersättning i kopierings/renderflöden**

Hitta dagens användning av `replaceInputMarkers(...)` och ersätt den i promptflöden med:

```js
const template = adaptLegacyPromptTemplate(rawTemplate, prompt.parameter_schema);
const bindings = resolvePromptBindings(getGlobalRenderState(), prompt.parameter_schema, prompt.default_bindings, prompt.binding_overrides);
const rendered = renderPromptTemplate(template, bindings);
```

`replaceInputMarkers(...)` får vara kvar tillfälligt för gammal fri användarinmatning, men den nya kedjan ska vara den officiella vägen för parametriserade prompts.

- [ ] **Step 6: Kör frontendverifiering**

Run:

```powershell
npm run build
```

Expected:
- build grönt
- inga `script.js`-fel
- befintlig promptvy fortsätter ladda

- [ ] **Step 7: Commit**

```bash
git add script.js
git commit -m "feat(web): add parameterized prompt render pipeline"
```

### Task 2: Lägg in parameter-schema och exempelmetadata för statiska prompts

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/prompts.json`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`
- Optionally modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/prompts/*.txt`

**Interfaces:**
- Consumes: `loadPrompts()`, `getPromptText()`, `createPromptCard()`, den nya renderkedjan från Task 1.
- Produces:
  - `parameter_schema`
  - `default_bindings`
  - `binding_overrides`
  - initial `{{...}}`-migrering eller `legacy_fallback_field`

- [ ] **Step 1: Lägg till parameter_schema på ett litet urval först**

Börja med 3-5 prompts som tydligt använder målgrupp/ton/roll, till exempel:

- `mejl`
- `klarsprak`
- `tvaversioner`
- `informationsutskick`
- `kallelse`

Exempelstruktur i `prompts.json`:

```json
"parameter_schema": {
  "version": 1,
  "legacy_fallback_field": "input",
  "fields": [
    { "key": "kontext", "type": "enum", "source": "global", "required": true },
    { "key": "roll", "type": "enum", "source": "global", "required": true },
    { "key": "malgrupp", "type": "enum", "source": "global", "required": true },
    { "key": "ton", "type": "enum", "source": "global", "required": true, "options": ["neutral", "tydlig och vänlig", "formell"] }
  ]
}
```

- [ ] **Step 2: Lägg till defaults och minst en override per exempelprompt**

Exempel:

```json
"default_bindings": {
  "ton": "tydlig och vänlig"
},
"binding_overrides": [
  {
    "when": { "kontext": "skola" },
    "set": { "malgrupp": "vårdnadshavare" }
  }
]
```

- [ ] **Step 3: Migrera minst en prompttext till `{{...}}`**

Välj en konkret prompt, till exempel `prompts/mejl.txt`, och byt från rent fri text till minst en tydlig namngiven platshållare.

Exempel:

```text
Skriv ett svar i {{ton}} ton till {{malgrupp}}.
Utgå från att avsändaren har rollen {{roll}} i {{kontext}}.
```

- [ ] **Step 4: Rendera den renderade versionen i detaljpanelen**

Säkerställ att `getPromptText(promptId)` använder promptens metadata och returnerar renderad text i stället för bara rå text.

- [ ] **Step 5: Kör verifiering**

Run:

```powershell
npm run build
```

Manual check:
- ändra `kontext`
- ändra `roll`
- ändra `målgrupp`
- ändra `ton`
- kontrollera att minst en migrerad prompt faktiskt ändrar textinnehåll

- [ ] **Step 6: Commit**

```bash
git add prompts.json prompts/*.txt script.js
git commit -m "feat(web): add prompt parameter schemas for static prompts"
```

### Task 3: Bygg UI för `roll`, `målgrupp` och `ton`

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/promptbanken.html`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/style.css`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`

**Interfaces:**
- Consumes: globalt kontextfilter, `getGlobalRenderState()`, `saveGlobalRenderState(...)`.
- Produces:
  - tre nya globala valkontroller
  - en gemensam omrenderingssignal för hela sidan

- [ ] **Step 1: Lägg till UI-containers nära globala kontextbaren**

Lägg in tre styrda fält i `promptbanken.html`:

```html
<label class="context-filter-control">
  <span>Roll</span>
  <select id="global-role-select"></select>
</label>
<label class="context-filter-control">
  <span>Målgrupp</span>
  <select id="global-audience-select"></select>
</label>
<label class="context-filter-control">
  <span>Ton</span>
  <select id="global-tone-select"></select>
</label>
```

- [ ] **Step 2: Lägg till optionskällor i JS**

Minsta hårdkodade uppsättningar i första versionen:

```js
const GLOBAL_ROLE_OPTIONS = ['handläggare', 'chef', 'kommunikatör', 'pedagog', 'samordnare'];
const GLOBAL_AUDIENCE_OPTIONS = ['invånare', 'medarbetare', 'allmänhet', 'vårdnadshavare', 'elever'];
const GLOBAL_TONE_OPTIONS = ['neutral', 'tydlig och vänlig', 'formell', 'rak och handlingsorienterad', 'varm och trygg', 'pedagogisk'];
```

- [ ] **Step 3: Rendera och koppla select-fälten till global state**

Skapa:

```js
function initGlobalRenderControls() { ... }
```

Varje ändring ska:
- spara värdet i globalt renderstate
- trigga `loadPrompts()`
- vid behov trigga omrendering av aktiv detaljpanel

- [ ] **Step 4: Lägg till enkel stil så kontrollerna hör ihop**

Lägg till CSS så att kontext, roll, målgrupp och ton läses som ett enda kontrollblock, inte fyra lösa widgetar.

- [ ] **Step 5: Kör verifiering**

Run:

```powershell
npm run build
```

Manual check:
- valen syns högt upp
- ändringar i `roll`, `målgrupp` och `ton` påverkar minst de migrerade statiska promptarna

- [ ] **Step 6: Commit**

```bash
git add promptbanken.html style.css script.js
git commit -m "feat(web): add global controls for role audience and tone"
```

### Task 4: Inför samma modell för öppna katalogprompts och paket i frontend

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/migrations/*.sql` (read/write modelling in later task)

**Interfaces:**
- Consumes: `loadCatalogPrompts()`, `openCatalogPromptDetail()`, `loadCatalogPackages()`, `openCatalogPackageDetail()`, renderkedjan från Task 1.
- Produces:
  - frontendstöd för `parameter_schema` även på katalogobjekt
  - konsekvent rendering i detaljpaneler

- [ ] **Step 1: Definiera frontend-normalisering för katalogobjekt**

Skapa en normaliserare:

```js
function normalizeCatalogTemplateEntity(entity) {
    return {
        ...entity,
        parameter_schema: entity.parameter_schema || null,
        default_bindings: entity.default_bindings || {},
        binding_overrides: entity.binding_overrides || []
    };
}
```

- [ ] **Step 2: Rendera promptdetaljer med nya bindings om metadata finns**

I `renderCatalogDetailVariant(...)`:
- om `variant.parameter_schema` finns, rendera texten via `renderPromptTemplate(...)`
- annars visa råtext som idag

- [ ] **Step 3: Rendera paketintro med samma regel**

Om paketvariant har `intro_text` och parameterdata ska även den passera samma renderkedja.

- [ ] **Step 4: Behåll fallback till gammal vy utan krasch**

Ingen katalogpost får bli tom bara för att parameterdata saknas. Gammalt innehåll ska visas som råtext om metadata inte finns.

- [ ] **Step 5: Kör verifiering**

Run:

```powershell
npm run build
```

Expected:
- katalogdetaljer fortsätter öppnas
- inga JS-fel när äldre katalogposter saknar parameterfält

- [ ] **Step 6: Commit**

```bash
git add script.js
git commit -m "feat(web): support parameterized rendering in catalog details"
```

### Task 5: Lägg till datamodell i Supabase för parameter-schema och bindings

**Files:**
- Create: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/migrations/20260725xxxxxx_catalog_parameter_schemas.sql`
- Modify: relevanta read/write-RPC-migrationer under `supabase/migrations/`
- Test: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/tests/verify_catalog_core.sql`

**Interfaces:**
- Consumes: katalogtabeller och read-RPC:er.
- Produces:
  - `parameter_schema jsonb`
  - `default_bindings jsonb`
  - `binding_overrides jsonb`

- [ ] **Step 1: Lägg till nya JSONB-kolumner**

För promptvarianter:

```sql
alter table public.catalog_prompt_variants
  add column if not exists parameter_schema jsonb,
  add column if not exists default_bindings jsonb default '{}'::jsonb,
  add column if not exists binding_overrides jsonb default '[]'::jsonb;
```

För paketvarianter:

```sql
alter table public.catalog_package_variants
  add column if not exists parameter_schema jsonb,
  add column if not exists default_bindings jsonb default '{}'::jsonb,
  add column if not exists binding_overrides jsonb default '[]'::jsonb;
```

- [ ] **Step 2: Uppdatera read-RPC:erna**

`list_...` och `get_...` ska returnera de nya fälten där det är rimligt. Minimikrav:
- detalj-RPC:er måste returnera dem
- list-RPC:er får returnera dem om payloaden hålls rimlig

- [ ] **Step 3: Lägg till verifierings-SQL**

Lägg till enkla assertions i testfil som bekräftar att:
- nya kolumner finns
- JSONB returneras från detalj-RPC:er

- [ ] **Step 4: Dokumentera rollbackbar migration**

Migrationen ska vara additive och inte bryta befintliga anrop som ännu inte använder dessa fält.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/*.sql supabase/tests/verify_catalog_core.sql
git commit -m "feat(db): add parameter schemas to catalog variants"
```

### Task 6: Synka modellen till MCP och undvik divergens

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/mcp-server/skills.json`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/mcp-server/prompts/*.txt`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/mcp-server/server/*.py` vid behov

**Interfaces:**
- Consumes: samma parameternamn och mallsyntax som webben.
- Produces:
  - MCP-kompatibel parameterrepresentation
  - samma ton-/målgrupps-/rollmodell som webben

- [ ] **Step 1: Spegla namngivna platshållare i MCP-prompts där samma prompt finns**

Migrera samma exempelprompts i `mcp-server/prompts/*.txt` så de inte halkar efter webbkopiorna.

- [ ] **Step 2: Lägg till metadatafält i MCP om de saknas**

Om `skills.json` behöver bära ton/roll/målgrupp som tydliga metadatafält ska det göras additivt.

- [ ] **Step 3: Verifiera att MCP-servern fortfarande startar**

Run:

```powershell
npm run check:python
```

Expected:
- ingen syntax- eller importkrasch

- [ ] **Step 4: Commit**

```bash
git add mcp-server/prompts/*.txt mcp-server/skills.json mcp-server/server/*.py
git commit -m "feat(mcp): align prompt rendering parameters with web model"
```

## Self-Review

- **Spec coverage:** Planen täcker den tekniska specens huvudkrav: namngivna platshållare, fyra basparametrar, globalt renderstate, adapter för `[]`, statiska promptmetadata, katalog/Supabase-utökning och MCP-synk.
- **Placeholder scan:** Inga `TODO`/`TBD`-steg lämnade. Varje task pekar på konkreta filer, funktioner och testkommandon.
- **Type consistency:** Parameternamn hålls konsekvent som `kontext`, `roll`, `malgrupp`, `ton`, samt metadatafälten `parameter_schema`, `default_bindings`, `binding_overrides`.
