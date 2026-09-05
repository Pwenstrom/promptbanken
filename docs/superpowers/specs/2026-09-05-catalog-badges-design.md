# Ny/Trendande/Populär-märkning i katalogen — Design

**Status:** Godkänd av användaren i chatt (badge-definition, uppdateringstakt,
prioritetsordning, och att båda prompter och paket ska ha det). Redo för
implementationsplan.

## Bakgrund

Promptbankens katalogsida (`promptbanken.html`) visar prompt- och paketkort
utan någon indikation av vad som är nytt eller mycket använt. Vi har redan
statistik som kan svara på det: `library_usage_events` (tabell från
`20260729082734_open_library_usage_events.sql`) loggar `prompt_view`,
`prompt_copy`, `package_view` och motsvarande MCP-händelser per
`prompt_slug`/`package_slug`, med 180 dagars retention och en nattlig
pg_cron-städning. Admin-RPC:erna `get_library_prompt_usage`/
`get_library_package_usage` rankar redan efter användning, men bara för
plattformsägare — inget av detta är synligt i katalogen.

Mål: ge varje kort i katalogen (prompter och paket) en av tre möjliga
badges — **Ny**, **Trendande**, **Populär** — beräknat från redan
existerande statistik, utan att förändra hur statistiken samlas in.

## Omfattning

- **Ingår:** en badge per katalogkort på `promptbanken.html`, för både
  prompt- och paketkort (`createCatalogPromptCard`/`createCatalogPackageCard`
  i `script.js`).
- **Ingår inte:** admin-UI för att manuellt sätta/övertrumfa en badge
  (kan läggas till senare om det behövs — inte efterfrågat nu). Legacy
  statiska prompter utan katalogtvilling (`prompts.json`-poster som saknar
  en rad i `catalog_prompts`, se `LEGACY_STATIC_CATALOG_MAP` i `script.js`)
  får ingen badge — de saknar redan andra katalogfunktioner
  ("Lägg till i Mitt bibliotek") av samma skäl.
- **Ingår inte:** ändringar av `mcp_promptbanken`-repot eller `/mcp`-ytan.
  Statistiken som redan samlas in där (source='open_mcp') används som
  indata, men inget i den ytan ändras.

## Badge-definitioner

Alla tre beräknas per katalogobjekt (`catalog_prompts.slug` respektive
`catalog_packages.slug`), en gång per natt, från `library_usage_events`.

| Badge | Regel |
| --- | --- |
| **Ny** | `catalog_prompts.created_at` / `catalog_packages.created_at` inom senaste 14 dagarna. |
| **Trendande** | Användning (view+copy+get, summerat) senaste 7 dagarna ≥ 3× användningen de föregående 7 dagarna (dag 8–14 bak), OCH minst 3 händelser senaste 7 dagarna (annars räknas 0→1 händelse som "oändlig tillväxt"). Begränsat till topp 5 kvalificerade prompter och topp 5 kvalificerade paket. |
| **Populär** | Bland topp 10 prompter / topp 5 paket rankat efter total användning (view+copy+get) senaste 90 dagarna, OCH minst 5 händelser i fönstret (annars kan ett enda tidigt besök krönas "populärt" i en tyst katalog). |

**Prioritet vid flera träffar:** Ny > Trendande > Populär. Ett objekt bär
högst en badge.

Rank-baserat (topp N) i stället för absoluta trösklar för Trendande/Populär
gör att gränsen själv följer med när trafiken växer eller minskar, utan att
någon behöver justera magiska tal i koden.

## Datamodell

Ny tabell, populerad av ett nattligt jobb — inga skrivningar från
klient/RPC:

```sql
create table public.catalog_badges (
    subject_type text not null check (subject_type in ('prompt', 'package')),
    subject_slug text not null,
    badge text not null check (badge in ('new', 'trending', 'popular')),
    computed_at timestamptz not null default now(),
    primary key (subject_type, subject_slug)
);
```

En rad per katalogobjekt som faktiskt har en badge — objekt utan träff
har ingen rad (frontend behandlar "ingen rad" som "ingen badge", inte
som ett fel eller en "väntar på data"-status).

