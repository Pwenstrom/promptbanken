# Redaktionellt granskningsflöde för creator-innehåll — design

Datum: 2026-08-23
Status: godkänd, redo för implementationsplan

## Syfte

Ge Promptbanken ett säkert publiceringsflöde för creator-inskickat
innehåll. En creator skickar in prompts och paket (byggt i delprojekt 3).
Innehållet förgranskas automatiskt mot Promptbankens publiceringsregler
och kräver därefter *alltid* ett mänskligt godkännande innan det
publiceras.

Godkänt innehåll publiceras i webbkatalogen med creator-attribution. Det
exponeras via Promptbanken Open/MCP först när creatorn uttryckligen
samtyckt till distribution och rättighetsläget är intygat. Tills dessa
villkor är fullt implementerade filtreras creator-innehåll bort från
Open/MCP.

## Sammanhang: delprojekt 4 av 7

1. ~~SEO + paketförst-IA~~ — levererad 2026-08-15
2. ~~Creator-profiler~~ — levererad 2026-08-18
3. ~~Creator-authoring med attribution och återanvändningsstyrning~~ —
   levererad 2026-08-21
4. **Redaktionellt granskningsflöde** ← denna spec
5. Kreditledger (Workshopkrediter)
6. Workshop-datamodell
7. MCP-exponering av godkänt creator-innehåll

Delprojekt 3 lämnade kedjan bruten efter inskicket: `submit_creator_prompt`
och `submit_creator_package_draft` sätter `status = 'review'`, men ingen
adminyta läser det. `src/admin.js` filtrerar `content_items` på
`.eq('workspace_id', state.workspace.id)`, så en creators personliga
arbetsyta är osynlig för plattformsägaren. Denna spec stänger glappet.

## Nuvarande arkitektur (referens)

- `content_items` har `status` (`draft|review|published|archived`),
  `review_note`, samt `creator_consent_shared` och
  `creator_consent_reusable` från delprojekt 3.
- `creator_package_drafts` + `creator_package_items` håller paket-utkast,
  max 8 prompts per utkast, max 3 samtidiga i `review` per creator.
- Katalogen är variantbaserad: `catalog_prompts` +
  `catalog_prompt_variants(context_key)`. Presentationsfälten (`icon_key`,
  `image_key`, `color_theme`) bor på huvudraden, texten i varianten.
  Motsvarande för `catalog_packages`/`catalog_package_variants`/
  `catalog_package_items`.
- Skrivning till katalogen sker redan via platform_owner-gatade RPC:er:
  `create_catalog_prompt`, `upsert_catalog_prompt_variant`,
  `publish_catalog_prompt`, `create_catalog_package`,
  `add_prompt_to_catalog_package`, `publish_catalog_package`.
- `creator_profiles` (delprojekt 2) har `id`, `user_id` (unik),
  `slug`, `display_name`, `status`.
- Webben (`script.js`, `promptbanken.html`,
  `scripts/generate-catalog-pages.mjs`) och den hostade MCP:n i repot
  `mcp_promptbanken` läser **samma** publika RPC:er:
  `list_published_prompts`, `get_published_prompt`,
  `list_published_packages`, `get_published_package`,
  `list_published_package_prompts`.
- Katalogens storlek i produktion 2026-08-23: 102 publicerade prompts,
  17 publicerade paket. Det är litet nog att hela titel- och
  sammanfattningslistan får plats i en modellkontext.
- Supabase Edge Functions används redan (`supabase/functions/delete-account`)
  med service-role-mönstret. Ingen Anthropic-integration finns i repot idag.

## Scope

Ingår:

- AI-förgranskning av inskickade prompts och paket-utkast, körd på
  begäran från granskningsvyn, med verdikt Grön/Gul/Röd, korta fynd och
  ett förslag på återkoppling till creatorn.
- Publiceringsregler som versionshanterad markdown i repot.
- Granskningsvy som ny flik i `admin.html`, med Godkänn, Begär ändring
  och Avslå.
