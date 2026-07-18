# Plan-/kvotsynk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Synka plan-/kvotinformation mellan DB, MCP-server och Valvet-UI: utöka `get_plan_usage` med Valvet-fält, låt `vault.js` läsa RPC:n i stället för hårdkodade konstanter, och rätta stale "Pro-only"-texter för `update_my_item`/`archive_my_item`.

**Architecture:** En migration i `promptbanken`-repot (som äger allt schema) droppar och återskapar `public.get_plan_usage(uuid)` med sex nya kolumner som speglar befintliga triggrar/RPC:ers räknelogik exakt. Valvets `vault.js` hämtar RPC:n vid bootstrap, cachar i `state.usage` och faller tillbaka till dagens konstanter vid fel (gränser upprätthålls ändå server-side). Textfixar i tre repos — ingen gating-logik ändras någonstans.

**Tech Stack:** Postgres/plpgsql (Supabase), supabase-js v2, vanilla JS ES modules, Python (endast docstrings/beskrivningstext).

**Spec:** `docs/superpowers/specs/2026-07-18-plan-usage-sync-design.md` (promptbanken-repot)

## Global Constraints

- Tre repos berörs; committa i det repo filen ligger i. Sökvägar nedan är alltid prefixade med reponamn.
  - `promptbanken` = `C:\Users\petwen\OneDrive - Höglandsförbundet\Projekt\promptbanken`
  - `valvet_promptbanken` = `C:\Users\petwen\OneDrive - Höglandsförbundet\Projekt\valvet_promptbanken`
  - `mcp_promptbanken` = `C:\Users\petwen\OneDrive - Höglandsförbundet\Projekt\mcp_promptbanken\mcp_promptbanken` (OBS: nästlad mapp)
- Faktaunderlag för texterna: sedan migration `20260718090000_valvet_free_update_archive_via_mcp.sql` (commit `495f547`) får Free-plan köra `update_my_item`/`archive_my_item` via MCP. `save_my_item` är Free 5/kalendermånad, Pro obegränsat. Detta får INTE omformuleras till något annat.
- Ingen gating-logik ändras — bara SQL-läs-RPC:n, klient-UI och texter.
- `get_plan_usage`:s befintliga nio kolumner behåller namn, ordning och semantik exakt (admin.js läser dem).
- Svenska i alla användarvänliga texter; samma ton som befintlig copy.
- Inga automattest-ramverk finns i repona: SQL verifieras med manuellt körbara verify-skript (mönster: `supabase/tests/verify_copy_catalog_item_to_valvet.sql`), UI verifieras manuellt i browser.

---

### Task 1: Migration — utöka `get_plan_usage` med Valvet-fält

**Files:**
- Create: `promptbanken/supabase/migrations/20260718120000_plan_usage_valvet_fields.sql`
- Create: `promptbanken/supabase/tests/verify_plan_usage_valvet_fields.sql`

**Interfaces:**
- Consumes: befintliga `public.get_plan_usage(uuid)` (definierad i `20260707120000_fix_plan_usage_addon_workspaces.sql`), `app_private.has_active_pro_entitlement(uuid)`, tabellerna `content_items`, `api_keys`, `app_private.mcp_write_attempts`, `app_private.valvet_catalog_copies`.
- Produces: `public.get_plan_usage(p_workspace_id uuid)` med 15 kolumner — de befintliga nio plus `valvet_items_used integer, valvet_items_max integer, monthly_saves_used integer, monthly_saves_max integer, catalog_copies_used integer, catalog_copies_max integer`. `null` i en `*_max`-kolumn betyder obegränsat. Task 2 (vault.js) läser dessa fältnamn exakt.

- [ ] **Step 1: Skriv verify-skriptet (testet först)**

Skapa `promptbanken/supabase/tests/verify_plan_usage_valvet_fields.sql`:

```sql
-- supabase/tests/verify_plan_usage_valvet_fields.sql
-- Manuellt körbart mot staging. get_plan_usage är auth.uid()-baserad --
-- kör varje block via SQL-editorns role-impersonation som respektive
-- testanvändare (samma metod som verify_copy_catalog_item_to_valvet.sql),
-- inte som postgres-superuser.
--
-- Fixturer: samma Free- och Pro-personlig-workspace-användare som i
-- verify_valvet_rpcs.sql. Byt in respektive workspace-id nedan.

-- 1. Som Free-användare med känt antal aktiva Valvet-items, X sparningar
--    via MCP denna månad och Y katalogkopior denna månad:
select * from public.get_plan_usage('<free-workspace-id>');
-- Förväntat (FÖRE migrationen): 9 kolumner, inga valvet_-fält.
-- Förväntat (EFTER migrationen): 15 kolumner. De första nio oförändrade
-- (max_prompts=3, max_mcp_keys=1 för Free). Dessutom:
--   valvet_items_used   = antal content_items med module='valvet',
--                         owner = workspace-ägaren, status <> 'archived'
--   valvet_items_max    = 50
--   monthly_saves_used  = antal rader i app_private.mcp_write_attempts med
--                         tool='save_my_item', outcome='success',
--                         created_at >= date_trunc('month', now())
--   monthly_saves_max   = 5
--   catalog_copies_used = antal rader i app_private.valvet_catalog_copies
--                         denna kalendermånad
--   catalog_copies_max  = 5

-- 2. Som Pro-användare:
select * from public.get_plan_usage('<pro-workspace-id>');
-- Förväntat: valvet_items_max=1000, monthly_saves_max=null,
-- catalog_copies_max=null (obegränsat). used-kolumnerna räknas ändå.

-- 3. Korsreferens mot befintliga kvot-RPC:er (samma användare som steg 1):
select * from public.valvet_catalog_copy_quota();
-- Förväntat: used = catalog_copies_used från steg 1, monthly_limit = 5.

-- 4. Som medlem i en delad addon-yta (organization utan licens):
select * from public.get_plan_usage('<addon-workspace-id>');
-- Förväntat: de nio första kolumnerna som före migrationen; alla sex
-- valvet-/kvotfält är 0 respektive null (Valvet är personligt).

-- 5. Admin-regression: logga in i admin.html som valfri användare och
-- kontrollera att planpanelen (Din plan/användning) renderar som förut.
```

- [ ] **Step 2: Kör steg 1-anropet FÖRE migrationen — verifiera 9 kolumner**

Kör via Supabase MCP-verktyget `execute_sql` (eller SQL-editorn):
```sql
select w.id from public.workspaces w where w.type = 'personal' limit 1;
select * from public.get_plan_usage('<id-från-raden-ovan>');
```
(Anropet måste ske som en autentiserad medlem av workspacet eller platform_owner — se verify-skriptets impersonation-notis.)
Expected: resultatet har exakt 9 kolumner (`has_license` … `used_workspaces`), inga `valvet_`-kolumner. Detta är "failing test"-läget.

- [ ] **Step 3: Skriv migrationen**

Skapa `promptbanken/supabase/migrations/20260718120000_plan_usage_valvet_fields.sql`:

```sql
-- 20260718120000_plan_usage_valvet_fields.sql
-- get_plan_usage exponerar inga Valvet-tal, så Valvets frontend hårdkodar
-- gränserna (50/1000 items, 1/3 nycklar) och kan glida isär från
-- triggrarna. Utökar RPC:n med sex kolumner som speglar den faktiska
-- räknelogiken i enforce_vault_item_limit (20260716101000),
-- save_my_item_for_key (20260717090000) och valvet_catalog_copy_quota
-- (20260718100000). null i en *_max-kolumn = obegränsat.
--
-- Postgres tillåter inte ändrad returtyp via create or replace ->
-- drop + recreate. Grants återställs identiskt nedan. De nio befintliga
-- kolumnerna är oförändrade (admin.js läser dem via namn).

drop function public.get_plan_usage(uuid);

create function public.get_plan_usage(p_workspace_id uuid)
returns table(
    has_license      boolean,
    max_prompts      integer,
    max_mcp_keys     integer,
    max_members      integer,
    max_workspaces   integer,
    used_prompts     integer,
    used_mcp_keys    integer,
    used_members     integer,
    used_workspaces  integer,
    valvet_items_used   integer,
    valvet_items_max    integer,
    monthly_saves_used  integer,
    monthly_saves_max   integer,
    catalog_copies_used integer,
    catalog_copies_max  integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_workspace public.workspaces%rowtype;
    v_license   public.pro_licenses%rowtype;
    v_addon     public.shared_workspace_addons%rowtype;
    v_ids       uuid[];
    v_is_pro    boolean;
begin
    select * into v_workspace from public.workspaces where id = p_workspace_id;
    if not found then
        raise exception 'Workspace saknas.';
    end if;

    if not exists (
        select 1 from public.profiles
         where user_id = (select auth.uid()) and workspace_id = p_workspace_id
    ) and not app_private.current_user_is_platform_owner() then
        raise exception 'Åtkomst nekad.';
    end if;

    -- Delad addon-yta: organisation, ingen licens, gränser i
    -- shared_workspace_addons. Valvet är personligt -> 0/null.
    if v_workspace.type = 'organization' and v_workspace.license_id is null then
        select * into v_addon from public.shared_workspace_addons where workspace_id = p_workspace_id;

        return query
        select
            false,
            coalesce(v_addon.max_prompts, 200),
            0,  -- delade addon-ytor har inga egna MCP-nycklar (enforce_mcp_key_limit)
            coalesce(v_addon.max_members, 5),
            1,
            (select count(*)::int from public.content_items
              where workspace_id = p_workspace_id and type = 'prompt' and status <> 'archived'),
            0,
            (select count(*)::int from public.profiles where workspace_id = p_workspace_id),
            1,
            0, null::integer, 0, null::integer, 0, null::integer;
        return;
    end if;

    if v_workspace.type <> 'organization' or v_workspace.license_id is null then
        v_is_pro := app_private.has_active_pro_entitlement(v_workspace.owner_user_id);

        return query
        select
            false,
            v_workspace.max_prompts,
            (case when v_workspace.plan = 'pro' then 3 else 1 end),
            1,
            1,
            (select count(*)::int from public.content_items
              where workspace_id = p_workspace_id and type = 'prompt' and owner_user_id = (select auth.uid()) and status <> 'archived'),
            (select count(*)::int from public.api_keys
              where workspace_id = p_workspace_id and scopes @> array['mcp']::text[] and revoked_at is null),
            1,
            1,
            -- Valvet-items: speglar enforce_vault_item_limit (räknas per
            -- workspace-ägare, inte anroparen -- platform_owner kan inspektera).
            (select count(*)::int from public.content_items ci
              where ci.workspace_id = p_workspace_id
                and ci.module = 'valvet'
                and ci.owner_user_id = v_workspace.owner_user_id
                and ci.status <> 'archived'),
            (case when v_workspace.plan = 'free' then 50 else 1000 end),
            -- MCP-sparningar: speglar kvotspärren i save_my_item_for_key.
            (select count(*)::int from app_private.mcp_write_attempts
              where workspace_id = p_workspace_id
                and tool = 'save_my_item'
                and outcome = 'success'
                and created_at >= date_trunc('month', now())),
            (case when v_workspace.plan = 'free' then 5 else null::integer end),
            -- Katalogkopior: speglar valvet_catalog_copy_quota
            -- (Pro-check via entitlement med utgångsdatum, inte rå planflagga).
            (select count(*)::int from app_private.valvet_catalog_copies
              where workspace_id = p_workspace_id
                and created_at >= date_trunc('month', now())),
            (case when v_is_pro then null::integer else 5 end);
        return;
    end if;

    select * into v_license from public.pro_licenses where id = v_workspace.license_id;
    select array_agg(id) into v_ids from public.workspaces w where w.id in (select app_private.license_group_workspace_ids(p_workspace_id));

    return query
    select
        true,
        v_license.max_prompts_total,
        v_license.max_mcp_keys_total,
        v_license.max_members_total,
        v_license.max_workspaces,
        (select count(*)::int from public.content_items
          where workspace_id = any(v_ids) and type = 'prompt' and status <> 'archived'),
        (select count(*)::int from public.api_keys
          where workspace_id = any(v_ids) and scopes @> array['mcp']::text[] and revoked_at is null),
        (select count(*)::int from public.profiles where workspace_id = any(v_ids)),
        (select count(*)::int from public.workspaces where id = any(v_ids)),
        0, null::integer, 0, null::integer, 0, null::integer;
end;
$$;

revoke all on function public.get_plan_usage(uuid) from public;
grant execute on function public.get_plan_usage(uuid) to authenticated;
```

