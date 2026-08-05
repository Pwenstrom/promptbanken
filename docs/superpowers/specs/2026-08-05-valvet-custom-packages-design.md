# Design: Valvet egna promptpaket (`create_custom_package`)

## Bakgrund

Ett live ChatGPT-test mot Valvet Pro (2026-08-04) visade att det inte finns
något sätt att bunta ihop flera egna sparade prompts till en namngiven,
ordnad enhet. Testaren löste det provisoriskt genom att klistra in sju
delprompts som text i ett enda `type='assistant'`-objekt — fungerande, men
strukturlöst (ingen egen ordning, ingen koppling till originalprompterna,
ingen möjlighet att uppdatera en delprompt utan att redigera hela
klumptexten).

Detta är en riktig produktlucka, inte en bugg. Se även den separata,
redan fixade buggen i `save_prompt_for_key`
(`20260805100000_fix_save_prompt_for_key_status.sql`), som är orelaterad.

## Scope

Rent privat gruppering inom en enskild användares Valvet. Ingen delning,
ingen koppling till Promptbankens admin-kuraterade katalog
(`catalog_packages`) — de är och förblir separata system.

**Uttryckligen utanför scope:** Valvet team-/org-delning. Valvets
läs/skriv-vägar (webb och MCP, `vault.py` + tillhörande RPC:er) är idag
hårdkodade till anroparens personliga workspace/`owner_user_id`, till
skillnad från Promptbankens redan byggda org-workspaces
(`list_my_shared_workspaces`/`list_shared_workspace_prompts`, ett separat
innehållsområde). Att låta flera medlemmar i ett team se och redigera
samma Valvet-paket är en egen, större förändring av hela Valvets
ägarskapsmodell — inte något denna spec bygger. Detta paket-schema är
dock medvetet **workspace_id-skopat, inte `owner_user_id`-skopat** (se
Datamodell) just för att en sådan framtida migration ska kunna lägga till
delning utan att rita om paket-tabellerna. Det ändrar inget beteende idag
— personliga workspaces har bara en ägare, så resultatet är identiskt med
strikt privat.

## Datamodell

`content_item_type` (enum) utökas med ett tredje värde `'package'`, samma
mönster som när `'assistant'` lades till (`20260716100000_valvet_module_and_write_log.sql`).
Ett paket är en vanlig `content_items`-rad: `module='valvet'`,
`type='package'`, `visibility='private'`. `content`-fältet (not null) bär
en kort beskrivning/introtext för paketet, inte konkatenerad prompttext.

Ny tabell för medlemskap och ordning:

```sql
create table public.valvet_package_items (
    package_id uuid not null references public.content_items(id) on delete cascade,
    member_id  uuid not null references public.content_items(id) on delete cascade,
    sort_order integer not null,
    primary key (package_id, member_id)
);
```

- `on delete cascade` på båda kolumnerna: raderas paketet försvinner
  kopplingarna; raderas en medlemspost (hård delete, sker inte via
  nuvarande MCP-verktyg men är möjligt via direkt databasåtkomst)
  försvinner den ur paketet automatiskt utan att lämna en trasig referens.
- **Arkivering är INTE radering.** `archive_my_item` sätter bara
  `status='archived'` — en arkiverad medlemsprompt stannar kvar i
  `valvet_package_items` (raden är inte borttagen ur `content_items`).
  `get_my_package` filtrerar bort arkiverade medlemmar ur den expanderade
  listan (visar dem inte), men själva kopplingsraden ligger kvar orörd —
  om prompten återställs (`archive_my_item ... restore=true`) dyker den
  upp i paketet igen automatiskt, utan att någon behövde lägga till den på
  nytt.
- Ägarskapskontroll sker via `workspace_id` på `content_items`-raderna
  (paket och medlemmar måste tillhöra samma workspace som nyckelns
  anropare), inte via en hårdkodad `owner_user_id`-jämförelse — se Scope.

## Nya RPC:er och MCP-verktyg

Samma säkerhetsmönster som befintliga Valvet-RPC:er (nyckelhash-baserad
verifiering, workspace-koll, `security definer`), se
`app_private.save_my_item`/`archive_my_item` som referens.

### `create_custom_package(title, description, category, prompt_ids[])`

