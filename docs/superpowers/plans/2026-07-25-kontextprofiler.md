# Kombinerbara kontextprofiler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Låt läsare (webb + MCP) välja flera kontextprofiler samtidigt (t.ex. Kommun + Skola) och få kombinerat innehåll: en deduplicerad rad per post i listor, alla matchande varianter som flikar i detaljvy.

**Architecture:** Read-RPC:erna i Supabase byter från `p_context_key text` till `p_context_keys text[]`. Listfunktioner dedupar till en rad per post (copy från första matchande profilen i arrayordning, annars `generell`). Detaljfunktioner returnerar en rad per matchande context_key plus alltid en garanterad `generell`-rad. MCP-verktygen och en ny, fristående frontend-katalogsektion (separat från befintlig `prompts.json`-rendering) anropar samma array-baserade RPC:er.

**Tech Stack:** PostgreSQL/Supabase (plpgsql/SQL RPC, `create or replace`), Python/FastMCP (`mcp-server/server/`), vanilla JS i `script.js` + `index.html` + `style.css` (ingen bundling, inga `import`-satser).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-25-kontextprofiler-design.md` styr hela planen.
- Ingen schemaändring: `catalog_prompts`, `catalog_prompt_variants`, `catalog_packages`, `catalog_package_variants`, `catalog_package_items` och `context_key`-checken är oförändrade.
- Endast läs-RPC:er ändras. Skriv-RPC:er (`create_catalog_prompt`, `publish_catalog_prompt`, m.fl. från 2026-07-21-planen) rörs inte.
- Profilval lagras i `localStorage`, aldrig kopplat till Supabase-konto.
- `script.js` får inga `import`-satser (repo-regel) — Supabase REST-anrop görs med råa `fetch()`-anrop mot `${SUPABASE_URL}/rest/v1/rpc/<function>`, samma mönster som `mcp-server/server/catalog.py` redan använder mot Supabase REST.
- Ingen pytest/npm-testrunner finns i repot. Verifiering sker via `rg`-sökningar (SQL/Python) och manuell körning i webbläsarens dev-konsol (`npm run web:dev`), i linje med befintligt mönster i `script.js` (t.ex. `testLocalStorage()`, `performRegressionTests()`).
- Katalogsektionen i frontend är fristående från `prompts.json`-flödet: egen container, egen `loadCatalog*`-funktion, egna kort. `loadPrompts()`/`createPromptCard()` i `script.js` ändras inte.

---

### Task 1: Read-RPC:er byter till context_keys-array

**Files:**
- Create: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/migrations/20260725100000_catalog_read_context_arrays.sql`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/tests/verify_catalog_core.sql`

**Interfaces:**
- Consumes: `public.catalog_prompts`, `public.catalog_prompt_variants`, `public.catalog_packages`, `public.catalog_package_variants`, `public.catalog_package_items` (oförändrade från 2026-07-21-migrationerna).
- Produces (ersätter tidigare `(text)`/`(text, text)`-signaturer helt):
  - `public.list_published_prompts(p_context_keys text[] default array['generell'])` → `(id, slug, icon_key, image_key, color_theme, title, summary, prompt_text, example_input, audience_label, tone_hint)`
  - `public.get_published_prompt(p_slug text, p_context_keys text[] default array['generell'])` → samma kolumner plus `context_key text`, en rad per matchande variant (matchande profiler i arrayordning, `generell` alltid sist)
  - `public.list_published_packages(p_context_keys text[] default array['generell'], p_package_type text default null)` → `(id, slug, package_type, icon_key, image_key, color_theme, title, summary, intro_text, audience_label)`
  - `public.get_published_package(p_slug text, p_context_keys text[] default array['generell'])` → samma kolumner plus `context_key text`, en rad per matchande variant
  - `public.list_published_package_prompts(p_package_slug text, p_context_keys text[] default array['generell'])` → `(prompt_id, prompt_slug, icon_key, image_key, color_theme, title, summary, prompt_text, example_input, audience_label, tone_hint, sort_order, step_title, step_intro, is_required)`

- [ ] **Step 1: Utöka verifieringsfilen med signaturkontroll**

Lägg till i slutet av `verify_catalog_core.sql`:

```sql
-- Kontextprofiler: read-RPC:er ska ta text[] (inte text) som kontextparameter
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
where p.proname in (
  'list_published_prompts',
  'get_published_prompt',
  'list_published_packages',
  'get_published_package',
  'list_published_package_prompts'
)
order by p.proname;
```

- [ ] **Step 2: Skriv migrationen — droppa gamla text-baserade funktioner**

`20260725100000_catalog_read_context_arrays.sql`, första delen:

```sql
-- 20260725100000_catalog_read_context_arrays.sql
-- Byter read-RPC:erna från en enskild p_context_key till en kombinerbar
-- p_context_keys text[]. Listfunktioner dedupar till en rad per post;
-- detaljfunktioner returnerar en rad per matchande variant plus generell.

