# Creator-authoring med attribution och återanvändningsstyrning — design

Datum: 2026-08-18
Status: godkänd, redo för implementationsplan

## Syfte

Ge en publicerad creator (se [[2026-08-16-creator-profiler-design]]) ett
eget skrivyta för att skapa och skicka in enskilda prompts och paket av
egna prompts, med två explicita samtycken per prompt: att den delas i
öppna Promptbanken, och att andra creators får återanvända den i sina
egna paket. Inskickat innehåll blir aldrig publikt automatiskt — det
hamnar i granskningsläge och väntar på ett redaktionellt godkännande
(delprojekt 4, inte byggt än).

## Sammanhang: delprojekt 3 av 7

1. ~~SEO + paketförst-IA~~ — levererad 2026-08-15
2. ~~Creator-profiler~~ — levererad 2026-08-18
3. **Creator-authoring med attribution och återanvändningsstyrning** ← denna spec
4. Redaktionellt granskningsflöde
5. Kreditledger (Workshopkrediter)
6. Workshop-datamodell
7. MCP-exponering av godkänt creator-innehåll

Uttryckligt avgränsat i denna spec (avstämt med Peter 2026-08-18):
- **Ingen peer-till-peer-bläddring.** En creator kan återanvända en annan
  creators prompt i sitt eget paket bara om den redan är `published` och
  har `creator_consent_reusable = true` — men det finns inget UI för att
  söka/bläddra bland andras godkända prompts i denna leverans. Rättigheten
  (RPC-nivå) byggs nu; bläddra-UI:t hör hemma efter delprojekt 4, när det
  faktiskt finns publicerat innehåll att återanvända.
- **Ingen redaktionell granskningsvy.** Att gå från `review` till
  `published` görs manuellt av platform_owner (SQL/admin-MCP), precis som
  idag. Delprojekt 4 bygger den riktiga adminvyn.
- **Ingen ändring av Free-planens 3-prompt-tak.** Creator-inskickade
  prompts räknas mot samma befintliga gräns som övriga arbetsyteprompts.
  Ingen ny kvotmodell för enskilda prompts i denna leverans.

## Nuvarande arkitektur (referens)

- `content_items` (Supabase, arbetsytemodellen) har redan `owner_user_id`,
  `workspace_id`, `status` (`draft|review|published|archived`),
  `visibility` (`public|workspace|private`), samt proveniensfälten
  `source_template_id`/`source_version`/`source_copied_at` som redan
  används för att kopiera admin-godkänt innehåll in i `catalog_prompts`.
  Samma kopieringsmönster återanvänds här — inget nytt att uppfinna för
  hur "godkänt utkast blir katalogpost".
- `catalog_prompts`/`catalog_packages` är adminets globala,
  presentationstunga tabeller (ikon, bild, färgtema) — inte lämpliga att
  skriva direkt till från en creator; de fylls av godkännandesteget
  (delprojekt 4), inte av denna spec.
- Personliga arbetsytor (Free-plan) skapas redan automatiskt vid
  registrering och har redan RLS på `owner_user_id`/`workspace_id`.
- `creator_profiles` (från delprojekt 2) har `status`, `slug`, och
  RPC-mönstret `get_my_*`/`upsert_my_*`/`publish_my_*` som denna spec
  följer för konsekvens.

## Scope

Ingår:
- Två nya kolumner på `content_items`: `creator_consent_shared boolean
  not null default false`, `creator_consent_reusable boolean not null
  default false`.
- RPC:er för att skicka in/dra tillbaka en egen prompt för granskning.
- Ny tabell `creator_package_drafts` (paket-utkast, ägs av en creator)
  och `creator_package_items` (ordnad lista av egna content_item-id:n i
  ett utkast, max 8 per utkast).
- RPC:er för att skapa/redigera paket-utkast, lägga till/ta bort/ordna
  prompts i utkastet, och skicka in/dra tillbaka utkastet för granskning.
- Kvot: max 3 `creator_package_drafts` med `status = 'review'` samtidigt
  per creator. Publicerade paket räknas inte mot gränsen. Antal utkast
  totalt är obegränsat.
- Två nya sidor i appen: `creator-content.html` (mina prompts) och
  `creator-packages.html` (mina paket), länkade från `creator.html`.