- Attribution på `catalog_prompts` och `catalog_packages`, med två
  distributionsvillkor kopierade in vid godkännande.
- Distributionsgate som utesluter creator-innehåll ur Open/MCP.
- `review_note` synlig för creatorn i `creator-content.html`.
- Riktiga listor på den publika creator-sidan istället för nolläge.
- SQL-tester för behörighet, gate och attributionskopiering.

Ingår inte:

- Faktisk MCP-exponering av creator-innehåll (delprojekt 7). Denna spec
  bygger gaten och villkorsfälten, men flippar dem aldrig till öppet.
- Bläddra-UI för andras återanvändningsbara prompts.
- Kreditledger / Workshopkrediter.
- Automatiskt publiceringsbeslut av något slag.

## Grundprincip: AI:n får inte publicera

Förgranskningen är rådgivande. Den skrivs som en behörighetsgräns, inte
som en instruktion i en prompt:

Edge-funktionen som anropar modellen har **ingen** skrivrättighet till
`content_items`, `creator_package_drafts` eller `catalog_*`. Den får
skriva i exakt en tabell — `creator_submission_screenings` — och läsa det
den ska bedöma. Även en fullständigt kapad modellprompt kan därmed inte
publicera, avslå eller ändra status på något. Statusövergångarna sker
uteslutande i RPC:er som kräver en inloggad `platform_owner`.

## Datamodell

### Nya samtyckesfält

Dagens `creator_consent_shared` betyder "får delas i öppna Promptbanken"
och täcker inte vidaredistribution till tredjepartsklienter som ChatGPT.
Två nya fält, på både `content_items` och `creator_package_drafts`:

```sql
alter table public.content_items
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false;

alter table public.creator_package_drafts
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false;
```

- `creator_consent_distribution` — creatorn godkänner att innehållet
  distribueras via Promptbanken Open/MCP till externa AI-klienter.
- `creator_rights_attested` — creatorn intygar att innehållet är eget
  eller att hen har rätt att sprida det.

Båda är frivilliga vid inskick. Saknas de kan innehållet fortfarande
godkännas och publiceras på webben — det kan bara aldrig nå Open/MCP.
`creator_consent_shared` förblir tvingande för inskick, oförändrat.

### Granskningsresultat

```sql
create table if not exists public.creator_submission_screenings (
    id uuid primary key default gen_random_uuid(),
    subject_type text not null check (subject_type in ('prompt', 'package')),
    subject_id uuid not null,
    verdict text not null check (verdict in ('gron', 'gul', 'rod')),
    findings jsonb not null default '[]'::jsonb,
    suggested_feedback text,
    rules_version text not null,
    model text not null,
    created_by uuid not null references auth.users(id),
    created_at timestamptz not null default now()
);

create index if not exists creator_submission_screenings_subject_idx
    on public.creator_submission_screenings (subject_type, subject_id, created_at desc);
```

Append-only. Ingen `update`- eller `delete`-policy. Adminvyn visar senaste
raden per post; historiken finns kvar så det går att se om en creator
förbättrat innehållet mellan två körningar.

`subject_id` har medvetet ingen foreign key — den pekar på antingen
`content_items` eller `creator_package_drafts` beroende på `subject_type`.
Alternativet, två nullbara FK-kolumner med check-villkor, ger en styvare
tabell utan att lösa något verkligt problem här; granskningshistoriken ska
överleva att ett utkast raderas.

`findings` är en lista av objekt:

```json
[{"kategori": "risk", "allvarlighet": "hog", "text": "Prompten ber om personnummer."}]
```

Kategorier: `regelverk`, `kvalitet`, `risk`, `rattigheter`, `dublett`.
Allvarlighet: `hog`, `medel`, `lag`.

### Attribution i katalogen

```sql
alter table public.catalog_prompts
    add column if not exists creator_profile_id uuid references public.creator_profiles(id) on delete set null,
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false;
```

