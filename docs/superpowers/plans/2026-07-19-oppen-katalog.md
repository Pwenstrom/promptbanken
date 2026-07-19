# Öppen katalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Avveckla all Pro-gating för att LÄSA Promptbanken-katalogen — alla 42 premiummallar och alla katalogposter blir öppna för alla; Valvet förblir enda ingången för att spara/kopiera.

**Architecture:** En migration i `promptbanken` öppnar tre DB-ytor (visibility-flip, `list_pro_templates`, `get_pro_templates_for_mcp_key`, `copy_catalog_item_to_valvet`-villkoret). Webb- och MCP-lagren behöver bara textjusteringar — lås-UI:t i `pro.js` är datadrivet av `is_unlocked` och släcks av sig självt. Alias-strategi: inga namn/vyer/kolumner tas bort.

**Tech Stack:** Postgres/Supabase (plpgsql), vanilla JS, Python FastMCP, docker-compose på VPS.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-19-oppen-katalog-design.md` i detta repo.
- Pro-planen behålls för Valvet — inga Valvet-gränser (50/1000, 1/3 nycklar, 5/mån sparningar, 5/mån kopior) ändras.
- Kommun-sidans licens-/arbetsytemekanik rörs inte.
- Alias-strategi: `published_workspace_content`, `list_pro_templates` (namn), `is_unlocked`-kolumnen behålls.
- `security definer`-funktioner som återskapas: `set search_path = ''`, fullt schemakvalificerade referenser.
- `visibility='private'`-rader rörs ALDRIG (användares egna utkast).
- Inga automattester i repona — verifiering via SQL-checklistor + curl + browser (befintlig konvention).
- Migrationer mot live-DB körs via Supabase MCP `apply_migration` (godkänt av Peter 2026-07-19).

---

### Task 1: DB-migration + verifieringschecklista (`promptbanken`)

**Files:**
- Create: `supabase/tests/verify_open_catalog.sql`
- Create: `supabase/migrations/20260719100000_open_catalog.sql`

**Interfaces:**
- Consumes: befintliga definitioner i `20260702160000_pro_prompt_templates.sql` (`list_pro_templates`), `20260703100000_pro_templates_for_mcp_key.sql` (`get_pro_templates_for_mcp_key`), `20260718100000_copy_catalog_item_to_valvet.sql` (kopierings-RPC:n).
- Produces: samma tre funktionssignaturer, nu utan Pro-gating. Task 2–4 ändrar bara texter.

- [ ] **Step 1: Skriv checklistan** — `supabase/tests/verify_open_catalog.sql`:

```sql
-- verify_open_catalog.sql — manuell checklista mot live (ingen staging finns).
-- FÖRE migrationen (läge 2026-07-19): 3 rader visibility='workspace' i
-- katalogen, published_public_content = 0 rader, list_pro_templates() som
-- anon ger is_unlocked=false och prompt_text=null.

-- 1. Räkning före/efter:
select visibility, count(*) from public.content_items
 where module='kommun' group by visibility;
-- Efter: inga 'workspace'-rader; 'private'-antalet OFÖRÄNDRAT (12).

select count(*) from public.published_public_content;  -- Efter: 2
select count(*) from public.published_workspace_content; -- Efter: 2 (alias, samma mängd)

-- 2. Premiummallar öppna för alla (kör som anon/utloggad):
select count(*) filter (where is_unlocked) as unlocked,
       count(*) filter (where prompt_text is not null) as with_text,
       count(*) as total
  from public.list_pro_templates();
-- Förväntat: 42 / 42 / 42.

-- 3. Nyckel-RPC:n öppen även för ogiltig nyckel:
select count(*) filter (where is_unlocked) as unlocked, count(*) as total
  from public.get_pro_templates_for_mcp_key('finns-inte');
-- Förväntat: 42 / 42.

-- 4. Som Free-inloggad användare (REST/SQL-editor-impersonation):
--    kopiera en f.d. workspace-post — ska LYCKAS (gav tidigare
--    'kräver Pro'-fel):
-- select * from public.copy_catalog_item_to_valvet('<fd-workspace-item-id>');
```

- [ ] **Step 2: Kör checklistans "före"-frågor mot live** — bekräfta utgångsläget (3/0/teaser).

- [ ] **Step 3: Skriv migrationen** — `supabase/migrations/20260719100000_open_catalog.sql`:

```sql
-- 20260719100000_open_catalog.sql
-- Delprojekt 6: katalog-Pro avvecklas. Allt katalogingehåll öppet för alla.
-- Pro behålls för Valvet (gränser orörda). Alias-strategi: inga namn bort.
-- Spec: docs/superpowers/specs/2026-07-19-oppen-katalog-design.md