- SQL-testfiler för kvot, samtyckestvång och RLS.

Ingår inte (framtida delprojekt, se ovan):
- Bläddra-UI för andras återanvändningsbara prompts.
- Redaktionell granskningsvy/adminflöde för att godkänna/avslå.
- Ny kvotmodell för enskilda prompts (Free-taket på 3 gäller oförändrat).
- Kreditledger / Workshopkrediter-koppling.

## Datamodell

### `content_items` — två nya kolumner

```sql
alter table public.content_items
    add column creator_consent_shared boolean not null default false,
    add column creator_consent_reusable boolean not null default false;
```

En creator-inskickad prompt är en vanlig `content_items`-rad i
creatorns personliga arbetsyta: `status = 'review'`,
`visibility = 'public'`, samtyckesfälten satta av RPC:n (aldrig direkt av
klienten).

### `creator_package_drafts`

| Kolumn | Typ | Anmärkning |
|---|---|---|
| `id` | uuid, pk | |
| `owner_user_id` | uuid, not null | RLS-nyckel |
| `title` | text, not null | |
| `summary` | text | |
| `status` | text, check in (`draft`,`review`,`published`,`archived`) | samma vokabulär som `content_status` |
| `created_at` / `updated_at` | timestamptz | |

### `creator_package_items`

| Kolumn | Typ | Anmärkning |
|---|---|---|
| `draft_id` | uuid, fk → `creator_package_drafts.id` | |
| `content_item_id` | uuid, fk → `content_items.id` | |
| `position` | int, not null | ordning i paketet |

Unik `(draft_id, content_item_id)` — samma prompt kan inte läggas till
två gånger i samma paket, men får ingå i flera olika paket (egna eller,
efter godkännande och med `creator_consent_reusable = true`, andras).
Max 8 rader per `draft_id`, kontrollerat i RPC:n (inte en DB-constraint,
eftersom det är en affärsregel som kan behöva ändras).

RLS: `creator_package_drafts` och `creator_package_items` läsbara/
skrivbara bara av `owner_user_id = auth.uid()` (items via join mot
draften). Admin-läsning för granskning byggs i delprojekt 4.

## RPC:er

Prompts (utökar befintligt, ingen ny skriv-RPC för själva innehållet —
arbetsytans vanliga create/edit-RPC:er återanvänds oförändrade):

- `submit_creator_prompt(p_content_item_id uuid, p_consent_shared
  boolean, p_consent_reusable boolean)` — kräver
  `p_consent_shared = true`, annars fel. Kräver att anropande användare
  äger raden. Sätter `status = 'review'`, `visibility = 'public'`,
  skriver samtyckena. Idempotent om redan i review.
- `withdraw_creator_prompt(p_content_item_id uuid)` — tillbaka till
  `status = 'draft'`, `visibility = 'private'`. Vägrar om `status =
  'published'` (kan inte dra tillbaka publicerat innehåll härifrån —
  det hör till delprojekt 4:s avpublicera-flöde).

Paket:

- `upsert_creator_package_draft(p_draft_id uuid default null, p_title
  text, p_summary text default null)` — skapar om `p_draft_id` är null,
  annars uppdaterar. Kräver ägarskap vid uppdatering.
- `add_prompt_to_package_draft(p_draft_id uuid, p_content_item_id uuid,
  p_position int)` — kräver ägarskap av draften. `content_item_id`
  måste antingen ägas av samma användare, eller ha `status = 'published'`
  och `creator_consent_reusable = true`. Vägrar vid 8 rader i draften.
- `remove_prompt_from_package_draft(p_draft_id uuid, p_content_item_id
  uuid)`.
- `reorder_package_draft_items(p_draft_id uuid, p_ordered_ids uuid[])`.
- `submit_creator_package_draft(p_draft_id uuid)` — sätter `status =
  'review'`. Vägrar om: draften har 0 prompts, eller creatorn redan har
  3 drafts med `status = 'review'`.
- `withdraw_creator_package_draft(p_draft_id uuid)` — tillbaka till
  `draft`. Vägrar om `status = 'published'`.
- `list_my_creator_prompts()` — egna `content_items` av typ `prompt`,
  alla statusar, för `creator-content.html`.
- `list_my_creator_package_drafts()` — egna paket-utkast med sina items,
  för `creator-packages.html`.

