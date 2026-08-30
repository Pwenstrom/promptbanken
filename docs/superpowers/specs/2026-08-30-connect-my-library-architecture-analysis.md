# Arkitektur- och återanvändningsanalys — Mitt bibliotek & Promptbanken Connect

Datum: 2026-08-30
Status: analys, INTE en implementationsplan. Inget kodarbete har gjorts.
Beställare: handover-dokument "Promptbanken — Produktstrategi, Creator,
Mitt bibliotek och Promptbanken Connect".

Metod: läsning av kod, migrationer och specar i tre repon
(`promptbanken`, `valvet_promptbanken`, `mcp_promptbanken`) plus Octopus-
hubben (`VISION.md`, `STATUS.md`, `PROJECTS.md`). Inget gissat — varje
påstående nedan har en fil:rad-källa eller en migrationsfil som stöd.

---

## A. Repoöversikt

| Repo | Ansvar | Driftform |
| --- | --- | --- |
| `promptbanken` | Huvudappen: publika katalogen (`promptbanken.html`, `script.js`), admin (`admin.html` + `src/admin*.js`), Creator-ytan (`creator*.html` + `src/creator*.js`), all Supabase-migrationshistorik (auktoritativ källa för schema), lokal stdio-MCP (`mcp-server/`) | Statisk Vite-site (GitHub Pages, `app.promptbanken.se`) + Supabase-projekt |
| `valvet_promptbanken` | Valvet: privat-bibliotek-frontend (`vault.html`/`vault.js`), inloggning (`login.html`), planer-sida | Statisk Vite-site (GitHub Pages, `valvet.promptbanken.se`), ingen egen backend — ren Supabase-JS-klient mot samma projekt |
| `mcp_promptbanken` | Den delade, Docker-driftade MCP-servern: Open MCP (`/mcp`), nyckelautentiserad yta (`/mcp/key`), admin-MCP (`/admin`), legacy SSE (`/sse`) | Docker på VPS (`mcp.promptbanken.se`) |
| `landing_promptbanken` | Landningssida | Inte inspekterad i denna analys — inget i handover-uppdraget berör den |
| `promptbanken/mcp-server` (delmodul, inte eget repo) | LOKAL stdio-MCP, en process per användare, nyckel via miljövariabel | Startas av användarens egen MCP-klient, körs aldrig som HTTP-server |

Alla tre aktiva repon delar **samma Supabase-projekt/databas**. Det finns
alltså redan en gemensam datavärld — precis den premiss handover-dokumentet
utgår från.

---

## B. Vad finns redan i Valvet

Valvet (`valvet_promptbanken`) är en ren Supabase-JS-klient (`src/vault.js`,
849 rader) mot `content_items` med `module = 'valvet'`. Ingen egen
datamodell, ingen backend.

Byggt och produktionsverifierat idag:

- **CRUD på egna objekt**: skapa (`vault.js:286-303`), redigera
  (`vault.js:267-276`), arkivera/"radera" (`vault.js:640-658`), återställ
  (`vault.js:692-710`). Ingen hård delete.
- **Kvot**: 50 aktiva objekt Free, 1000 Pro (`enforce_vault_item_limit`,
  migration `20260716101000`), helt separat gräns från Creator/kommun-taket
  på 3 prompts.
- **Katalogkopiering**: två vägar — `copy_published_prompt_to_valvet`
  (dagens källa, `catalog_prompts`) och `copy_template_to_valvet` (äldre,
  `pro_prompt_templates`). Båda skriver en **full kopia** till
  `content_items`, med proveniensfälten `source_template_id`,
  `source_version` (SHA-256-hash av källinnehållet vid kopieringstillfället)
  och `source_copied_at`.
- **Paketaktivering**: `valvet_package_activations`, en rad per aktiverat
  paket-id, ingen kopiering av innehåll.
- **MCP-nycklar**: skapa/lista/återkalla i `api_keys`-tabellen
  (`vault.js:718-812`), en nyckel per personligt Free-workspace, tre för Pro.
- **Auth**: Supabase Auth direkt (`src/auth.js`, `src/login.js`) —
  email/lösenord, lösenordsåterställning, Google OAuth.
- **Ingen rollmodell.** Explicit dokumenterat i Valvets egen plan
  (`docs/superpowers/plans/2026-07-16-valvet-web-app.md:20`): en användare,
  ett personligt workspace, inga viewer/editor/admin-roller.