-- 1. Flippa katalogens workspace-rader till public (private rörs inte).
update public.content_items
   set visibility = 'public'
 where module = 'kommun' and visibility = 'workspace';

-- 2. list_pro_templates(): alltid upplåst, även utloggad.
create or replace function public.list_pro_templates()
returns table(
    id uuid, area text, area_label text, title text, syfte text,
    output_format text, prompt_text text, tags text[],
    risk_level public.content_risk_level, security_examples text[],
    sort_order integer, is_unlocked boolean
)
language sql stable security definer set search_path = ''
as $$
    select t.id, t.area, t.area_label, t.title, t.syfte, t.output_format,
           t.prompt_text, t.tags, t.risk_level, t.security_examples,
           t.sort_order, true
      from public.pro_prompt_templates t
     order by t.sort_order;
$$;
revoke all on function public.list_pro_templates() from public;
grant execute on function public.list_pro_templates() to anon, authenticated;

-- 3. get_pro_templates_for_mcp_key(): samma — nyckeln behöver inte ens
--    verifieras längre, men signaturen behålls (alias för MCP-klienter).
create or replace function public.get_pro_templates_for_mcp_key(p_key_hash text)
returns table(
    id uuid, area text, area_label text, title text, syfte text,
    output_format text, prompt_text text, tags text[],
    risk_level public.content_risk_level, security_examples text[],
    sort_order integer, is_unlocked boolean
)
language sql stable security definer set search_path = ''
as $$
    select t.id, t.area, t.area_label, t.title, t.syfte, t.output_format,
           t.prompt_text, t.tags, t.risk_level, t.security_examples,
           t.sort_order, true
      from public.pro_prompt_templates t
     order by t.sort_order;
$$;
revoke all on function public.get_pro_templates_for_mcp_key(text) from public;
grant execute on function public.get_pro_templates_for_mcp_key(text) to anon, authenticated;