RLS: `enable row level security`, en `select`-policy för `anon, authenticated`
(offentlig läsning, samma badge alla besökare ser — ingen
personalisering). Ingen `insert`/`update`/`delete`-policy: skrivning sker
enbart via en `security definer`-funktion som det nattliga jobbet anropar,
samma mönster som `app_private.purge_library_usage_events()`.

## Beräkningsfunktion och schemaläggning

`app_private.recompute_catalog_badges()` — en `security definer`-funktion,
inget indataargument, ingen ägarskapskontroll behövs (den anropas bara av
`pg_cron`, aldrig av en användare — samma resonemang som
`purge_library_usage_events`). Kör i en transaktion:

1. `truncate` eller `delete` alla rader i `catalog_badges`.
2. Sätt in "new"-raderna direkt från `catalog_prompts`/`catalog_packages`
   där `created_at >= now() - interval '14 days'` och `status = 'published'`.
3. Beräkna "trending"-kandidater (7-dagars vs föregående 7-dagars summa per
   slug, filtrerat på minst 3 händelser, rankat, topp 5 per typ) och sätt
   in de som INTE redan fick "new".
4. Beräkna "popular"-kandidater (90-dagars summa per slug, minst 5
   händelser, rankat, topp 10 prompter / topp 5 paket) och sätt in de som
   inte redan fick "new" eller "trending".

Schemaläggs med `cron.schedule('recompute-catalog-badges', '30 2 * * *', ...)`
— 30 minuter innan den befintliga `purge-library-usage-events` (02:15 vs
03:15, se befintlig kommentar i `20260729082734`) så att badges alltid
beräknas på fullständig, ej ännu utrensad statistik. (Utrensningen tar
bara bort händelser äldre än 180 dagar — påverkar aldrig 7/14/90-dagarsfönstren
badge-beräkningen faktiskt tittar på, ordningen är ett litet extra
säkerhetsmarginal, inte ett krav.)

## Läs-RPC

```sql
create or replace function public.list_catalog_badges()
returns table (subject_type text, subject_slug text, badge text)
language sql
stable
security definer
set search_path = ''
as $$
    select subject_type, subject_slug, badge from public.catalog_badges;
$$;

revoke all on function public.list_catalog_badges() from public;
grant execute on function public.list_catalog_badges() to anon, authenticated;
```

En enda rad-lista, inget filterargument — katalogen har för få objekt
(~140 prompter, betydligt färre paket) för att pagineringsbehovet ska
uppstå. Frontend hämtar detta en gång per sidladdning och bygger en
`Map<slug, badge>` per typ, precis som `catalogAreaLabels`/
`catalogRiskLabels` redan görs i `script.js`.

## Frontend

**Datahämtning:** `loadCatalogPrompts()`/`loadCatalogPackages()` (eller en
gemensam init-funktion om de redan körs parallellt) anropar
`list_catalog_badges()` en gång, bygger `catalogPromptBadges`/
`catalogPackageBadges`-mapparna (samma modul-nivå-`Map`-mönster som
`catalogPromptsById`), innan korten renderas.

**Rendering:** en ny `catalogBadgeLabels`-konstant (svenska etiketter:
`{ new: 'Ny', trending: 'Trendande', popular: 'Populär' }`), och en badge-
`<span>` läggs till i `createCatalogPromptCard`/`createCatalogPackageCard`s
tagg-rad (samma `.card-tags`-container som risk-chippen jag redan lade
till i prompt-korten) — placerad FÖRE risk-chippen, så den mest
"nyhetsvärda" informationen läses först.

```html
<span class="catalog-new-badge" data-badge="new">Ny</span>
```

Tre CSS-klasser (`data-badge="new|trending|popular"`), samma pill-bas som
`.risk-chip` (`.card-tags span` ger padding/border-radius/font-storlek
gratis), tre färgvarianter som INTE krockar visuellt med risk-chippens
grön/gul/röd-skala (risk och badge ska aldrig kunna förväxlas). Godkänt via
designkanvasen (`https://claude.ai/code/artifact/891ce739-1116-43d8-b9b2-3ac804616018`):