- [ ] **Step 4: Applicera migrationen**

Applicera via Supabase MCP-verktyget `apply_migration` med namnet `plan_usage_valvet_fields` och filens innehåll.
Expected: OK utan fel. (Vid fel om beroende objekt: inget vy-/funktionsberoende på `get_plan_usage` finns — felet är då något annat och ska utredas, inte kringgås.)

- [ ] **Step 5: Kör verify-skriptets steg 1-4 — verifiera 15 kolumner**

Kör samma anrop som Step 2 igen via `execute_sql`.
Expected: 15 kolumner; för ett Free-workspace `valvet_items_max=50`, `monthly_saves_max=5`, `catalog_copies_max=5`; used-värden stämmer mot manuell räkning:
```sql
select count(*) from public.content_items where workspace_id='<id>' and module='valvet' and status <> 'archived';
```
Kör också korsreferensen (verify-steg 3) och addon-fallet (verify-steg 4) om addon-yta finns.

- [ ] **Step 6: Commit (promptbanken-repot)**

```bash
git add supabase/migrations/20260718120000_plan_usage_valvet_fields.sql supabase/tests/verify_plan_usage_valvet_fields.sql
git commit -m "feat: expose Valvet usage/limits in get_plan_usage"
```

---

### Task 2: Valvet-UI läser `get_plan_usage` i stället för konstanter

**Files:**
- Modify: `valvet_promptbanken/src/vault.js` (state, bootstrap, `vaultItemLimit`, `MCP_KEY_LIMITS`/`mcpKeyLimit`, ny `refreshUsage`/`renderUsage`, anrop efter mutationer)
- Modify: `valvet_promptbanken/vault.html` (nytt användningselement i MCP-vyn)

**Interfaces:**
- Consumes: `public.get_plan_usage(p_workspace_id uuid)` från Task 1 — fälten `valvet_items_used`, `valvet_items_max`, `monthly_saves_used`, `monthly_saves_max`, `used_mcp_keys`, `max_mcp_keys`; `null` max = obegränsat. supabase-js returnerar `returns table` som array av radobjekt.
- Produces: `state.usage` (radobjekt eller `null`), `refreshUsage()` (exporterad). Katalogflikens kvotvisning (`valvet_catalog_copy_quota`) lämnas orörd — den har redan egen RPC.

- [ ] **Step 1: Utöka state och bootstrap**

I `valvet_promptbanken/src/vault.js`, ändra state-objektet (rad 4-10):

```js
export const state = {
  session: null,
  user: null,
  workspace: null,
  usage: null,      // senaste get_plan_usage-rad, null = okänd (fallback till konstanter)
  items: [],       // aktiva "Mina insättningar"
  archived: []      // arkiverade
};
```

I `bootstrap()` (efter att `state.workspace = workspace;` satts, rad 103), lägg till före `return true;`:

```js
  await refreshUsage();
```

- [ ] **Step 2: Lägg till refreshUsage/renderUsage**

Lägg in direkt efter `bootstrap()`-funktionen:

```js
export async function refreshUsage() {
  if (!state.workspace) return;
  const { data, error } = await supabase.rpc('get_plan_usage', { p_workspace_id: state.workspace.id });
  if (error) {
    // Gränserna upprätthålls server-side (triggrar/RPC:er) -- vid fel behåller
    // vi senaste kända värden och faller annars tillbaka till konstanterna.
    renderUsage();
    return;
  }
  state.usage = Array.isArray(data) ? (data[0] ?? null) : (data ?? null);
  renderUsage();
}

function renderUsage() {
  const el = document.querySelector('[data-mcp-usage]');
  if (!el) return;
  if (!state.usage) {
    el.textContent = '';
    return;
  }
  const u = state.usage;
  const keys = `${u.used_mcp_keys} av ${u.max_mcp_keys} aktiva MCP-nycklar.`;
  const saves = u.monthly_saves_max === null
    ? 'Obegränsade sparningar via MCP (Pro).'
    : `${u.monthly_saves_used} av ${u.monthly_saves_max} sparningar via MCP denna månad.`;
  const copies = u.catalog_copies_max === null
    ? 'Obegränsade katalogkopior (Pro).'
    : `${u.catalog_copies_used} av ${u.catalog_copies_max} katalogkopior denna månad.`;
  el.textContent = `${keys} ${saves} ${copies}`;
}
```