Alla nya RPC:er `security definer`, `set search_path = ''`, gated på
`auth.uid()`, samma stil som `creator_profiles`-RPC:erna.

## UI / flöde

- `creator.html` får en ny sektion "Mina prompts och paket" med länkar
  till de två nya sidorna (ersätter dagens statiska nollägestexter för
  "Publicerade paket"/"Publicerade prompts" — de blir riktiga länkar när
  creatorn har innehåll, annars kvar som nolläge).
- **`creator-content.html`**: lista egna prompts (alla statusar, med
  statusbadge Utkast/Under granskning/Publicerad/Arkiverad — samma ord
  som `content_status`). "Ny prompt" öppnar arbetsytans befintliga
  create-formulär. Varje rad i draft-läge har "Skicka in för
  granskning": kryssruta "Jag godkänner att prompten delas i öppna
  Promptbanken" (krävs) + kryssruta "Andra creators får återanvända den
  i sina paket" (valfri). Knappen inaktiv tills obligatorisk kryssruta
  är ikryssad — inget serveranrop för det fallet.
- **`creator-packages.html`**: lista egna paket-utkast med statusbadge.
  "Nytt paket" → titel + summary. Paketbyggare: lägg till bland egna
  `published`/`review`/`draft`-prompts (inga andras — bläddra-UI är
  framtida arbete), ordna med upp/ner, räknare "X/8". "Lägg till"
  inaktiveras vid 8. UI-hint (icke-blockerande): "3–6 prompts brukar
  vara ett lagom paket" när antalet är utanför det intervallet.
  "Skicka in för granskning" visar tydligt fel om 3-i-review-taket är
  nått, med vägledning ("dra tillbaka eller vänta på granskning av ett
  annat paket").

## Felhantering

- Samtycke ej ikryssat → knapp inaktiv, klientvalidering, inget
  serverfel i normalfallet.
- 3-i-review-tak (paket) → RPC kastar svenskt fel, visas som text
  ovanför knappen, samma mönster som befintliga RPC-fel i
  `creatorProfile.js`.
- 8-prompts-tak → "Lägg till" inaktiveras i UI vid 8; RPC:n validerar
  ändå (klienten är inte att lita på för affärsregler).
- Försök återanvända en annans icke-publicerade eller icke-reusable
  prompt → RPC:n vägrar med tydligt fel; UI:t visar bara egna prompts
  som valbara i paketbyggaren så detta felfall är i praktiken bara ett
  serverskydd, inte en normal UI-väg.
- Dra tillbaka publicerat innehåll → vägras med förklaring, hänvisar
  till att avpublicering hör till granskningsflödet (delprojekt 4).

## Testning

- Nya SQL-testfiler i `supabase/tests/` (samma mönster som befintliga):
  - samtyckestvång vid `submit_creator_prompt`,
  - 8-prompts-taket och 3-i-review-taket i paket-RPC:erna,
  - RLS: en användare kan inte läsa/skriva en annan användares
    content_items, package draft eller package items,
  - återanvändning: `add_prompt_to_package_draft` med en annans
    `published` + `creator_consent_reusable = true`-prompt lyckas; med
    `creator_consent_reusable = false` eller `status != 'published'`
    vägras det.
- Manuell browser-verifiering av `creator-content.html` och
  `creator-packages.html`, samma nivå som `creator.html` redan har
  (ingen automatiserad UI-testsvit finns för appsidor idag).

## Självgranskning

- Inga TBD/placeholders kvar.
- Konsekvent med [[2026-08-16-creator-profiler-design]]: samma RPC-namn-
  konvention (`get_my_*`/`list_my_*`/`upsert_my_*`/`submit_*`/
  `withdraw_*`), samma statusvokabulär, samma RLS-mönster.
- Scope är avgränsat till en enda implementationsplan (data + RPC + två
  sidor) — inte uppdelat ytterligare.
- Öppen fråga för Peter, inte blockerande: paket-i-review-taket (3) är
  satt "för Free Creator" i den ursprungliga diskussionen — om ett
  framtida betalt creator-tier ska ha en annan gräns är inte beslutat
  här. Denna spec implementerar bara 3 som en enda global gräns; en
  tier-differentierad gräns är en enkel senare ändring (ett tal i en
  RPC), inte en omdesign.