-- 4. copy_catalog_item_to_valvet: öppna synlighetsvillkoret.
--    Hela funktionen återskapas — kopiera definitionen VERBATIM från
--    20260718100000_copy_catalog_item_to_valvet.sql med EXAKT två ändringar:
--    a) källrads-SELECT:ens villkor
--         and (visibility = 'public' or (visibility = 'workspace' and v_is_pro))
--       ersätts med
--         and visibility in ('public','workspace')
--    b) felmeddelandet 'Den här posten finns inte eller kräver Pro.'
--       ersätts med 'Den här posten finns inte.'
--    v_is_pro-deklarationen och kvotgrenen (if not v_is_pro ...) BEHÅLLS —
--    kvoten är Valvets affärsgräns och ska vara kvar.
```

- [ ] **Step 4: Applicera mot live** via Supabase MCP `apply_migration` (namn `open_catalog`).

- [ ] **Step 5: Kör checklistans "efter"-frågor** — alla förväntningar ska stämma (0 workspace-rader, 12 private orörda, 2/2 i vyerna, 42/42/42, 42/42).

- [ ] **Step 6: Commit**

```powershell
git add supabase/tests/verify_open_catalog.sql supabase/migrations/20260719100000_open_catalog.sql
git commit -m "feat: open catalog - retire Pro-gating for catalog reads"
```

### Task 2: Kommun-webbens texter (`promptbanken`)

**Files:**
- Modify: `planer.html` (rad ~59–77: "✗ Premium-mallar", "Hela premiumbiblioteket")
- Modify: `src/pro.js` (rad ~274–280: banner-ternären)
- Ev. fler träffar: `grep -in "premium" *.html src/*.js` under arbetet

**Interfaces:**
- Consumes: `list_pro_templates()` returnerar nu alltid `is_unlocked=true` (Task 1).
- Produces: inga API:er — bara texter.

- [ ] **Step 1:** `planer.html`: ersätt `<li>✗ Premium-mallar</li>` (Free) och `<li>✓ Hela premiumbiblioteket</li>`/premiumbibliotek-pitchen (Pro/högre tiers) med rader som inte påstår mallaccess-skillnad. Free-kortet: `<li>✓ Hela promptbiblioteket</li>`. Pro-kortets pitch flyttar tyngd till egna mallar/arbetsytor/MCP-nycklar. Kör `grep -in "premium" planer.html` efteråt — 0 träffar som påstår gating.
- [ ] **Step 2:** `src/pro.js`: ersätt banner-ternären (`anyUnlocked ? 'Din plan har Pro aktiverat…' : 'Du ser en förhandsvisning…'`) med den fasta texten `'Hela promptbiblioteket är öppet — alla mallar nedan är upplåsta.'`. Rör inte lås-koden i övrigt (död, datadriven).
- [ ] **Step 3:** Grep-svep: `grep -in "premium\|kräver Pro\|Uppgradera till Pro" *.html src/*.js mcp-server/server/*.py` — åtgärda kvarvarande påståenden om mallaccess (inkl. lokala MCP-serverns `list_pro_templates`-beskrivning). Valvet-gränser/arbetsytor-texter lämnas.
- [ ] **Step 4:** Verifiera i browser efter deploy (Task 5) — pro-sidan visar alla mallar upplåsta utan inloggning.
- [ ] **Step 5: Commit** — `git commit -m "feat: open catalog - remove Pro template claims from web texts"`

### Task 3: Valvets katalogläsning (`valvet_promptbanken`)

**Files:**
- Modify: `src/vault.js:431`

**Interfaces:**
- Consumes: `published_public_content` innehåller nu hela katalogen (Task 1).

- [ ] **Step 1:** Ersätt rad 431:

```js
const view = state.workspace?.plan === 'pro' ? 'published_workspace_content' : 'published_public_content';
```

med:

```js
const view = 'published_public_content';
```

Kvottexterna i `updateCatalogQuota` rörs INTE (Valvet-kvoten kvar).
- [ ] **Step 2:** `npm run build` — bygget grönt.
- [ ] **Step 3: Commit** — `git commit -m "feat: catalog fully open - always read published_public_content"`

### Task 4: Hostade MCP-serverns texter (`mcp_promptbanken`, nästlad mapp `mcp_promptbanken/mcp_promptbanken`)

**Files:**
- Modify: `mcp-server/server/mcp_server.py:339-341` (docstring) och `:1209-1212` (`_tool_definitions`)
- Modify: `DECISIONS.md` (tillägg, historik orörd)

- [ ] **Step 1:** Båda beskrivningarna för `list_pro_templates` ersätts med: `"List the full Promptbanken template catalog (name kept for backwards compatibility -- the catalog is open, no Pro plan required)."`
- [ ] **Step 2:** `DECISIONS.md`-tillägg daterat 2026-07-19: katalog-Pro avvecklad, alla mallar öppna, referens till migration `20260719100000_open_catalog.sql`; verktygsnamnet behålls som alias.
- [ ] **Step 3:** `python -m py_compile mcp-server/server/mcp_server.py` — OK.
- [ ] **Step 4: Commit** — `git commit -m "docs: list_pro_templates now serves the open catalog"`

### Task 5: Deploy + end-to-end-verifiering

- [ ] **Step 1:** Push `promptbanken` och `valvet_promptbanken` och `mcp_promptbanken` till origin/main (godkänt).
- [ ] **Step 2:** VPS: `ssh promptbanken-vps` → `cd ~/mcp_promptbanken && git pull --ff-only && docker-compose up -d --build` (ContainerConfig-workaround vid behov: `docker-compose stop && docker rm -f <container> && docker-compose up -d`).
- [ ] **Step 3:** `curl -s -X POST https://mcp.promptbanken.se/mcp -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_pro_templates","arguments":{}}}' -H 'Content-Type: application/json'` UTAN nyckel — 42 mallar, alla med prompt_text.
- [ ] **Step 4:** Browser: kommun-webbens pro-sida utloggad — alla mallar upplåsta; Valvet "Bläddra i Promptbanken" — katalogen listas (samma innehåll oavsett plan).
- [ ] **Step 5:** Uppdatera minnesfilen `valvet-fas1-status` med utfallet.