- **Ingen delningsfunktion.** Ingen share-tabell, share-RPC eller share-UI
  finns i detta repo.
- **Ingen creator-yta.** Valvet är en ren konsument av publicerad katalog —
  inget publicerings- eller profilflöde finns här.

**Direkt återanvändbart för Mitt bibliotek, oförändrat:** hela
`content_items`-modellen (typ, status, visibility, ägarskap,
proveniensfält), kvotmönstret via modul-taggad trigger, katalogkopieringens
proveniensspårning, samt hela auth/workspace-bootstrapkedjan
(`ensure_personal_workspace`).

---

## C. Vad finns redan för Creator

Byggt i `promptbanken`-repot, inte i Valvet. Sju delprojekt planerade, fyra
levererade och i produktion (senaste commit idag, 2026-08-30):

1. **SEO + paketförst-IA** — levererad 2026-08-15.
2. **Creator-profiler** — levererad 2026-08-18. Tabell `creator_profiles`
   (en rad per `auth.users`, inte per workspace), slug, bio, länkar,
   publicera/avpublicera-RPC:er, publik profilsida.
3. **Creator-authoring** — levererad 2026-08-21. `content_items` med
   `module = 'kommun'` (legacy namn, se sektion M) är creatorns egna
   prompts; `creator_package_drafts`/`creator_package_items` är egna
   paket-utkast, max 8 prompts/utkast, max 3 samtidigt i granskning.
   Samtycken `creator_consent_shared`/`creator_consent_reusable`.
4. **Redaktionellt granskningsflöde** — levererad 2026-08-23/24. AI-
   förgranskning (edge function `screen-creator-submission`, skriver bara
   till `creator_submission_screenings`, ingen skrivbehörighet till
   innehåll), admin-granskningsvy i `admin.html#creator-granskning`
   (`src/adminCreatorReview.js`), beslut fattas alltid av en inloggad
   `platform_owner` via RPC (`approve_creator_prompt`,
   `approve_creator_package`, `request_changes_creator_submission`,
   `reject_creator_submission`). Godkänt innehåll landar som **utkast** i
   `catalog_prompts`/`catalog_packages` med `creator_profile_id` satt.