Samma tre kolumner på `catalog_packages`.

Villkorsflaggorna kopieras in från källan vid godkännande istället för att
läsas via join. Motivet: katalograden ska bära sitt eget bevis för att den
får distribueras. En creator som i efterhand ändrar sig i sin arbetsyta
ska inte tyst ändra distributionsläget för redan publicerat innehåll —
det ska kräva ett aktivt beslut i granskningsvyn.

`on delete set null` gör att en raderad creator-profil avattribuerar
katalogposten men aldrig raderar publicerat innehåll.

## Publiceringsreglerna

`docs/creator-publiceringsregler.md`, versionshanterad i git och inbakad i
edge-funktionens bundle vid deploy. Filen inleds med en rad
`<!-- version: 2026-08-23.1 -->` som funktionen läser ut och skriver till
`rules_version` på varje granskningsrad. Utan den går gamla omdömen inte
att tolka när reglerna ändrats.

Reglerna täcker fem områden, samma som granskningens fyndkategorier:
publiceringsregler (form, språk, struktur), kvalitet (är prompten
användbar och konkret), risker (personuppgifter, myndighetsutövning,
medicinska eller juridiska råd), rättigheter (upphovsrätt, igenkännbara
tredjepartskällor) och dubletter mot befintlig katalog.

## AI-förgranskningen

Ny edge function `supabase/functions/screen-creator-submission`.

Anrop: `POST` med `{ subject_type, subject_id }` och admins JWT.

Flöde:

1. Verifiera JWT och att användaren är `platform_owner`. Annars 403.
2. Hämta innehållet — prompttext, titel, sammanfattning, och för paket
   även samtliga ingående prompters titel och text i ordning.
3. Hämta katalogens jämförelselista: `slug`, titel och sammanfattning för
   alla publicerade prompts respektive paket. Vid dagens 102 poster blir
   det cirka 4 000 tokens. Passerar katalogen ~500 poster måste detta
   ersättas av en kandidatsökning; det är den enda delen av designen som
   inte skalar rakt av.
4. Läs den inbakade regel-markdownen och dess versionsrad.
5. Anropa `claude-sonnet-5` med regelverket, innehållet och
   jämförelselistan. Modellvalet motiveras av att felbedömningar här
   kostar adminstid eller släpper igenom fel innehåll, medan volymen är
   låg — granskning sker på begäran, inte per inskick.
6. Skriv resultatet till `creator_submission_screenings` och returnera det.

Två promptmallar, en per `subject_type`. Paketmallen bedömer helheten:
hänger prompterna ihop, är ordningen logisk, överlappar de varandra,
motsvarar titel och sammanfattning innehållet.

Modellsvaret begärs som JSON via `tool_use` med ett fast schema, inte som
fritext. Går svaret ändå inte att tolka skrivs ingen granskningsrad, och
funktionen returnerar ett fel som visas i adminvyn — aldrig ett tomt eller
gissat verdikt.

`ANTHROPIC_API_KEY` sätts som Supabase-secret. Den får inte hamna i repot
eller i någon frontend-bundle.

## Granskningsvyn

Ny flik i `admin.html`, med logiken i en egen modul `src/adminCreatorReview.js`.
`src/admin.js` är redan omkring 2 800 rader; granskningsflödet läggs inte
där. Fliken registreras i `admin.js` men implementeras i den nya modulen.

Vyn listar prompts i `review` och paket-utkast i `review`, över
arbetsytegränsen, med senaste verdikt som färgmarkering. Öppnad post visar
full text, samtyckesflaggornas läge, granskningsfynden och tre knappar:

- **Kör granskning** — anropar edge-funktionen, uppdaterar vyn.
- **Godkänn** — skapar katalogutkast med attribution.
- **Begär ändring** — textfält förifyllt med AI:ns förslag, redigerbart.
- **Avslå** — samma textfält, arkiverar posten.

