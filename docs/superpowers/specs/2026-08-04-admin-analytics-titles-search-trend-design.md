# Admin-analys: titlar, sökmissar, daglig trend

## Bakgrund

`admin.html` / `src/adminUsage.js` är read-only-dashboarden för det öppna
biblioteket (se [2026-07-29-open-library-usage-admin-design.md](2026-07-29-open-library-usage-admin-design.md),
shippat i `5a09156`/`eb90375`). Tre brister har identifierats mot
produktionsdata 2026-08-04:

1. Prompt-/paket-tabellerna visar rå `slug` (t.ex. `legacy-arbetsbank-37`,
   `legacy-visuellt-27`). Dessa är riktiga publicerade katalogprompts —
   sluggen kommer från `20260725120000_seed_catalog_from_existing_templates.sql`
   (`'legacy-' || area || '-' || sort_order`) för mallar som saknade egen slug
   vid seedning. Riktig titel finns i `catalog_prompt_variants.title` men
   joinas aldrig in.
2. `get_library_search_feedback` beräknar redan `by_context` (missandel per
   filter/kontext) men `renderSearchFeedback()` visar bara totalsumma —
   sökmissarna går inte att bryta ner per behov.
3. `get_library_usage_summary` beräknar redan `daily` (events per dag och
   källa) men det renderas aldrig — går inte att visuellt verifiera att
   statistiken rör sig rätt efter en katalogändring.

Ingen av dessa kräver ny datainsamling. All data finns redan i
`library_usage_events` eller katalogtabellerna.

## Mål

1. Prompt-, paket- och felrader i adminytan visar läsbar titel, inte bara
   slug. Titel saknas → visa `"(borttagen — <slug>)"` istället för tomt.
2. Sökningar-sidan visar missandel per kontext/filter, inte bara totalt.
3. Översikt visar en daglig trendtabell per källa (`web` / `open_mcp`) för
   vald period.

## Icke-mål

- Ingen ny eventtyp, inget nytt spårat fält, ingen ändring av
  `track_library_usage_event`.
- Ingen ändring av throttling, retention eller RLS.
- Ingen graf-/chartbibliotek — enkel tabell räcker (samma stil som övriga
  dashboardtabeller).
- Ingen ändring av `mcp_promptbanken` eller lokal `mcp-server/`.

## Ändringar

### Migration: `supabase/migrations/<ny>_library_usage_titles_and_trend.sql`

`create or replace` på tre befintliga RPC:er (samma signatur, ingen
breaking change för anropare):

**`get_library_prompt_usage(p_days, p_limit)`** — lägg kolumn
`prompt_title text`. Join:

```sql
left join public.catalog_prompts cp on cp.slug = e.prompt_slug
left join lateral (
  select v.title
    from public.catalog_prompt_variants v
   where v.prompt_id = cp.id
   order by (v.context_key = 'generell') desc, v.created_at asc
   limit 1
) title on true
```

`prompt_title` blir `null` om `cp` saknas (borttagen/aldrig funnits) —
frontend visar fallback-text, RPC:n själv gissar inte.

**`get_library_package_usage(p_days, p_limit)`** — samma mönster mot
`catalog_packages` / `catalog_package_variants`, ny kolumn
`package_title text`.

**`get_library_usage_errors(p_days, p_limit)`** — samma två left joins
(prompt och paket, ett event har som mest ett av fälten satt), nya kolumner
`prompt_title text`, `package_title text`.

`get_library_search_feedback` och `get_library_usage_summary` ändras inte i
migrationen — `by_context` och `daily` finns redan i deras jsonb-retur.

Behörighet, `security definer`, `search_path` och
`current_user_is_platform_owner()`-kontroll ärvs oförändrad från befintliga
funktioner (samma `create or replace`, bara `returns table`-listan växer och
query-body joinar in title).

### `src/adminUsage.js`

- `renderPromptUsage()` / `renderPackageUsage()` / `renderErrors()`: visa
  `row.prompt_title || row.package_title` om satt, annars
  `"(borttagen — " + slug + ")"`. Slug kvar som liten undertext eller
  `title`-attribut för spårbarhet, inte huvudtext.
- `renderSearchFeedback()`: lägg tabell under befintliga siffror, en rad per
  `state.search.by_context[]`: kontext (`context_key`, `-` om tom),
  `total_count`, `empty_count`, missandel `%`. Sortering ärvs från RPC
  (redan `order by empty_count desc`).
- Ny `renderDailyTrend()`: tabell i Översikt, en rad per dag
  (`state.summary.daily[]` grupperad `day` → `{web, open_mcp}` events).
  Anropas från `renderAll()`.
- `exportCsv()` / `exportJson()`: ta med `prompt_title`/`package_title` i
  CSV-header och rader, ingen ändring av JSON-export (redan råobjekt).

### `admin.html`

- Prompt-/paket-/fel-tabellernas `<th>` uppdateras: `Prompt` → `Prompt`
  (samma, cellen byter bara vad den visar), ingen ny kolumn för titel —
  titel ersätter slug som primärtext i befintlig cell.
- Nytt `<div data-search-context>` under `data-search-feedback` i
  Sökningar-sektionen.
- Ny `<div class="workspace-table-wrap">` med `data-daily-trend`-tabell i
  Översikt, mellan periodväljare och statistikkorten (eller efter korten —
  under implementation, ej designkritiskt).

## Datakvalitet vid borttagen/omdöpt prompt

Om en prompt byter slug eller tas bort refererar historiska events
fortfarande till den gamla sluggen. RPC:n gissar inte ihop dem — visar
`"(borttagen — <slug>)"`. Det är en sanningsenlig signal ("den här sluggen
finns inte i katalogen just nu"), inte ett fel att dölja. Framtida
omslugg-spårning (mappa gammal→ny slug) är utanför scope.

## Verifiering

1. SQL: kör de tre uppdaterade RPC:erna mot staging/prod som platform-owner,
   kontrollera att `legacy-*`-sluggarna nu returnerar en riktig titel från
   `catalog_prompt_variants`.
2. SQL: kör samma RPC:er med en slug som inte finns i `catalog_prompts` —
   kontrollera `prompt_title` är `null` (fallbacken byggs i frontend, inte
   SQL).
3. SQL: bekräfta att icke-platform-owner fortfarande får exception (oförändrat
   beteende, samma guard).
4. Webbläsare: ladda `admin.html`, kontrollera Prompts/Paket/MCP-status visar
   titlar, Sökningar visar kontext-nedbrytning, Översikt visar dagstrend.
5. Build: `npm run build`; efter build kontrollera `dist/prompts/` finns kvar.

## Rekommenderad implementationordning

1. Migration: uppdatera tre RPC:er med title-join.
2. Verifiera SQL direkt (steg 1–3 ovan) innan frontend-arbete.
3. `src/adminUsage.js`: title-fallback i tre renderers, `renderDailyTrend`,
   `by_context`-tabell, uppdaterad CSV-export.
4. `admin.html`: ny markup för trend och kontext-tabell.
5. Webbläsarverifiering, build-verifiering.