- [ ] **Step 3: Ersätt konstanterna med RPC-värden (med fallback)**

Ändra `vaultItemLimit()` (rad 52-54) till:

```js
export function vaultItemLimit() {
  return state.usage?.valvet_items_max ?? (state.workspace?.plan === 'free' ? 50 : 1000);
}
```

Ersätt `MCP_KEY_LIMITS`-konstanten och `mcpKeyLimit()` (rad 536-540) med:

```js
function mcpKeyLimit() {
  return state.usage?.max_mcp_keys ?? (state.workspace?.plan === 'pro' ? 3 : 1);
}
```

Uppdatera räknarbadgen i `renderItems()` (rad 186-189) till att föredra RPC-värdet:

```js
  const counter = document.querySelector('[data-item-counter]');
  const limit = vaultItemLimit();
  const used = state.usage?.valvet_items_used ?? state.items.length;
  counter.textContent = `${used} av ${limit} insättningar`;
  counter.classList.toggle('is-limit', used >= limit);
```

- [ ] **Step 4: Uppdatera användningen efter mutationer**

Lägg till `refreshUsage()` efter lyckade mutationer (värden får inte visas fel efter en åtgärd):

- I `saveItem` (rad 268-269): ändra `await loadItems();` till `await Promise.all([loadItems(), refreshUsage()]);`
- I `archiveItem` (rad 479): ändra `await loadItems();` till `await Promise.all([loadItems(), refreshUsage()]);`
- I `restoreItem` (rad 531): ändra `await Promise.all([loadItems(), loadArchive()]);` till `await Promise.all([loadItems(), loadArchive(), refreshUsage()]);`
- I `createMcpKey` (rad 635): ändra `await loadMcpKeys();` till `await Promise.all([loadMcpKeys(), refreshUsage()]);`
- I revoke-hanteraren i `loadMcpKeys` (rad 583): ändra `await loadMcpKeys();` till `await Promise.all([loadMcpKeys(), refreshUsage()]);`
- I `copyToValvet` (rad 372): ändra `await Promise.all([loadItems(), updateCatalogQuota()]);` till `await Promise.all([loadItems(), updateCatalogQuota(), refreshUsage()]);`

- [ ] **Step 5: Lägg till användningselementet i vault.html**

I `valvet_promptbanken/vault.html`, MCP-vyn: direkt efter `<div data-mcp-key-list style="margin-top:1rem;"></div>` (rad 156), lägg till:

```html
        <p class="status-message" data-mcp-usage></p>
```

- [ ] **Step 6: Manuell verifiering i browser**

Kör `npm run web:dev` i `valvet_promptbanken` (kräver `VITE_SUPABASE_URL`/`VITE_SUPABASE_PUBLISHABLE_KEY` i miljön). Logga in som Free-testanvändare:
1. Mina insättningar: räknaren visar `<n> av 50 insättningar` och stämmer mot faktiskt antal.
2. MCP-fliken: raden visar `<k> av 1 aktiva MCP-nycklar. <s> av 5 sparningar via MCP denna månad. <c> av 5 katalogkopior denna månad.`
3. Skapa en insättning → räknaren ökar utan sidladdning. Arkivera den → räknaren minskar.
4. Devtools → Network → blockera `get_plan_usage`-anropet → ladda om: räknaren visar `<n> av 50` (fallback-konstanten), MCP-användningsraden är tom, inga JS-fel i konsolen.
5. Som Pro-testanvändare: `av 1000`, `av 3 aktiva MCP-nycklar`, `Obegränsade sparningar via MCP (Pro). Obegränsade katalogkopior (Pro).`