Förslaget till återkoppling är alltid redigerbart och skickas aldrig
automatiskt. Ingen knapp aktiveras av ett verdikt; ett rött omdöme
blockerar inte godkännande och ett grönt utlöser inte publicering.

## RPC:erna

Alla kräver `platform_owner`, alla följer repots mönster med
`app_private`-implementation och `public`-wrapper, `revoke all ... from
public`, `grant execute ... to authenticated`, svenska felmeddelanden.

- `list_creator_submissions()` — prompts i `review` med
  `creator_consent_shared = true`, plus paket-utkast i `review`, oavsett
  arbetsyta, med creatorns visningsnamn och senaste verdikt.
- `get_creator_submission(p_subject_type text, p_subject_id uuid)` — full
  text, samtyckesflaggor och granskningshistorik.
- `approve_creator_prompt(p_content_item_id uuid, p_slug text, p_icon_key text, p_color_theme text)`
  — skapar `catalog_prompts` i `draft` med en `generell`-variant från
  creatorns text, sätter `creator_profile_id` och kopierar
  distributionsflaggorna, och sätter `content_items.status = 'published'`.
- `approve_creator_package(p_draft_id uuid, p_slug text, p_icon_key text, p_color_theme text)`
  — motsvarande för `catalog_packages`, med `catalog_package_items` i
  utkastets ordning. Kräver att varje ingående prompt redan har en
  katalogpost, annars fel med tydlig text om vilken som saknas.
- `request_changes_creator_submission(p_subject_type text, p_subject_id uuid, p_note text)`
  — `status = 'draft'`, `review_note = p_note`.
- `reject_creator_submission(p_subject_type text, p_subject_id uuid, p_note text)`
  — `status = 'archived'`, `review_note = p_note`.

Godkännandet lämnar katalogposten som **utkast**. Ikon, bild, färgtema och
fler kontextvarianter finslipas i den befintliga adminvyn, och publicering
sker med befintliga `publish_catalog_prompt` / `publish_catalog_package`.
Motivet: creator-innehåll ska inte synas som halvfärdigt bredvid kurerat
innehåll i katalogen.

## Distributionsgaten

De fem publika läs-RPC:erna får en ny parameter:

```sql
p_include_creator_content boolean default false
```

Webben och `scripts/generate-catalog-pages.mjs` skickar `true`. Den hostade
MCP:n i `mcp_promptbanken` skickar ingenting och får därmed filtrerat
resultat utan att en enda rad ändras i det repot. Defaultvärdet är
riktningen som spelar roll: en glömd kodrad i det andra repot kan inte
läcka creator-innehåll, den kan bara utesluta för mycket.

Predikatet i denna leverans:

```sql
and (p_include_creator_content or cp.creator_profile_id is null)
```

Delprojekt 7 byter predikatet till att kräva
`creator_consent_distribution and creator_rights_attested`, utan ny
migration på innehållet.

**Migrationsgotcha:** en trailing default-parameter skapar en *andra*
överlagring, inte en ersättning. PostgREST anropar med namngivna argument,
vilket då ger `function is not unique`. Alla fem funktionerna har i dag
exakt en överlagring vardera i produktion:

| Funktion | Nuvarande argument |
| --- | --- |
| `list_published_prompts` | `p_context_keys text[]` |
| `get_published_prompt` | `p_slug text, p_context_keys text[]` |
| `list_published_packages` | `p_context_keys text[], p_package_type text` |
| `get_published_package` | `p_slug text, p_context_keys text[]` |
| `list_published_package_prompts` | `p_package_slug text, p_context_keys text[]` |

Migrationen måste `drop function` den gamla signaturen och skapa den nya i
samma transaktion, samt behålla alla returkolumner som senare migrationer
lagt till (`20260802100000_catalog_security_examples.sql`,
`20260815090000_catalog_package_seo_fields.sql`,
`20260725133000_catalog_parameter_schemas.sql` är de senaste
definitionerna). Varje utelämnad returkolumn är ett produktionsfel i både
webben och MCP:n.