drop function if exists public.list_published_prompts(text);
drop function if exists public.get_published_prompt(text, text);
drop function if exists public.list_published_packages(text, text);
drop function if exists public.get_published_package(text, text);
drop function if exists public.list_published_package_prompts(text, text);
```

- [ ] **Step 3: Implementera `list_published_prompts` (dedup, array-prioritet)**

```sql
create or replace function public.list_published_prompts(
    p_context_keys text[] default array['generell']
)
returns table (
    id uuid,
    slug text,
    icon_key text,
    image_key text,
    color_theme text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cp.id,
        cp.slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(matched.example_input, fallback.example_input) as example_input,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label,
        coalesce(matched.tone_hint, fallback.tone_hint) as tone_hint
    from public.catalog_prompts cp
    left join lateral (
        select v.*
          from public.catalog_prompt_variants v
         where v.prompt_id = cp.id
           and v.context_key = any(p_context_keys)
         order by array_position(p_context_keys, v.context_key)
         limit 1
    ) matched on true
    left join public.catalog_prompt_variants fallback
      on fallback.prompt_id = cp.id
     and fallback.context_key = 'generell'
    where cp.status = 'published'
    order by cp.slug;
$$;

revoke all on function public.list_published_prompts(text[]) from public;
grant execute on function public.list_published_prompts(text[]) to anon, authenticated;
```

- [ ] **Step 4: Implementera `get_published_prompt` (alla matchande varianter + generell)**

```sql
create or replace function public.get_published_prompt(
    p_slug text,
    p_context_keys text[] default array['generell']
)
returns table (
    id uuid,
    slug text,
    icon_key text,
    image_key text,
    color_theme text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cp.id,
        cp.slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        v.context_key,
        v.title,
        v.summary,
        v.prompt_text,
        v.example_input,
        v.audience_label,
        v.tone_hint
    from public.catalog_prompts cp
    join public.catalog_prompt_variants v on v.prompt_id = cp.id
    where cp.slug = p_slug
      and cp.status = 'published'
      and (v.context_key = any(p_context_keys) or v.context_key = 'generell')
    order by
        case when v.context_key = 'generell' then 1 else 0 end,
        coalesce(array_position(p_context_keys, v.context_key), 999);
$$;

revoke all on function public.get_published_prompt(text, text[]) from public;
grant execute on function public.get_published_prompt(text, text[]) to anon, authenticated;
```

- [ ] **Step 5: Implementera `list_published_packages` och `get_published_package`**

Samma två mönster som Steg 3–4, men på `catalog_packages`/`catalog_package_variants` och med fälten `intro_text` istället för `prompt_text`/`example_input`/`tone_hint`:

```sql
create or replace function public.list_published_packages(
    p_context_keys text[] default array['generell'],
    p_package_type text default null
)
returns table (
    id uuid,
    slug text,
    package_type text,
    icon_key text,
    image_key text,
    color_theme text,
    title text,
    summary text,
    intro_text text,
    audience_label text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cpkg.id,
        cpkg.slug,
        cpkg.package_type,
        cpkg.icon_key,
        cpkg.image_key,
        cpkg.color_theme,
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.intro_text, fallback.intro_text) as intro_text,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label
    from public.catalog_packages cpkg
    left join lateral (
        select v.*
          from public.catalog_package_variants v
         where v.package_id = cpkg.id
           and v.context_key = any(p_context_keys)
         order by array_position(p_context_keys, v.context_key)
         limit 1
    ) matched on true
    left join public.catalog_package_variants fallback
      on fallback.package_id = cpkg.id
     and fallback.context_key = 'generell'
    where cpkg.status = 'published'
      and (p_package_type is null or cpkg.package_type = p_package_type)
    order by cpkg.slug;
$$;

revoke all on function public.list_published_packages(text[], text) from public;
grant execute on function public.list_published_packages(text[], text) to anon, authenticated;

create or replace function public.get_published_package(
    p_slug text,
    p_context_keys text[] default array['generell']
)
returns table (
    id uuid,
    slug text,
    package_type text,
    icon_key text,
    image_key text,
    color_theme text,
    context_key text,
    title text,
    summary text,
    intro_text text,
    audience_label text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cpkg.id,
        cpkg.slug,
        cpkg.package_type,
        cpkg.icon_key,
        cpkg.image_key,
        cpkg.color_theme,
        v.context_key,
        v.title,
        v.summary,
        v.intro_text,
        v.audience_label
    from public.catalog_packages cpkg
    join public.catalog_package_variants v on v.package_id = cpkg.id
    where cpkg.slug = p_slug
      and cpkg.status = 'published'
      and (v.context_key = any(p_context_keys) or v.context_key = 'generell')
    order by
        case when v.context_key = 'generell' then 1 else 0 end,
        coalesce(array_position(p_context_keys, v.context_key), 999);
$$;

revoke all on function public.get_published_package(text, text[]) from public;
grant execute on function public.get_published_package(text, text[]) to anon, authenticated;
```

- [ ] **Step 6: Implementera `list_published_package_prompts` (dedup per prompt-i-paket)**

```sql
create or replace function public.list_published_package_prompts(
    p_package_slug text,
    p_context_keys text[] default array['generell']
)
returns table (
    prompt_id uuid,
    prompt_slug text,
    icon_key text,
    image_key text,
    color_theme text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text,
    sort_order integer,
    step_title text,
    step_intro text,
    is_required boolean
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cp.id as prompt_id,
        cp.slug as prompt_slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(matched.example_input, fallback.example_input) as example_input,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label,
        coalesce(matched.tone_hint, fallback.tone_hint) as tone_hint,
        cpi.sort_order,
        cpi.step_title,
        cpi.step_intro,
        cpi.is_required
    from public.catalog_packages cpkg
    join public.catalog_package_items cpi on cpi.package_id = cpkg.id
    join public.catalog_prompts cp on cp.id = cpi.prompt_id
    left join lateral (
        select v.*
          from public.catalog_prompt_variants v
         where v.prompt_id = cp.id
           and v.context_key = any(p_context_keys)
         order by array_position(p_context_keys, v.context_key)
         limit 1
    ) matched on true
    left join public.catalog_prompt_variants fallback
      on fallback.prompt_id = cp.id
     and fallback.context_key = 'generell'
    where cpkg.status = 'published'
      and cpkg.slug = p_package_slug
      and cp.status = 'published'
    order by cpi.sort_order;
$$;

revoke all on function public.list_published_package_prompts(text, text[]) from public;
grant execute on function public.list_published_package_prompts(text, text[]) to anon, authenticated;
```

- [ ] **Step 7: Kör verifieringskommandon**

Run:

```powershell
rg -n "text\[\]" supabase/migrations/20260725100000_catalog_read_context_arrays.sql
```

Expected: träffar i alla fem `create or replace function`-signaturer och motsvarande `revoke`/`grant`-rader.

Run:

```powershell
rg -n "drop function if exists public\.(list_published_prompts|get_published_prompt|list_published_packages|get_published_package|list_published_package_prompts)" supabase/migrations/20260725100000_catalog_read_context_arrays.sql
```

Expected: fem träffar, en per gammal funktion.

- [ ] **Step 8: Commit**

```powershell
git add supabase/migrations/20260725100000_catalog_read_context_arrays.sql supabase/tests/verify_catalog_core.sql
git commit -m "feat(db): support combinable context profiles in catalog read RPCs"
```

---

### Task 2: `mcp-server/server/catalog.py` — context_keys-lista

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/mcp-server/server/catalog.py`

**Interfaces:**
- Consumes: RPC:erna från Task 1 (`p_context_keys text[]`).
- Produces:
  - `list_published_prompts(context_keys: list[str] = ["generell"]) -> list[dict[str, Any]]`
  - `get_published_prompt(slug: str, context_keys: list[str] = ["generell"]) -> list[dict[str, Any]]` (byter från enskild dict/None till lista — anropare i Task 3 måste uppdateras)
  - `list_published_packages(context_keys: list[str] = ["generell"], package_type: str | None = None) -> list[dict[str, Any]]`
  - `get_published_package(slug: str, context_keys: list[str] = ["generell"]) -> list[dict[str, Any]]`
  - `list_published_package_prompts(package_slug: str, context_keys: list[str] = ["generell"]) -> list[dict[str, Any]]`

- [ ] **Step 1: Uppdatera samtliga funktionssignaturer och payloads**

Ersätt hela innehållet i `catalog.py` från och med `list_published_prompts` (rad 53) till filslut med:

```python
def list_published_prompts(context_keys: list[str] | None = None) -> list[dict[str, Any]]:
    return _call_rpc(
        "list_published_prompts",
        {"p_context_keys": context_keys or ["generell"]},
    )


def get_published_prompt(
    slug: str, context_keys: list[str] | None = None
) -> list[dict[str, Any]]:
    return _call_rpc(
        "get_published_prompt",
        {"p_slug": slug, "p_context_keys": context_keys or ["generell"]},
    )


def list_published_packages(
    context_keys: list[str] | None = None, package_type: str | None = None
) -> list[dict[str, Any]]:
    return _call_rpc(
        "list_published_packages",
        {
            "p_context_keys": context_keys or ["generell"],
            "p_package_type": package_type,
        },
    )


def get_published_package(
    slug: str, context_keys: list[str] | None = None
) -> list[dict[str, Any]]:
    return _call_rpc(
        "get_published_package",
        {"p_slug": slug, "p_context_keys": context_keys or ["generell"]},
    )


def list_published_package_prompts(
    package_slug: str, context_keys: list[str] | None = None
) -> list[dict[str, Any]]:
    return _call_rpc(
        "list_published_package_prompts",
        {
            "p_package_slug": package_slug,
            "p_context_keys": context_keys or ["generell"],
        },
    )
```

`get_published_prompt`/`get_published_package` tar inte längre `rows[0] if rows else None` — de returnerar hela listan av matchande varianter direkt, så Task 3 kan bygga en varianter-lista till MCP-klienten.

- [ ] **Step 2: Verifiera att filen kompilerar**

Run:

```powershell
python -m py_compile mcp-server/server/catalog.py
```

Expected: ingen output.

- [ ] **Step 3: Verifiera att inga `context_key=` (singular) anrop kvarstår**

Run:

```powershell
rg -n "context_key=" mcp-server/server/catalog.py
```

Expected: inga träffar (allt ska heta `context_keys`).

- [ ] **Step 4: Commit**

```powershell
git add mcp-server/server/catalog.py
git commit -m "feat(mcp): read catalog with combinable context_keys"
```

---

### Task 3: `mcp-server/server/mcp_server.py` — verktyg tar context_keys-lista

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/mcp-server/server/mcp_server.py:125-187`

**Interfaces:**
- Consumes: `_catalog.list_published_prompts/get_published_prompt/list_published_packages/get_published_package/list_published_package_prompts` från Task 2 (alla tar `context_keys: list[str]`, `get_published_prompt`/`get_published_package` returnerar listor).
- Produces: MCP-tools `list_prompts`, `get_prompt`, `list_packages`, `get_package`, `list_package_prompts` med `context_keys: list[str] = ["generell"]`-parameter.

- [ ] **Step 1: Ersätt de fem `@mcp.tool()`-funktionerna**

Ersätt block `mcp_server.py:125-187` med:

```python
@mcp.tool()
def list_prompts(context_keys: list[str] | None = None) -> dict[str, Any]:
    """List all published catalog prompts. Pass one or more context_keys
    (e.g. ["kommun", "skola"]) to combine profiles; each prompt appears once,
    using the first matching profile's copy, falling back to 'generell'."""
    try:
        return {
            "prompts": _catalog.list_published_prompts(context_keys=context_keys)
        }
    except _catalog.CatalogNotConfigured as exc:
        return {"error": str(exc), "prompts": []}


@mcp.tool()
def get_prompt(slug: str, context_keys: list[str] | None = None) -> dict[str, Any]:
    """Get one published catalog prompt by slug. Returns one entry per
    matching context_key (in the order passed) plus a guaranteed 'generell'
    entry, so a caller combining profiles sees every matching variant."""
    try:
        variants = _catalog.get_published_prompt(slug, context_keys=context_keys)
    except _catalog.CatalogNotConfigured as exc:
        return {"error": str(exc)}
    if not variants:
        return {"error": f"Ingen publicerad prompt hittades med slug '{slug}'."}
    return {"variants": variants}


@mcp.tool()
def list_packages(
    context_keys: list[str] | None = None, package_type: str | None = None
) -> dict[str, Any]:
    """List all published catalog packages/workflows, combining profiles the
    same way as list_prompts."""
    try:
        return {
            "packages": _catalog.list_published_packages(
                context_keys=context_keys, package_type=package_type
            )
        }
    except _catalog.CatalogNotConfigured as exc:
        return {"error": str(exc), "packages": []}


@mcp.tool()
def get_package(slug: str, context_keys: list[str] | None = None) -> dict[str, Any]:
    """Get one published catalog package by slug. Returns one entry per
    matching context_key plus a guaranteed 'generell' entry."""
    try:
        variants = _catalog.get_published_package(slug, context_keys=context_keys)
    except _catalog.CatalogNotConfigured as exc:
        return {"error": str(exc)}
    if not variants:
        return {"error": f"Inget publicerat paket hittades med slug '{slug}'."}
    return {"variants": variants}


@mcp.tool()
def list_package_prompts(
    package_slug: str, context_keys: list[str] | None = None
) -> dict[str, Any]:
    """List the published prompts belonging to one published package, in
    sort order, combining profiles the same way as list_prompts."""
    try:
        return {
            "prompts": _catalog.list_published_package_prompts(
                package_slug, context_keys=context_keys
            )
        }
    except _catalog.CatalogNotConfigured as exc:
        return {"error": str(exc), "prompts": []}
```

- [ ] **Step 2: Verifiera att filen kompilerar**

Run:

```powershell
python -m py_compile mcp-server/server/mcp_server.py
```

Expected: ingen output.

- [ ] **Step 3: Verifiera att `context_key=` (singular) inte kvarstår i verktygen**

Run:

```powershell
rg -n "def (list_prompts|get_prompt|list_packages|get_package|list_package_prompts)" -A 3 mcp-server/server/mcp_server.py
```

Expected: alla fem signaturer visar `context_keys`, ingen visar `context_key:` (singular).

- [ ] **Step 4: Commit**

```powershell
git add mcp-server/server/mcp_server.py
git commit -m "feat(mcp): expose combinable context_keys on catalog tools"
```

---

### Task 4: Frontend — Supabase REST-hjälpare och profil-lagring i `script.js`

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/index.html` (nytt inline `<script>` i `<head>`, före laddningen av `script.js`)
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js` (nytt block, placeras direkt efter rad 46, före `// Step 19: Dynamic JavaScript loading from prompts.json`)

**Interfaces:**
- Consumes: inget (första byggstenen i katalogsektionen).
- Produces:
  - `window.SUPABASE_URL` / `window.SUPABASE_ANON_KEY` (satta i `index.html`, inte i `script.js`)
  - `CATALOG_CONTEXT_PROFILES` (const array av `{ key, label }`)
  - `getCatalogProfileSelection(): string[]`
  - `saveCatalogProfileSelection(keys: string[]): void`
  - `callCatalogRpc(functionName: string, payload: object): Promise<any>`

**Bakgrund till detta steg:** `script.js` körs oprocessat (ingen `import.meta.env`), och de riktiga Supabase-värdena finns bara i `.env.local`/CI-secrets (`VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`), aldrig incheckade. Vite ersätter `%VITE_XXX%`-platshållare i `index.html` automatiskt (både i `npm run web:dev` och i build), så genom att sätta `window.SUPABASE_URL`/`window.SUPABASE_ANON_KEY` i ett inline-script i `index.html` slipper `script.js` hårdkodade värden helt — samma mönster som `src/supabaseClient.js` redan använder, fast utan bundling.

- [ ] **Step 1: Injicera Supabase-värden i `index.html`**

Lägg till i `<head>` i `index.html`, före `<script src="script.js">`-taggen (sök upp den exakta platsen i filen):

```html
<script>
    window.SUPABASE_URL = '%VITE_SUPABASE_URL%';
    window.SUPABASE_ANON_KEY = '%VITE_SUPABASE_PUBLISHABLE_KEY%';
</script>
```

- [ ] **Step 2: Lägg till konstanterna och profil-lagring i `script.js`**

Infoga i `script.js` efter rad 46:

```javascript
// Kontextprofiler: kombinerbar katalogläsning mot Supabase (fristående från prompts.json)
const SUPABASE_CATALOG_URL = window.SUPABASE_URL;
const SUPABASE_CATALOG_ANON_KEY = window.SUPABASE_ANON_KEY;
const CATALOG_PROFILE_STORAGE_KEY = 'promptbankenContextProfiles';

const CATALOG_CONTEXT_PROFILES = [
    { key: 'kommun', label: 'Kommun' },
    { key: 'skola', label: 'Skola' },
    { key: 'företag', label: 'Företag' },
    { key: 'förening', label: 'Förening' },
    { key: 'privat', label: 'Privat' }
];

function getCatalogProfileSelection() {
    try {
        const stored = JSON.parse(localStorage.getItem(CATALOG_PROFILE_STORAGE_KEY) || '[]');
        return Array.isArray(stored) ? stored : [];
    } catch (error) {
        return [];
    }
}

function saveCatalogProfileSelection(keys) {
    localStorage.setItem(CATALOG_PROFILE_STORAGE_KEY, JSON.stringify(keys));
}

async function callCatalogRpc(functionName, payload) {
    const response = await fetch(`${SUPABASE_CATALOG_URL}/rest/v1/rpc/${functionName}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_CATALOG_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_CATALOG_ANON_KEY}`
        },
        body: JSON.stringify(payload)
    });

    if (!response.ok) {
        throw new Error(`Kataloganrop ${functionName} misslyckades: ${response.status}`);
    }

    return response.json();
}
```

Not: `SUPABASE_CATALOG_URL`/`SUPABASE_CATALOG_ANON_KEY` läser samma publika Supabase-projekt-URL och publishable/anon-nyckel som redan exponeras till webbläsaren via `VITE_SUPABASE_URL`/`VITE_SUPABASE_PUBLISHABLE_KEY` för admin/auth-sidorna (se `src/supabaseClient.js`), men via `window.SUPABASE_URL`/`window.SUPABASE_ANON_KEY` som Step 1 satte i `index.html` — ingen hemlighet hårdkodas i `script.js` självt, och RLS styr fortfarande åtkomsten.

- [ ] **Step 3: Lägg till en regressionscheck i stil med befintliga**

Infoga direkt efter `performRegressionTests()`-anropet (nuvarande rad 46):

```javascript
        // Kontextprofil-regressionscheck
        function testCatalogProfileStorage() {
            const testKeys = ['kommun', 'skola'];
            saveCatalogProfileSelection(testKeys);
            const roundTripped = getCatalogProfileSelection();
            localStorage.removeItem(CATALOG_PROFILE_STORAGE_KEY);
            return JSON.stringify(roundTripped) === JSON.stringify(testKeys);
        }

        console.log('Catalog Profile Storage Test:', testCatalogProfileStorage() ? 'Passed' : 'Failed');
```

- [ ] **Step 4: Kör verifiering**

Run:

```powershell
npm run web:dev
```

Öppna sidan i webbläsaren, öppna dev-konsolen, och kontrollera:

Expected: konsolraden `Catalog Profile Storage Test: Passed` visas bland de övriga regressionsraderna. Kontrollera även att `window.SUPABASE_URL` i konsolen ger en riktig `https://...supabase.co`-URL (inte den bokstavliga strängen `%VITE_SUPABASE_URL%`) — det bekräftar att Vite ersatte platshållaren.

- [ ] **Step 5: Commit**

```powershell
git add index.html script.js
git commit -m "feat(web): add catalog RPC helper and local context profile storage"
```

---

### Task 5: Frontend — katalogsektionens markup och styling

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/promptbanken.html`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/style.css`

**Viktigt (upptäckt under Task 4):** `index.html` är en fristående landningssida (marknadsföring, laddar inte `script.js`). Den faktiska prompt-bläddringsappen — inklusive `#prompt-grid` och laddningen av `script.js` — ligger i `promptbanken.html`. All markup i denna task ska in där, inte i `index.html`.

**Interfaces:**
- Consumes: `CATALOG_CONTEXT_PROFILES` (Task 4) för att fylla checkbox-listan i JS senare (Task 6).
- Produces DOM-element som Task 6/7 binder till:
  - `#catalog-profile-filters` (container för profil-checkboxar)
  - `#catalog-prompt-grid` (kortgrid för publicerade katalogprompts)
  - `#catalog-package-grid` (kortgrid för publicerade paket)
  - `#catalog-prompt-detail` (dold detaljpanel med flikar)

- [ ] **Step 1: Lägg till sektionen i `promptbanken.html`**

Infoga en ny, fristående `<section>` direkt efter huvudinnehållets `prompt-grid`-sektion (sök efter `id="prompt-grid"` i `promptbanken.html` för exakt placering):

```html
<section class="catalog-section" id="catalog-section">
    <div class="catalog-section-heading">
        <h2>Öppen katalog</h2>
        <p>Publicerade prompts och paket från Promptbanken, filtrerat på dina kontextprofiler.</p>
    </div>

    <div class="catalog-profile-filters" id="catalog-profile-filters" role="group" aria-label="Kontextprofiler"></div>

    <h3>Prompts</h3>
    <div class="catalog-grid" id="catalog-prompt-grid"></div>

    <h3>Paket och arbetssätt</h3>
    <div class="catalog-grid" id="catalog-package-grid"></div>

    <div class="catalog-prompt-detail" id="catalog-prompt-detail" hidden>
        <button type="button" class="catalog-detail-close" id="catalog-detail-close" aria-label="Stäng">×</button>
        <div class="catalog-detail-tabs" id="catalog-detail-tabs"></div>
        <div class="catalog-detail-body" id="catalog-detail-body"></div>
    </div>
</section>
```

- [ ] **Step 2: Lägg till grundstyling i `style.css`**

Lägg till i slutet av `style.css`:

```css
.catalog-section {
    margin-top: 3rem;
    padding-top: 2rem;
    border-top: 1px solid var(--border-color, #e2e2e2);
}

.catalog-profile-filters {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin: 1rem 0;
}

.catalog-profile-filters label {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    padding: 0.35rem 0.75rem;
    border: 1px solid var(--border-color, #ccc);
    border-radius: 999px;
    cursor: pointer;
}

.catalog-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
    gap: 1rem;
    margin-bottom: 1.5rem;
}

.catalog-prompt-detail {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
}

.catalog-detail-tabs {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1rem;
}

.catalog-detail-tabs button.active {
    font-weight: 600;
    text-decoration: underline;
}
```

- [ ] **Step 3: Kör verifiering**

Run:

```powershell
rg -n "catalog-prompt-grid|catalog-package-grid|catalog-profile-filters|catalog-prompt-detail" promptbanken.html style.css
```

Expected: träffar i båda filerna för alla fyra selektorer.

- [ ] **Step 4: Commit**

```powershell
git add promptbanken.html style.css
git commit -m "feat(web): add markup and styling for open catalog section"
```

---

### Task 6: Frontend — profilväljare och katalogprompt-lista

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`

**Interfaces:**
- Consumes:
  - `CATALOG_CONTEXT_PROFILES`, `getCatalogProfileSelection`, `saveCatalogProfileSelection`, `callCatalogRpc` (Task 4)
  - DOM: `#catalog-profile-filters`, `#catalog-prompt-grid` (Task 5)
- Produces:
  - `renderCatalogProfileFilters(): void`
  - `loadCatalogPrompts(): Promise<void>`
  - `createCatalogPromptCard(prompt: object): HTMLElement`

- [ ] **Step 1: Implementera profilväljaren**

Lägg till i `script.js`, direkt efter `callCatalogRpc` (Task 4):

```javascript
function renderCatalogProfileFilters() {
    const container = document.getElementById('catalog-profile-filters');
    if (!container) return;

    const selected = new Set(getCatalogProfileSelection());

    container.innerHTML = CATALOG_CONTEXT_PROFILES.map(({ key, label }) => `
        <label>
            <input type="checkbox" data-catalog-profile="${key}" ${selected.has(key) ? 'checked' : ''}>
            ${label}
        </label>
    `).join('');

    container.querySelectorAll('input[data-catalog-profile]').forEach((checkbox) => {
        checkbox.addEventListener('change', () => {
            const nextSelection = Array.from(
                container.querySelectorAll('input[data-catalog-profile]:checked')
            ).map((input) => input.dataset.catalogProfile);
            saveCatalogProfileSelection(nextSelection);
            loadCatalogPrompts();
            loadCatalogPackages();
        });
    });
}

function getActiveContextKeys() {
    const selection = getCatalogProfileSelection();
    return selection.length ? selection : ['generell'];
}
```

- [ ] **Step 2: Implementera kortrendering och listladdning**

```javascript
function createCatalogPromptCard(prompt) {
    const card = document.createElement('div');
    card.className = 'catalog-card';
    card.dataset.catalogPromptSlug = prompt.slug;
    card.innerHTML = `
        <h4>${prompt.title}</h4>
        <p>${prompt.summary}</p>
    `;
    card.addEventListener('click', () => openCatalogPromptDetail(prompt.slug));
    return card;
}

async function loadCatalogPrompts() {
    const grid = document.getElementById('catalog-prompt-grid');
    if (!grid) return;

    try {
        const prompts = await callCatalogRpc('list_published_prompts', {
            p_context_keys: getActiveContextKeys()
        });
        grid.innerHTML = '';
        prompts.forEach((prompt) => grid.appendChild(createCatalogPromptCard(prompt)));
    } catch (error) {
        console.error('Kunde inte ladda katalogprompts:', error);
        grid.innerHTML = '<div class="error-message">⚠️ Kunde inte ladda katalogprompts.</div>';
    }
}
```

- [ ] **Step 3: Koppla in laddningen i sidans init-flöde**

Sök upp anropet till `loadPrompts()` i `script.js` (nära filens botten, där sidan initieras) och lägg till direkt efter:

```javascript
renderCatalogProfileFilters();
loadCatalogPrompts();
```

- [ ] **Step 4: Kör verifiering**

Run:

```powershell
npm run web:dev
```

I webbläsaren: bocka i "Kommun" i profilfiltret, kontrollera i Network-fliken att ett `POST` till `.../rpc/list_published_prompts` skickas med body `{"p_context_keys":["kommun"]}`.

Expected: anropet skickas med rätt payload och kortgriden uppdateras (eller visar felmeddelande om Supabase-katalogen saknar publicerat innehåll ännu — det är förväntat i tomma miljöer).

- [ ] **Step 5: Commit**

```powershell
git add script.js
git commit -m "feat(web): render combinable context profile filter and catalog prompt list"
```

---

### Task 7: Frontend — katalogprompt-detalj med variantflikar

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`

**Interfaces:**
- Consumes: `callCatalogRpc`, `getActiveContextKeys` (Task 4/6), DOM: `#catalog-prompt-detail`, `#catalog-detail-tabs`, `#catalog-detail-body`, `#catalog-detail-close` (Task 5).
- Produces: `openCatalogPromptDetail(slug: string): Promise<void>`, `renderCatalogDetailVariant(variant: object): void`.

- [ ] **Step 1: Implementera detaljöppning med variantflikar**

Lägg till i `script.js`, efter `loadCatalogPrompts`:

```javascript
let catalogDetailVariants = [];

function renderCatalogDetailVariant(variant) {
    const body = document.getElementById('catalog-detail-body');
    if (!body) return;

    body.innerHTML = `
        <h3>${variant.title}</h3>
        <p>${variant.summary}</p>
        <pre class="catalog-detail-prompt-text">${variant.prompt_text}</pre>
    `;
}

async function openCatalogPromptDetail(slug) {
    const panel = document.getElementById('catalog-prompt-detail');
    const tabsContainer = document.getElementById('catalog-detail-tabs');
    if (!panel || !tabsContainer) return;

    try {
        catalogDetailVariants = await callCatalogRpc('get_published_prompt', {
            p_slug: slug,
            p_context_keys: getActiveContextKeys()
        });
    } catch (error) {
        console.error('Kunde inte ladda promptdetaljer:', error);
        return;
    }

    if (!catalogDetailVariants.length) return;

    const profileLabelByKey = new Map(CATALOG_CONTEXT_PROFILES.map(({ key, label }) => [key, label]));

    tabsContainer.innerHTML = catalogDetailVariants.map((variant, index) => `
        <button type="button" data-catalog-tab-index="${index}" class="${index === 0 ? 'active' : ''}">
            ${profileLabelByKey.get(variant.context_key) || 'Generell'}
        </button>
    `).join('');

    tabsContainer.querySelectorAll('button[data-catalog-tab-index]').forEach((button) => {
        button.addEventListener('click', () => {
            tabsContainer.querySelectorAll('button').forEach((btn) => btn.classList.remove('active'));
            button.classList.add('active');
            renderCatalogDetailVariant(catalogDetailVariants[Number(button.dataset.catalogTabIndex)]);
        });
    });

    renderCatalogDetailVariant(catalogDetailVariants[0]);
    panel.hidden = false;
}

document.getElementById('catalog-detail-close')?.addEventListener('click', () => {
    document.getElementById('catalog-prompt-detail').hidden = true;
});
```

Not: flikraden renderas bara om `catalogDetailVariants.length > 1` uppfattas visuellt som flikval — vid en enda rad (bara `generell`) visas ändå en flik ("Generell"), vilket är korrekt eftersom UI:t inte behöver dölja enskilda flikar för detta första steg (ingen extra logik krävs eftersom en synlig flik med en variant är harmlös).

- [ ] **Step 2: Kör verifiering**

Run:

```powershell
npm run web:dev
```

I webbläsaren: klicka på ett katalogprompt-kort med minst två profiler valda (t.ex. Kommun + Skola) mot en Supabase-instans som har en prompt med båda variant-typerna, och kontrollera att två flikar visas och att innehållet byts vid klick.

Expected: flikbyte uppdaterar `#catalog-detail-body` utan sidladdning.

- [ ] **Step 3: Commit**

```powershell
git add script.js
git commit -m "feat(web): show matching context variants as tabs in catalog prompt detail"
```

---

### Task 8: Frontend — katalogpaket-lista

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/script.js`

**Interfaces:**
- Consumes: `callCatalogRpc`, `getActiveContextKeys` (Task 4/6), DOM: `#catalog-package-grid` (Task 5).
- Produces: `createCatalogPackageCard(pkg: object): HTMLElement`, `loadCatalogPackages(): Promise<void>`.

- [ ] **Step 1: Implementera paketkort och listladdning**

Lägg till i `script.js`, efter `openCatalogPromptDetail`-blocket:

```javascript
function createCatalogPackageCard(pkg) {
    const card = document.createElement('div');
    card.className = 'catalog-card';
    card.dataset.catalogPackageSlug = pkg.slug;
    card.innerHTML = `
        <h4>${pkg.title}</h4>
        <p>${pkg.summary}</p>
        <span class="catalog-package-type">${pkg.package_type === 'workflow' ? 'Arbetssätt' : 'Samling'}</span>
    `;
    return card;
}

async function loadCatalogPackages() {
    const grid = document.getElementById('catalog-package-grid');
    if (!grid) return;

    try {
        const packages = await callCatalogRpc('list_published_packages', {
            p_context_keys: getActiveContextKeys(),
            p_package_type: null
        });
        grid.innerHTML = '';
        packages.forEach((pkg) => grid.appendChild(createCatalogPackageCard(pkg)));
    } catch (error) {
        console.error('Kunde inte ladda katalogpaket:', error);
        grid.innerHTML = '<div class="error-message">⚠️ Kunde inte ladda katalogpaket.</div>';
    }
}
```

- [ ] **Step 2: Koppla in laddningen i init-flödet**

I samma init-block som Task 6 Steg 3 (`renderCatalogProfileFilters(); loadCatalogPrompts();`), lägg till:

```javascript
loadCatalogPackages();
```

- [ ] **Step 3: Kör verifiering**

Run:

```powershell
rg -n "loadCatalogPackages|createCatalogPackageCard" script.js
```

Expected: träffar för både definition och init-anrop.

Run:

```powershell
npm run web:dev
```

Expected: paketgriden fylls (eller visar tomt/felmeddelande om inga paket är publicerade ännu), och byte av profilfilter uppdaterar även paketlistan.

- [ ] **Step 4: Commit**

```powershell
git add script.js
git commit -m "feat(web): list published catalog packages filtered by context profiles"
```

## Self-Review

- **Spec coverage:** Task 1 täcker read-RPC-arraysignaturer, dedup-listning och multi-variant-detalj (spec-beslut 1–4). Task 2–3 täcker MCP-parameterbyte (spec-beslut 6). Task 4 täcker lokal profil-lagring (spec-beslut 5). Task 5–8 täcker frontend-profilval, listdedup och variantflikar (spec-beslut 4–5, "Frontend-gränssnitt"-avsnittet). Utanför scope (kontobunden lagring, textsammanslagning, rankingalgoritm) är medvetet uteslutet, i linje med specen.
- **Placeholder scan:** Inga `TBD`/`TODO`. `SUPABASE_CATALOG_URL`/`SUPABASE_CATALOG_ANON_KEY`-platshållarvärdena i Task 4 är en engångsinsättning av riktiga projektvärden (samma som `.env`/Supabase-dashboarden), inte en kvarlämnad platshållare i logiken.
- **Type consistency:** `context_keys`/`p_context_keys` används konsekvent som namn genom DB (Task 1), Python (Task 2–3) och JS (Task 4–8). `get_published_prompt`/`get_published_package` returnerar konsekvent en lista av varianter (inte en enskild dict) från Task 2 och framåt — Task 3 och Task 7 bygger båda på den listformen.