| Badge | Bakgrund | Text | Ikon (12px inline SVG) |
| --- | --- | --- | --- |
| Ny | `#eef4ff` | `#0052a3` | 4-udda gnista (samma "öppen katalog"-blått som redan används, se `docs/superpowers/plans/2026-09-01-unified-catalog-list.md`) |
| Trendande | `#f3e8ff` | `#7e22ce` | Trendpil uppåt (stroke-baserad) |
| Populär | `#fdf6e3` | `#8a6d1d` | Fylld stjärna |

Badge-`<span>` läggs FÖRE risk-chippen i `.card-tags`-raden (mest
nyhetsvärda informationen läses först). Paketkort saknar idag en
`.card-tags`-rad helt — den läggs till, och den befintliga
`.catalog-package-type`-chippen (Samling/Arbetssätt) flyttas in i samma
rad som badgen i stället för att stå kvar som en fristående `<span>`
under brödtexten (ren layoutstädning, ingen semantisk ändring).

**Paketkort:** samma mönster i `createCatalogPackageCard`, som idag saknar
en tagg-rad helt — den läggs till bara för badgen (paketkort har inte
risk-chip eller area-kicker att dela raden med, men samma `.card-tags`-
klass återanvänds för konsekvent spacing).

## Felhantering

- `list_catalog_badges()`-anropet är non-fatal: om det fejlar eller
  returnerar tomt, renderas korten precis som idag (utan badge) — samma
  "syns bara om vi har säker data"-princip som resten av katalogsidan
  redan följer (t.ex. `renderCatalogUnavailableState`).
- Om det nattliga jobbet av någon anledning inte kör en natt: gamla
  `catalog_badges`-rader ligger kvar orörda (ingen delete sker förrän
  jobbet faktiskt lyckas köra klart, eftersom hela beräkningen sker i en
  transaktion) — katalogen visar gårdagens badges snarare än inga alls.

## Testning

- SQL-verifiering (`supabase/tests/verify_catalog_badges.sql`,
  rollback-wrapped, samma mönster som `verify_pro_mcp_key_limit.sql`):
  skapar fixture-rader i `catalog_prompts`/`library_usage_events` med kända
  tidsstämplar och användningsmönster, kör
  `app_private.recompute_catalog_badges()`, verifierar att rätt slugs får
  rätt badge (inklusive prioritetsordningen Ny > Trendande > Populär) och
  att minimitrösklarna respekteras.
- `npm test`: en ny fixturebaserad test i `scripts/` som verifierar att
  `catalogBadgeLabels`-etiketterna renderas i kortets DOM när en badge-map
  har en post för ett givet slug, och att inget badge-element skapas när
  mappen saknar en post (matchar det befintliga testmönstret för
  katalogkort, t.ex. `scripts/catalog-page-template.test.mjs`).
- Manuell verifiering efter deploy: kör
  `select app_private.recompute_catalog_badges();` en gång manuellt (som
  gjordes för `share_referenced_package_items`-migrationen), bekräfta
  liverendering på `promptbanken.html` innan det nattliga jobbet hunnit
  köra av sig själv.

## Självgranskning

- **Platshållarscan:** inga TBD kvar utom de explicit uppskjutna hex-
  färgvalen, som är en implementationsdetalj, inte en öppen
  designfråga.
- **Intern konsekvens:** prioritetsordningen (Ny > Trendande > Populär)
  matchar mellan badge-definitionstabellen och beräkningsfunktionens
  steg 2–4 (senare steg hoppar uttryckligen över redan-badgade slugs).
- **Omfattning:** en sammanhållen ändring (en tabell, en beräkningsfunktion,
  ett cron-jobb, en läs-RPC, två kortmallar) — inte uppdelningsbehövande.
- **Tvetydighet:** "senaste 7 dagarna" och "föregående 7 dagarna" definieras
  explicit som icke-överlappande fönster (dag 0–7 respektive dag 8–14) i
  beräkningsfunktionens beskrivning, för att undvika en dubbeltolkning av
  vilka dagar som räknas två gånger.