Expected: samtliga fem punkter gröna.

- [ ] **Step 7: Commit (valvet_promptbanken-repot)**

```bash
git add src/vault.js vault.html
git commit -m "feat: read plan limits/usage from get_plan_usage instead of constants"
```

---

### Task 3: Textfixar i Valvet — Free får update/archive

**Files:**
- Modify: `valvet_promptbanken/vault.html:169-173` (guide-intro) och `:227-231` (guide-note)

**Interfaces:**
- Consumes: faktaunderlaget i Global Constraints (Free får update/archive; save 5/mån Free).
- Produces: inga kodgränssnitt — endast copy.

- [ ] **Step 1: Rätta guide-introt**

I `valvet_promptbanken/vault.html`, ändra stycket (rad 169-173):

```html
          <p>
            Tänk på nyckeln som en riktig nyckel till en riktig dörr. Varje AI-klient (Claude, ChatGPT)
            är en dörr in till ditt valv — koppla in nyckeln i klienten så kan den läsa och skriva
            i dina insättningar åt dig. Välj din klient nedan.
          </p>
```

(Ändringen: "läsa och (om du har Pro) skriva" → "läsa och skriva".)

- [ ] **Step 2: Rätta guide-noten**

Ändra stycket (rad 227-231) till:

```html
        <p class="guide-note" style="margin-top:1rem;">
          <code>list_my_items</code>, <code>search_my_items</code>, <code>get_my_item</code>,
          <code>update_my_item</code> och <code>archive_my_item</code> fungerar för alla planer.
          <code>save_my_item</code> är också tillgängligt för alla, men Free har en kvot på 5 nya
          insättningar per månad via MCP — Pro har ingen kvot.
        </p>
```

- [ ] **Step 3: Verifiera att inga Pro-only-påståenden finns kvar**

Kör i `valvet_promptbanken`:
```bash
grep -rn "kräver Pro" vault.html login.html planer.html
```
Expected: inga träffar som handlar om `update_my_item`/`archive_my_item`. (Träffar om andra Pro-funktioner, t.ex. promptpaket, är korrekta och lämnas.)

- [ ] **Step 4: Commit (valvet_promptbanken-repot)**

```bash
git add vault.html
git commit -m "fix: MCP guide no longer claims update/archive require Pro"
```

---

### Task 4: Textfixar i MCP-servern — beskrivningar + beslutslogg

**Files:**
- Modify: `mcp_promptbanken/DECISIONS.md` (tillägg överst, rör inte historiken)
- Modify: `mcp_promptbanken/mcp-server/server/mcp_server.py:1344-1367` (`_tool_definitions`) och `:1815-1838` (docstrings)

**Interfaces:**
- Consumes: faktaunderlaget i Global Constraints; migration `20260718090000` i promptbanken-repot som referens.
- Produces: inga kodgränssnitt — verktygsbeskrivningar och beslutslogg. Ingen logikändring: gating ligger i RPC:erna, och `_classify_vault_write_error`-mappningarna (`"Uppgradera till Pro"` → `not_pro`) behålls oförändrade som skydd om DB-sidan skulle ändras igen.

- [ ] **Step 1: Lägg tillägg i DECISIONS.md**

Överst i `mcp_promptbanken/DECISIONS.md`, direkt efter rubriken `# Beslut` (rad 1), infoga:

```markdown
## 2026-07-18 - Free får update/archive; Pro-only-delen av 2026-07-17-beslutet upphävd

### Beslut
Produktbeslut 2026-07-18: `update_my_item` och `archive_my_item` är öppna för
Free-nycklar. Gaten togs bort i promptbanken-repots migration
`20260718090000_valvet_free_update_archive_via_mcp.sql` (RPC:erna
`update_my_item_for_key`/`archive_my_item_for_key` kräver inte längre
`has_active_pro_entitlement`). `save_my_item`-kvoten (Free 5/kalendermånad)
och `save_workspace_prompt` (Pro-only) är oförändrade.

### Skäl
Update/archive är grundläggande hygien, inte premiumvärde — att spärra dem
bakom Pro innebar att en AI-klient kunde skapa poster på Free men aldrig
rätta eller städa dem.

### Konsekvens
Serverns verktygsbeskrivningar får inte längre säga "Pro-only" för
update/archive. Felklassificeringen `not_pro` i `_classify_vault_write_error`
behålls som skydd ifall RPC-sidan ändras igen.
```