5. **Delningar** — tabellerna `creator_shares`/`creator_share_events`/
   `content_snapshots` skapades 2026-08-25 (migration `20260825090000`).
   RPC:er för skapa/lista/förläng/avsluta delning samt en anonym publik
   läsväg (`get_shared_content`) finns och fungerar. **UI-sidan
   `creator-shares.html` finns som fil men är inte länkad i navigationen**
   än (`docs/2026-08-24-creator-ux-structure.md` listar den som "läggs till
   när vyn finns").
6. **Översikt** — `get_my_creator_overview()` + checklista, levererad idag
   (`20260830120000_creator_overview_checklist.sql`).
7. **MCP-exponering av godkänt creator-innehåll** — **inte byggt**, och
   enligt spec medvetet blockerad tills Open MCP 1.2.2-ansökan är avgjord
   (se sektion K).

**Viktigt**: delningssystemet (`creator_shares`) delar bara **redan
publicerat katalog-innehåll** (`catalog_prompts`/`catalog_packages` med
`status='published'`), inte ett privat utkast direkt ur arbetsytan. Det
skiljer sig från handover-dokumentets exempel ("privat prompt → dela →
länk, utan publicering") — se gap i sektion H.

---

## D. Överlapp mellan Creator och Valvet

Mindre överlapp än väntat, för att grundarkitekturen redan var rätt:

- **Samma tabell, disjunkta moduler.** Creator-prompts (`module='kommun'`)
  och Valvet-objekt (`module='valvet'`) ligger i samma `content_items`-
  tabell men är helt separerade av en `check`-constraint + en
  modul-låsningstrigger (`lock_content_item_module`, migration
  `20260716100000`) som förbjuder att en rad byter modul. Två separata
  kvot-triggers (`enforce_content_access_model` för `kommun`,
  `enforce_vault_item_limit` för `valvet`) körs på samma tabell utan att
  påverka varandra — verifierat i `20260716100500_valvet_bypass_kommun_trigger.sql`,
  som uttryckligen kommenterar att Valvet "har ett eget, helt separat
  gränssystem".
- **Ingen dubblerad pakettabell.** Creator-paket-utkast
  (`creator_package_drafts`) och Valvets paketaktivering
  (`valvet_package_activations`) är två helt olika begrepp (utkast som ska
  granskas vs. en flagga för "det här kurerade paketet är aktiverat") —
  inte en duplicering, bara olika saker.
- **Verklig duplicering, en plats**: två separata katalogkopieringsvägar i
  Valvet (`copy_published_prompt_to_valvet` mot `catalog_prompts`,
  `copy_template_to_valvet` mot äldre `pro_prompt_templates`) som gör
  samma sak mot två källtabeller. Dokumenterad, medveten teknisk skuld
  (kommentar i `20260804100000`), inte adresserad i denna analys eftersom
  handover inte efterfrågar det.
- **Namnkrock, inte datakrock**: `module = 'kommun'` betyder idag "Creator-
  innehåll", ett kvarblivet namn från den ursprungliga kommun-nischade
  MVP:n (juni 2026). Ingen kod förväxlar de två, men namnet är missvisande
  för en läsare idag — flaggat i sektion M.

Slutsats: Creator och Valvet är redan byggda som **samma innehållsmodell,
två lager ovanpå den** — exakt det handover-dokumentet efterfrågar. Det
som saknas är inte enande av datamodellen, utan att koppla ihop de två
lagren i UI/UX (se sektion F, G, L).

---

## E. Datamodell — återanvänd, generalisera, eller nytt

**Återanvänd oförändrat:**

- `content_items` (typ, status, visibility, `owner_user_id`,
  `source_template_id`/`source_version`/`source_copied_at`) — bär redan
  precis den proveniensmodell handover-dokumentets sektion 5C ("Egen
  version") efterfrågar.
- `workspaces`/`profiles`/rollhierarkin — redan byggd för framtida
  organisationsnivå (`workspace_admin`/`workspace_owner` finns i enum:en,
  bara oanvända av personliga workspaces idag).
- `api_keys` med `scopes text[]` — redan ett generiskt
  åtkomstnyckel-koncept, inte hårdkodat mot ett enda verktyg.
- `creator_profiles`, `creator_shares`/`creator_share_events`/
  `content_snapshots`, `creator_package_drafts`/`creator_package_items` —
  all creator-infrastruktur är redan generell nog att inte behöva byggas om.

**Bör generaliseras, inte dupliceras:**

- `creator_shares` är idag hårdkodad mot `catalog_prompts`/
  `catalog_packages` med `status='published'` (se `create_creator_share`,
  raderna 179-197 i `20260825090000_creator_shares.sql`). Om handover-
  dokumentets "dela privat, utan publicering"-flöde ska byggas är rätt
  väg att **utöka `subject_type`** (t.ex. lägga till `'draft_prompt'`/
  `'package_draft'` som giltiga värden och peka `subject_id` mot
  `content_items`/`creator_package_drafts` istället för katalogen) —
  inte en ny paralleltabell. `content_snapshots` är redan
  subject-type-agnostisk och klarar detta utan ändring.
- Läs-RPC:erna för publicerad katalog (`list_published_prompts` m.fl.) har
  redan bevisat mönstret för bakåtkompatibel utökning: en ny
  default-parameter i en `drop function` + `create` i samma migration. Om
  "Lägg till i mitt bibliotek som referens" byggs som en ny kolumn på
  `content_items` är samma mönster (default-safe tillägg, aldrig ändra
  befintliga kolumners betydelse) rätt väg.

**Inga nya tabeller är uppenbart nödvändiga** för kärnflödet
konto → Mitt bibliotek → Connect. De två luckor som finns (referens
vs. kopia, privat delning) löses med kolumntillägg på befintliga tabeller
(sektion F, H), inte nya datavärldar.

---

## F. "Lägg till i mitt bibliotek" — referens kontra kopia

**Nuläge:** `copy_published_prompt_to_valvet` gör alltid en **full kopia**.
Prompttexten, titeln, sammanfattningen skrivs in i en ny `content_items`-
rad. `source_template_id`/`source_version` sparas, men bara som spårbar
proveniens — inget läser dem för att visa "det här är en referens till
X" eller för att upptäcka att originalet uppdaterats.

**Konsekvens av nuläget:** om en creator redigerar sin publicerade prompt
efter att någon kopierat den till Valvet, ser kopian aldrig ändringen.
Attribution finns inte heller i kopian — `content_items` har inget fält
som pekar mot `creator_profile_id`.

**Minsta möjliga förändring för en riktig referens** (inte en omskrivning):

1. Lägg till två nullbara kolumner på `content_items`:
   `library_ref_catalog_id uuid references catalog_prompts(id)` (eller
   `catalog_packages`, motsvarande `subject_type`-mönster som
   `creator_shares` redan använder) och behåll `source_template_id` som
   den är (bakåtkompatibelt, ingen migrering av befintliga rader behövs).
2. En ny, tunn RPC `add_catalog_prompt_to_library(p_prompt_id uuid)` som
   **inte** kopierar `prompt_text`/`title` in i `content_items`, utan bara
   sätter `library_ref_catalog_id` och lämnar `content` tomt/null.
   Renderingslagret (webben) läser då live från `catalog_prompts` via
   `library_ref_catalog_id` när det fältet är satt, annars från
   `content_items.content` som idag.
3. Attribution följer automatiskt eftersom `catalog_prompts.creator_profile_id`
   redan finns — ingen ny kolumn behövs för det.

Detta är ett tillägg ovanpå `copy_published_prompt_to_valvet`, inte en
ersättning — "Skapa egen version" (sektion G) fortsätter använda den
kopierande vägen.

---

## G. "Skapa egen version"

**Redan löst, i praktiken.** `copy_published_prompt_to_valvet` /
`copy_template_to_valvet` gör exakt det handover-dokumentet efterfrågar:
en full, redigerbar privat kopia med ursprungsrelation sparad
(`source_template_id`, `source_version`, `source_copied_at`). Användaren
äger kopian direkt och kan redigera den fritt (`vault.js:267-276`, vanlig
update-RPC, ingen spärr mot att ändra en kopierad rad).

Det enda som saknas är att detta idag bara går **från katalog → Valvet**,
inte som ett uttryckligt andra val bredvid en ny "referens"-knapp (sektion
F). Att bygga referens-vägen bredvid gör "Egen version" till det
befintliga kopieringsflödet, oförändrat — inte en ny funktion.

---

## H. Delning

Två separata system finns redan, ingen av dem är riktigt vad handover-
dokumentets exempel beskriver rakt av:

1. **`creator_shares`** (2026-08-25) — token-baserad, tidsbegränsningsbar,
   med statistik och versionslåsning (`content_snapshots`). Byggd för att
   dela **publicerat** creator-innehåll. Detta är den tekniskt mest
   kompletta share-implementationen i hela produkten — token via
   `gen_random_bytes`, dygnsaggregerad anonym statistik, "upphört"-läge
   istället för 404, allt redan i linje med GDPR-hållningen i
   `VISION.md`.
2. **Paket-deep-link** (`?package=<slug>`, `2026-08-11`-specen) — ren
   URL-parameter + `history.pushState`, ingen token, ingen åtkomstkontroll
   (paketet är redan publikt). Löser ett annat problem (delbar länk till
   *publikt* innehåll för SEO/social), inte relevant för privat delning.

**Gap mot handover sektion 6**: att dela ett *opublicerat* utkast privat
("mottagaren kan läsa/använda innehållet" utan att det blir publikt) stöds
inte av något av de två systemen idag — `create_creator_share` kräver
uttryckligen `status = 'published'` och `creator_profile_id`-ägarskap.

**Minsta möjliga förändring**: generalisera `creator_shares` (se sektion
E) att acceptera `subject_type in ('prompt','package','draft_prompt',
'package_draft')` och låta `build_content_payload`/`create_creator_share`
läsa från `content_items`/`creator_package_drafts` när `subject_type` är
ett av de nya värdena, med samma ägarskapskontroll
(`owner_user_id = auth.uid()`) istället för
`creator_profile_id`-kontrollen. Token-, expiry- och statistiklogiken
återanvänds helt oförändrad. Detta är en enda migration, ingen ny tabell.

---

## I. Vad finns redan från Valvet/MCP som kan återanvändas för Connect

Detta är den viktigaste enskilda upptäckten i analysen: **något som
fungerar som Promptbanken Connect finns redan, byggt och i produktion**,
bara inte under det namnet och inte OAuth-baserat.

`mcp_promptbanken`s `/mcp/key`-yta är arkitektoniskt precis det handover-
dokumentet beskriver som Connect:

- Egen endpoint, egen auth-modell (`X-MCP-Key`/`Authorization`-header,
  SHA-256-hashad nyckel som slås upp mot `api_keys.key_hash`), helt skild
  från `/mcp` (Open MCP, ingen auth).
- Exponerar exakt den privata ytan Connect ska ge åtkomst till: egna
  prompts (`list_my_prompts`, `save_workspace_prompt`), Valvet-objekt
  (`list_my_items`/`save_my_item`/`update_my_item`/`archive_my_item`),
  delade arbetsytor (`list_my_shared_workspaces`,
  `list_shared_workspace_prompts`), paketaktivering.
- Bekräftat via tre oberoende källor i koden att detta **inte** är del av
  den frusna `/mcp`-ytan: `mcp-contract.json` sätter dessa verktyg i
  grupper kopplade bara till `free`/`pro`-profilerna (`/mcp/key`), aldrig
  till `public`-profilen (`/mcp`); `_tool_definitions(mcp_key)` filtrerar
  bort dem helt utan nyckel; `tools/call` på `/mcp` avvisar dem explicit
  med JSON-RPC `-32601`.

Den lokala stdio-MCP:n i `promptbanken`-repot (`mcp-server/server/
pro_templates.py`) har samma mönster i miniatyr: en nyckel
(`PROMPTBANKEN_MCP_KEY` env var) hashas och skickas som `p_key_hash` till
samma RPC-familj (`get_workspace_prompts_for_key` m.fl.). Två olika
transportlager (stdio+env var vs. HTTP+header), **samma bakomliggande
auktoriseringsmodell** (nyckelhash mot `api_keys`).

**Vad detta betyder för Connect:** Connect behöver inte en ny
datamodell, inga nya RPC:er för att läsa Mitt bibliotek, och inget nytt
verktygskontrakt för de flesta operationer — `/mcp/key`s tool-set är
redan i praktiken Connects tool-set. Det som saknas är **hur nyckeln
kommer i användarens hand**: idag måste användaren logga in i Valvet-
webben och kopiera en nyckelsträng manuellt in i sin AI-klients config.
Det som gör dagens `/mcp/key` otillräckligt som en riktig
"Connect"-produkt är alltså inte datamodellen eller verktygen, utan
utfärdandeflödet (statisk nyckel, ingen OAuth, ingen enkel
"godkänn i klienten"-upplevelse) — se sektion J.

---

## J. Auth/OAuth för Connect

**Nuläge, exakt:** Supabase Auth används redan fullt ut för
interaktiv inloggning (email/lösenord, Google OAuth, i `valvet_promptbanken/
src/login.js` och `promptbanken`s motsvarande flöden). MCP-åtkomst idag
använder **inte** Supabase-sessioner eller JWT:er — det är en helt separat
mekanism: en statisk, sha256-hashad API-nyckel i `api_keys`-tabellen,
kopplad till ett workspace, aldrig till en inloggad session. Ingen av de
tre trust-modeller `mcp_promptbanken` redan har (nyckelhash-som-bevis,
`platform_owner`-JWT för admin, `mcp_server`-Postgres-rollen för legacy
skills) mintar någonsin en riktig per-användar-Supabase-JWT åt en extern
klient.

**`mcp_promptbanken`s egen uttalade plan** (`DECISIONS.md`, "Endpoint-
strategi inför ChatGPT-publicering") är att lägga OAuth **ovanpå samma
`/mcp`-endpoint**, som en tredje auth-variant bredvid anonym och nyckel,
med motiveringen "endpoints delas per auth-modell, aldrig per feature".

**Denna plan kolliderar delvis med handover-uppdraget**, som uttryckligen
kräver att Connect INTE kopplas till `/mcp` och att `/mcp` 1.2.2 fryses
under pågående granskning. Lösningen är inte att välja bort
`mcp_promptbanken`s princip (den är sund) utan att tillämpa den på rätt
endpoint: en **ny endpoint, `/connect`, med sin egen auth-modell (OAuth)**
— fortfarande "en endpoint per auth-modell", bara att den nya auth-
modellen får en egen endpoint istället för att adderas till `/mcp`. När
1.2.2-granskningen är avgjord kan `mcp_promptbanken`-teamet senare besluta
om `/connect` ska slås samman med `/mcp` som en tredje profil — men det
beslutet ligger uttryckligen utanför detta uppdrag (handover förbjuder att
slå ihop Open MCP och Connect).

**Rekommenderat OAuth-mönster, byggt på det som redan finns:**

1. Supabase stödjer OAuth 2.1/PKCE-flöden för tredjepartsklienter via
   Supabase Auth direkt (inloggningssidan användaren redan har). Ingen
   egen OAuth-server behöver byggas — Supabase Auth *är* redan
   auktoriseringsservern för inloggning.
2. Vid godkännande ("användaren godkänner kopplingen") utfärdas **inte**
   en Supabase-session-token till AI-klienten, utan en ny rad i
   `api_keys` med ett nytt scope, t.ex. `scopes = ['connect']` — samma
   tabell, samma `key_hash`-uppslagsmönster som `/mcp/key` redan
   använder, bara utfärdad via en OAuth-liknande "authorize"-sida istället
   för att användaren kopierar en sträng manuellt.
3. `get_mcp_key_context`-mönstret (redan byggt, `app_private.
   get_mcp_key_context(p_key_hash)`) återanvänds för att slå upp
   workspace/plan från den nya nyckeltypen.
4. Återkallning: redan löst — `api_keys.revoked_at`, samma UI-mönster som
   Valvets nyckelhantering (`vault.js:752`).
5. Scopes: `api_keys.scopes text[]` är redan en array, inte en enum —
   att lägga till `'connect'` som ett nytt scope-värde bredvid `'mcp'` är
   en ren tilläggsförändring, ingen migrering av befintliga nycklar.

Detta ger "riktig OAuth-känsla för användaren" (godkänn i webbläsaren,
ingen manuell nyckelkopiering) utan att bygga en OAuth-server från
grunden och utan att röra `api_keys`- eller RLS-modellen. Den enda nya
komponenten är en auktoriseringssida/-flöde (kan vara en Supabase Edge
Function eller en sida i `promptbanken`-repot) som pratar med Supabase
Auth och sedan skriver till `api_keys` — inget av detta rör
`mcp_promptbanken`s `/mcp`-kod.

---

## K. Open MCP-säkerhet — uttrycklig bekräftelse

**Inget förslag i denna analys kräver någon ändring av Promptbanken Open
MCP 1.2.2.** Konkret, verifierat i koden:

- Open MCP:s kontrakt är exakt de 9 verktygen i `_PUBLIC_OPEN_TOOL_NAMES`
  på `/mcp`, deklarerade i `mcp-contract.json`s `public`-grupp. Ingenting i
  denna analys föreslår att lägga till, ta bort eller byta signatur på
  något av dem.
- Distributionsgaten som redan byggts för creator-innehåll
  (`p_include_creator_content boolean default false` på de fem publika
  läs-RPC:erna) är konstruerad så att `mcp_promptbanken` — som inte
  skickar den nya parametern alls — automatiskt får `false` och därmed
  exakt samma resultat som innan migrationen. Samma default-safe mönster
  är rätt mall för alla framtida ändringar som rör tabeller Open MCP läser.
- Föreslagen Connect-auth (sektion J) är en ny endpoint (`/connect`) och
  ett nytt scope-värde i `api_keys.scopes` — rör varken `/mcp`-koden,
  `mcp-contract.json`s `public`-grupp, eller någon RPC Open MCP anropar.
- Föreslagna ändringar av `creator_shares` (sektion E/H) rör en tabell och
  RPC:er som `mcp_promptbanken` aldrig anropar (grep bekräftar noll
  träffar på `creator_shares`/`get_shared_content` i det repot).
- Föreslagen referensmodell (sektion F) lägger nullbara kolumner till
  `content_items`, en tabell Open MCP inte har åtkomst till (RLS +
  `revoke all ... from anon`) och inte läser.

Om något framtida delprojekt (7: MCP-exponering av creator-innehåll)
skulle kräva ändring av `/mcp`-ytan gäller samma regel som redan står i
`creator-review-flow-design.md`: vänta tills 1.2.2-ansökan är avgjord.
Denna analys föreslår inget som bryter mot det.

---

## L. Minimal väg: konto → Mitt bibliotek → Connect

Kortast möjliga kedja, byggd på det som redan existerar:

1. **Konto** — redan klart. Supabase Auth + `ensure_personal_workspace`
   ger varje ny användare ett personligt workspace automatiskt.
2. **Mitt bibliotek (webb)** — Valvets `vault.js`/`content_items(module=
   'valvet')` är redan "Mitt bibliotek". Det som saknas för att det ska
   *kännas* som en enhetlig yta med Creator är: (a) en synlig knapp "Lägg
   till i mitt bibliotek" på katalogkort i `promptbanken.html` som anropar
   `copy_published_prompt_to_valvet` (finns redan som RPC, saknas som
   knapp i huvudkatalogen — bara Valvet-appen anropar den idag), och (b)
   den nya referens-kolumnen i sektion F om "referens, inte kopia" ska
   vara dag-ett-beteende snarare än en snabb första version med bara
   kopiering.
3. **Delning av privat innehåll** — generalisera `creator_shares` enligt
   sektion H, om det ska ingå i denna leverans (handover sektion 6 nämner
   det som en del av Free-planen).
4. **Connect** — ny endpoint `/connect` i `mcp_promptbanken`, återanvänder
   `/mcp/key`s hela verktygsuppsättning och RPC-lager rakt av, med ett nytt
   scope (`'connect'`) i `api_keys` och en OAuth-liknande
   utfärdandesida enligt sektion J istället för manuell nyckelkopiering.

Steg 2 och 4 kan byggas parallellt (olika repon, ingen delad kod). Steg 3
är fristående och kan skjutas utan att blockera 2 eller 4.

---

## M. Teknisk skuld — vad kan tas bort eller slås ihop

- **`module = 'kommun'` är ett missvisande namn.** Betydelsen är idag
  "Creator-innehåll", inte "kommun-nischat innehåll" — ett kvarblivet namn
  från junis MVP. Att byta värdet kräver en datamigrering (alla befintliga
  rader) plus att uppdatera varje trigger/RPC som refererar strängen
  `'kommun'` — inte gjort i denna analys, men värt en egen, isolerad
  migration någon gång. Ingen brådska: det är bara ett internt
  databasvärde, aldrig exponerat i UI eller API.
- **Två katalogkopieringsvägar i Valvet** (`copy_published_prompt_to_valvet`
  vs. `copy_template_to_valvet`) — den andra är uttryckligen legacy
  (`pro_prompt_templates`), men tas medvetet inte bort eftersom historiska
  kopior pekar dit. Kandidat för pensionering när/om
  `pro_prompt_templates` självt fasas ut.
- **`src/admin.js`** i `promptbanken`-repot är redan bekräftat död kod
  (ersatt av analysskalet `admin.html`, se
  `2026-08-23-creator-review-flow-design.md:38-40`). Kan tas bort helt,
  inget i denna analys eller Connect-arbetet beror på den.
- **"Valvet" som externt produktbegrepp kan försvinna utan omskrivning.**
  All kod, alla tabeller och all UI-logik i `valvet_promptbanken`-repot
  fungerar oavsett vad produkten kallas utåt — "module='valvet'",
  RPC-namnen och webbadressen `valvet.promptbanken.se` är interna
  implementationsdetaljer. Att döpa om produkten till "Mitt bibliotek" i
  marknadsföring/UI-copy (rubriker, knappar, domännamn om så önskas)
  kräver noll ändringar i datamodellen. Detta besvarar handover-frågan
  direkt: **ja, Valvet kan pensioneras som varumärke utan att den
  underliggande implementationen skrivs om.**
- **`pro_prompt_templates`-tabellen** är redan flaggad som medveten
  teknisk skuld i tidigare arbete (2026-08-02-loggen: "rörs INTE,
  medveten teknisk skuld") — orörd även här, av samma skäl.

---

## N. Risker

| Risk | Bedömning |
| --- | --- |
| Öppna MCP 1.2.2 påverkas | **Låg**, se sektion K — inget förslag rör `/mcp`-kod, `mcp-contract.json`s `public`-grupp, eller RPC:er Open MCP anropar. |
| Migrationsrisk vid generalisering av `creator_shares` | **Låg-medel**. Att lägga till nya `subject_type`-värden är additivt (check-constraint-utökning), men `create_creator_share`/`get_shared_content`s logik måste grenas per typ noggrant — samma klass av risk som distributionsgatens "drop function först"-fälla (se `20260823094000`s kommentar om PostgREST-överlagringar), fast för en enklare funktion utan den fällan (`creator_shares`-RPC:erna har inga trailing-default-parametrar att krocka med). |
| RLS/auth-risk i Connect | **Medel om fel mönster väljs.** Om Connect byggs som en ny riktig Supabase-JWT-per-användare-modell (fjärde trust-modellen, som varken `/mcp`, `/mcp/key` eller `/admin` använder idag) måste RLS-policyer skrivas och testas från grunden. Rekommendationen i sektion J (återanvänd `api_keys`-nyckelhash-mönstret) undviker detta genom att luta sig mot samma väl testade modell `/mcp/key` redan kör i produktion. |
| Bakåtkompatibilitet för befintliga Valvet-kopior | **Låg.** Referensmodellen i sektion F är additiv (nya nullbara kolumner) — befintliga `content_items`-rader med bakad `content` fortsätter fungera exakt som idag. |
| Dataduplicering | **Redan hanterad** för Creator/Valvet (sektion D). Ny duplicering kan uppstå om referens-vägen (F) byggs som ännu en kopieringsfunktion istället för en riktig referens — håll disciplinen att `library_ref_catalog_id`-vägen aldrig bakar in `prompt_text`. |
| Delningssäkerhet | **Låg för det som redan finns** (`creator_shares` har redan token via `gen_random_bytes`, ingen enumererbar räkneföljd, aldrig läcker "fanns aldrig" vs. "har gått ut"). Om privat-utkast-delning (H) byggs: säkerställ att ägarskapskontrollen byts från `creator_profile_id`-koppling till `owner_user_id = auth.uid()` konsekvent — annars kan en creator av misstag dela innehåll de inte äger. |
| MCP-auth-risk | **Medel.** `mcp_promptbanken`s egen plan (OAuth på `/mcp`) och detta uppdrags krav (Connect separat) drar åt olika håll — se sektion J. Om ett framtida beslut ändå slår ihop dem måste det ske efter 1.2.2-granskningen, aldrig under. |
| Beroenden mellan repon | **Känt och redan hanterat mönster.** Alla tre repon delar ett Supabase-projekt; `mcp_promptbanken`s `CLAUDE.md` dokumenterar redan att migrationer i `promptbanken`-repot är auktoritativa och att den lokala kopian i `mcp_promptbanken/supabase/migrations` inte är det — samma disciplin gäller för alla nya migrationer denna analys föreslår. |

---

## O. Rekommenderad stegordning

1. **Publicera "Lägg till i mitt bibliotek"-knappen i huvudkatalogen**
   (ren UI-koppling till redan existerande
   `copy_published_prompt_to_valvet`-RPC) — ingen migration, snabbast
   sätt att koppla ihop Creator/katalog och Valvet synligt för användaren.
2. **Bygg referensmodellen** (sektion F): två nya kolumner på
   `content_items`, en ny tunn RPC, rendera-logik i webben som väljer
   live-läsning vs. bakad text.
3. **Generalisera `creator_shares`** till att omfatta opublicerat eget
   innehåll (sektion H/E) — en migration, återanvänder allt annat
   oförändrat.
4. **Länka `creator-shares.html` i Creator-navigationen** — filen finns
   redan (se sektion C), bara inte länkad.
5. **Bygg Connect-auktoriseringsflödet** (sektion J): nytt `'connect'`-
   scope i `api_keys`, en auktoriseringssida som pratar med Supabase Auth,
   ingen ändring i `mcp_promptbanken`s `/mcp`-kod.
6. **Bygg `/connect`-endpointen i `mcp_promptbanken`**, som en ren kopia
   av `/mcp/key`s tool-dispatch pekad mot det nya scopet — parallellt med
   steg 5, i det repot, av det repots ägare.
7. **Verifiera Open MCP 1.2.2 oförändrad** efter varje steg ovan, med
   `promptbanken-mcp-contract-test`-skillen mot produktion, innan nästa
   steg påbörjas.

Organisationslagret (framtida) kräver inga förberedande ändringar utöver
det som redan finns i rollhierarkin och `workspaces.type = 'organization'`
— korrekt enligt handover sektion 14, ingen åtgärd nu.