## Återkoppling till creatorn

`list_my_creator_prompts` returnerar i dag inte `review_note`. Utan den ser
creatorn aldrig varför en ändring begärdes, och knappen "Begär ändring"
blir en återvändsgränd. RPC:n utökas med kolumnen och
`src/creatorContent.js` visar noten på poster i `draft` som har en.

Motsvarande för paket: `list_my_creator_package_drafts` utökas med
`review_note`, vilket kräver kolumnen på `creator_package_drafts` — den
finns inte där i dag.

## Den publika creator-sidan

`scripts/creator-page-template.mjs` rad 169–171 renderar i dag tre
hårdkodade nollägen. Två av dem fylls nu:

- **Publicerade paket** och **Publicerade prompts** — från
  `catalog_packages`/`catalog_prompts` där `creator_profile_id` matchar,
  status `published`. Ny läs-RPC `list_creator_published_content(p_slug text)`.
- **Workshopkrediter** förblir nolläge (delprojekt 5).

Katalogens egna sidmallar (`scripts/catalog-page-template.mjs`) får en
"Av *namn*"-rad med länk till `/creator/<slug>` när `creator_profile_id`
är satt. Det är hela SEO-värdet i creator-programmet.

## Felhantering

- Edge-funktionen otillgänglig eller API-fel: adminvyn visar felet och
  behåller posten oförändrad. Granskning är aldrig ett hinder för att
  fatta beslut manuellt.
- Otolkbart modellsvar: ingen rad skrivs, felet visas.
- Godkännande av paket där en ingående prompt saknar katalogpost: RPC:n
  avbryter med besked om vilken prompt som måste godkännas först.
- Slug-krock vid godkännande: RPC:n avbryter, admin får ange annan slug.

## Testning

`supabase/tests/creator_review.sql`:

- Gaten utesluter creator-innehåll som default och släpper igenom det med
  `p_include_creator_content => true`.
- Alla nya RPC:er avvisar en användare som inte är `platform_owner`.
- `approve_creator_prompt` skapar katalogpost i `draft`, sätter
  `creator_profile_id` och kopierar båda distributionsflaggorna.
- `request_changes` och `reject` sätter rätt status och `review_note`.
- Rollen som edge-funktionen kör med saknar `update`-rättighet på
  `content_items.status` och `catalog_prompts`.
- De fem läs-RPC:erna returnerar oförändrade kolumnuppsättningar efter
  signaturbytet.

Efter deploy körs `promptbanken-mcp-contract-test` mot produktion för att
verifiera att MCP:ns nio publika verktyg svarar identiskt som före.

## Kvarstående för delprojekt 7

Innan creator-innehåll får nå Open/MCP:

- `privacy.html` och `privacy-en.html` avsnitt 2.3 måste beskriva att
  verktygens utdata kan innehålla en creators visningsnamn och profillänk.
  Det var exakt den brist som fällde ansökan 1.2.1.
- Modereringsgrinden — AI-förgranskning plus obligatoriskt mänskligt
  godkännande — bör beskrivas i ansökan, inte bara finnas i koden.
- Gate-predikatet byts till att kräva båda distributionsflaggorna.
- Ansökan 1.2.2 bör vara avgjord först. Att ändra connectorns utdata
  medan en granskning pågår är onödig risk.

## Risker

- **Signaturbytet på fem delade RPC:er** är leveransens farligaste steg.
  Det påverkar webben, sidgeneratorn och den hostade MCP:n samtidigt. Körs
  som egen migration, verifieras mot den faktiska PostgREST-vägen, inte
  bara i SQL-editorn.
- **Modellkostnad** är försumbar vid dagens volym men obunden i teorin.
  Granskning på begäran är i sig taket.
- **Dublettkontrollen slutar skala** vid några hundra katalogposter.
  Dokumenterat, inte löst.