- [ ] **Step 2: Rätta `_tool_definitions()`**

I `mcp_promptbanken/mcp-server/server/mcp_server.py`, ändra beskrivningen för `update_my_item` (rad 1345-1348):

```python
            "description": (
                "Update an existing Valvet item. Available on all plans. expected_updated_at "
                "(from a prior get_my_item call) is required for optimistic locking."
            ),
```

och för `archive_my_item` (rad 1364-1367):

```python
            "description": (
                "Archive or restore a Valvet item. Available on all plans. confirm must be true, "
                "otherwise the call is rejected."
            ),
```

- [ ] **Step 3: Rätta `@mcp.tool()`-docstrings**

Ändra `update_my_item`-docstringen (rad 1823-1825):

```python
    """Update an existing Valvet item. Available on all plans. expected_updated_at
    must be the updated_at value from a prior get_my_item/list_my_items call
    (optimistic locking) -- on mismatch, re-fetch and retry."""
```

och `archive_my_item`-docstringen (rad 1832-1836):

```python
    """Archive (or, with restore=true, un-archive) a Valvet item. Available on
    all plans. confirm must be explicitly true -- the call is rejected otherwise,
    to guard against an ambiguous or injected instruction archiving the wrong
    item. Archiving an already-archived item (or restoring an already-active
    one) is a safe no-op."""
```

- [ ] **Step 4: Verifiera att inga Pro-only-påståenden finns kvar för update/archive**

```bash
grep -n "Pro-only" mcp-server/server/mcp_server.py
```
Expected: inga träffar för `update_my_item`/`archive_my_item`. (`save_workspace_prompt` är fortsatt Pro-only — träffar där är korrekta.)

- [ ] **Step 5: Commit (mcp_promptbanken-repot)**

```bash
git add DECISIONS.md mcp-server/server/mcp_server.py
git commit -m "docs: update/archive tool descriptions no longer claim Pro-only"
```

- [ ] **Step 6: Notera driftsättning**

Beskrivningsändringarna når klienterna först vid nästa deploy av servern (manuell `docker compose up -d --build` på VPS:en). Ingen brådska — texterna är kosmetiska; RPC-beteendet är redan rätt i prod. Flagga i sluppsummeringen att deploy återstår.

---

### Task 5: Markera stale rader i delade designspecen

**Files:**
- Modify: `promptbanken/docs/superpowers/specs/2026-07-16-valvet-design.md:70-80` (Free/Pro-tabellen)

**Interfaces:**
- Consumes: faktaunderlaget i Global Constraints.
- Produces: ingen kod — historisk spec markeras ersatt, skrivs inte om.

- [ ] **Step 1: Uppdatera tabellraderna och lägg ersättningsnotis**

I `promptbanken/docs/superpowers/specs/2026-07-16-valvet-design.md`, ändra raderna 77-78 i tabellen:

```markdown
| Uppdatera via MCP (`update_my_item`) | ~~nej~~ ja (sedan 2026-07-18) | ja |
| Arkivera/återställa via MCP (`archive_my_item`) | ~~nej~~ ja (sedan 2026-07-18) | ja |
```

och infoga direkt efter tabellen (efter raden `| Export | ... |`, rad 80):

```markdown
> **Ersatt 2026-07-18:** Pro-gaten för `update_my_item`/`archive_my_item` togs
> bort genom produktbeslut — se migration
> `20260718090000_valvet_free_update_archive_via_mcp.sql` och
> `docs/superpowers/specs/2026-07-18-plan-usage-sync-design.md`.
```

- [ ] **Step 2: Commit (promptbanken-repot)**

```bash
git add docs/superpowers/specs/2026-07-16-valvet-design.md
git commit -m "docs: mark update/archive Pro gate as superseded in Valvet spec"
```