- Validerar: `prompt_ids` är inte tom; varje id finns i `content_items`,
  tillhör anroparens workspace, `module='valvet'`, `status <> 'archived'`.
- Ett ogiltigt eller främmande id i listan avvisar HELA anropet (inget
  tyst partiellt paket) — felmeddelandet anger vilket id som var
  problemet.
- Skapar paket-raden (`type='package'`) och samtliga
  `valvet_package_items`-rader i en transaktion; `sort_order` följer
  ordningen i `prompt_ids`.
- Returnerar paket-raden (samma form som `save_my_item` returnerar sin
  rad).

### `get_my_package(id)`

- Hämtar paket-raden (404-liknande fel om id inte finns, inte tillhör
  anroparens workspace, eller inte är `type='package'` — samma mönster
  `get_my_item` redan har för fel typ).
- Expanderar medlemmarna i `sort_order`, med icke-arkiverade prompts
  fullt utfyllda (id, title, content, category) — samma platta form som
  Promptbankens `list_package_prompts` redan returnerar, för att hålla
  klientsidans parsing bekant.

### `update_my_package_items(id, prompt_ids[])`

- Ersätter HELA medlemslistan atomärt (ta bort alla existerande
  `valvet_package_items`-rader för paketet, sätt in de nya) — enklare
  kontrakt än add/remove-par, matchar hur `update_my_item` redan ersätter
  hela fält snarare än att patcha delvis.
- Samma valideringsregler som `create_custom_package` för den nya listan.
- Titel/beskrivning/kategori uppdateras separat via befintlig
  `update_my_item` (paketet är trots allt bara en `content_items`-rad) —
  inget nytt verktyg behövs för det.

### Inga nya list/sök-verktyg

Paket är bara `type='package'` och dyker upp automatiskt i
`list_my_items`/`search_my_items` (redan filtrerbara på `type`). Ingen
ändring behövs i dessa.

### Arkivering

`archive_my_item` fungerar direkt utan ändring — paketet är en vanlig
`content_items`-rad. Arkivering av paketet lämnar
`valvet_package_items`-raderna orörda (samma "arkivering ≠ radering"-
princip som ovan); om paketet återställs är medlemslistan intakt.

## Felhantering (sammanfattning)

| Situation | Beteende |
|---|---|
| Tom `prompt_ids[]` | Avvisas: "Ett paket behöver minst en prompt." |
| Id som inte finns / fel workspace / arkiverad | Avvisas, hela anropet, med vilket id som orsakade felet |
| `get_my_package`/`update_my_package_items` på ett id som inte är `type='package'` | Samma "hittades inte"-fel som `get_my_item` ger för fel typ |
| Medlem arkiveras efter paketet skapats | Kopplingen finns kvar, medlemmen döljs i `get_my_package`, återkommer om den återställs |

## Test

Manuellt testskript i samma stil som
`supabase/tests/verify_copy_published_prompt_to_valvet.sql`:

1. Skapa ett paket med 3 befintliga prompts, verifiera ordning i
   `get_my_package`.
2. Försök skapa ett paket med ett id från en annan workspace — ska
   avvisas.
3. Försök skapa ett paket med tom `prompt_ids[]` — ska avvisas.
4. `update_my_package_items` med en ny lista — verifiera att gamla
   kopplingar är borta och nya finns.
5. Arkivera en medlemsprompt — verifiera att den försvinner ur
   `get_my_package` men att paketet i övrigt är intakt.
6. Återställ samma prompt (`restore=true`) — verifiera att den dyker upp
   i paketet igen utan ny `update_my_package_items`-anrop.
7. Arkivera paketet självt — verifiera att `list_my_items` inte längre
   visar det (standardbeteende, samma som andra items), men att
   `valvet_package_items`-raderna ligger kvar orörda i databasen.

## Ej byggt i denna spec (medvetet uppskjutet)

- Delning av paket till andra medlemmar i ett team/org-workspace (kräver
  att hela Valvets ägarskapsmodell ses över, egen framtida spec).
- Koppling mellan användarskapade paket och Promptbankens
  admin-kuraterade `catalog_packages` (separata system, ska förbli det).
- Nästlade paket (paket som innehåller andra paket) — inte efterfrågat,
  YAGNI.
