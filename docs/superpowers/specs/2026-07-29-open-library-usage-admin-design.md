# Open Library Usage Admin Design

## Bakgrund

Promptbanken har gått från produkt med workspace-/adminflöden till ett öppet
bibliotek där innehåll kurateras via admin-MCP. `admin.html` ska därför inte
längre vara en plats för redigering, publicering, workspacehantering,
medlemsadministration eller uppgraderingsflöden.

Adminytans nya uppgift är att visa anonym statistik och analys som hjälper
Promptbanken att utveckla det öppna biblioteket: vilka prompts och paket används,
vad kopieras, var uppstår fel och vilka behov verkar saknas.

## Mål

1. Göra `admin.html` till en read-only analysyta för det öppna biblioteket.
2. Samla anonym användningsstatistik från både webbkatalogen och den öppna
   hostade MCP-endpointen från första versionen.
3. Minska attackytan genom att ta bort write-orienterade adminflöden från
   adminfrontenden.
4. Ge beslutsnära mått för promptförbättring, paketutveckling och felsökning.
5. Lägga en datamodell som kan aggregeras, exporteras och rensas utan att spara
   personuppgifter.

## Icke-mål

- Ingen redaktörs-UI för att skapa, ändra, publicera eller radera kataloginnehåll.
- Ingen workspace-, medlems-, faktura-, plan- eller inbjudningshantering i den nya
  adminytan.
- Ingen rå trafikanalys från GitHub Pages eller VPS accessloggar.
- Ingen lagring av IP-adresser, e-post, användarkonton, rå user-agent, MCP-nycklar,
  nyckelhashar, promptinput eller rå prompttext.
- Ingen detaljerad klientfingerprinting.
- Ingen realtidsdashboard i v1.

## Berörda ytor

### `promptbanken`

- Supabase-migrationer för anonym eventmodell och aggregerade admin-RPC:er.
- `script.js` för webbkatalogens trackinghändelser.
- `admin.html` och `src/admin.js` för read-only analysdashboard.
- `style.css` för dashboardens layout.
- Integritets-/hjälptext om anonym användningsstatistik.

### `mcp_promptbanken`

Den hostade öppna MCP-servern på VPS (`mcp.promptbanken.se`) måste instrumenteras
för samma eventmodell. Den här specen bor i `promptbanken` eftersom databasen och
adminytan ägs här, men implementationen kräver en följdspec eller plan i
`mcp_promptbanken` för serverkod och VPS-deploy.

### Lokala `mcp-server/`

Den lokala stdio-servern i detta repo kan få samma wrappermönster för
utvecklingsparitet, men den är inte den primära statistikkällan. V1-målet är den
hostade öppna MCP-endpointen.

## Datamodell

Skapa en smal eventtabell, exempelvis `public.library_usage_events`, med RLS
påslaget och utan direkt `select` för `anon` eller vanliga `authenticated`.

Fält:

- `id uuid primary key default gen_random_uuid()`
- `created_at timestamptz not null default now()`
- `event_version smallint not null default 1`
- `source text not null`
- `event_type text not null`
- `outcome text not null default 'success'`
- `prompt_slug text null`
- `package_slug text null`
- `context_keys text[] null`
- `area text null`
- `risk_level text null`
- `result_count integer null`
- `catalog_version text null`
- `metadata jsonb not null default '{}'::jsonb`

Tillåtna `source` i v1:

- `web`
- `open_mcp`

Reserverade för framtiden:

- `admin_mcp`
- `valvet`
- `enterprise_mcp`

Tillåtna `event_type` i v1:

- `prompt_view`
- `prompt_copy`
- `prompt_get`
- `prompt_list`
- `package_view`
- `package_get`
- `package_list`
- `package_prompts_list`
- `search`
- `filter_apply`
- `error`

Tillåtna `outcome` i v1:

- `success`
- `empty`
- `not_found`
- `invalid_input`
- `rate_limited`
- `error`

Index:

- `(created_at desc)`
- `(source, event_type, created_at desc)`
- `(prompt_slug, created_at desc)` where `prompt_slug is not null`
- `(package_slug, created_at desc)` where `package_slug is not null`
- `(outcome, created_at desc)` where `outcome <> 'success'`

`metadata` får bara innehålla små, uttryckligt tillåtna nycklar. V1 bör begränsa
den till tekniska attribut som `tool`, `package_type`, `copy_surface` och
`query_length`. Ingen fri klientpayload ska sparas.

## Skriv-RPC för events

Skapa en publik men hårt validerad RPC, exempelvis
`public.track_library_usage_event(...)`, som är enda skrivvägen från webb och
öppen MCP.

Krav:

- `grant execute` till `anon`, `authenticated` och den roll som den hostade
  MCP-servern använder.
- Funktionen validerar `source`, `event_type` och `outcome` mot allowlists.
- Funktionen kapar textfält till korta längder, exempelvis sluggar max 120 tecken.
- Funktionen avvisar metadata med otillåtna nycklar eller för stor payload.
- Funktionen sparar inte rå sökterm.
- Funktionen returnerar bara `{ accepted: true }` eller motsvarande minimal respons.
- Funktionen använder pinnad `search_path`.

För Postgres-säkerhet ska implementationen följa projektets Supabase-regler:
RLS på tabellen, inga service-role-nycklar i frontend, och inga
`SECURITY DEFINER`-funktioner utan explicit auth-/rollkontroll och fast
`search_path`.

## Webbevents

`script.js` ska logga följande händelser:

- `prompt_view`: promptdetalj öppnas.
- `prompt_copy`: prompttext kopieras.
- `package_view`: paketdetalj öppnas.
- `search`: sökning körs med `result_count` och `query_length`, inte rå sökterm.
- `filter_apply`: kontext-/kategori-/taggfilter används.

Throttling:

- Max en `prompt_view` per prompt och anonym session per timme.
- Max en `package_view` per paket och anonym session per timme.
- `prompt_copy` loggas varje gång, eftersom det är starkare nyttosignal.
- `search` debouncas och loggas först när resultat faktiskt räknats.

Anonym session:

- Frontend får skapa ett slumpmässigt, icke-personligt sessionsvärde i
  `sessionStorage`.
- Sessionen skickas inte som eget identifierande fält i v1.
- Om unikhetsmått behövs senare kan en dagligt roterad hash införas, men det är
  inte del av v1.

## Öppna MCP-events

Den hostade MCP-servern ska logga events i verktygsfunktionerna, inte genom
efterhandsparsning av accessloggar.

Verktyg och event:

- `list_prompts` -> `prompt_list`
- `get_prompt` -> `prompt_get`
- `list_packages` -> `package_list`
- `get_package` -> `package_get`
- `list_package_prompts` -> `package_prompts_list`

MCP-event ska innehålla:

- `source = 'open_mcp'`
- motsvarande `event_type`
- `prompt_slug` eller `package_slug` där det finns
- `context_keys` om verktyget fick sådana
- `result_count` för listverktyg
- `outcome = 'success'`, `empty`, `not_found` eller `error`
- `metadata.tool` med verktygsnamnet

MCP-event får inte innehålla:

- MCP-nyckel, nyckelhash eller bearer-token
- rå user-agent
- klientens promptinput
- renderad prompttext
- IP-adress

Fel ska loggas strukturerat. Om `get_prompt("okand-slug")` inte hittar något ska
det ge `event_type = 'prompt_get'`, `prompt_slug = 'okand-slug'`,
`outcome = 'not_found'`. Det är viktig produktfeedback.

## Admin-RPC:er

Adminfrontenden ska inte läsa `library_usage_events` direkt. Skapa aggregerade
read-RPC:er, exempelvis:

- `public.get_library_usage_summary(p_days integer default 30)`
- `public.get_library_prompt_usage(p_days integer default 30, p_limit integer default 50)`
- `public.get_library_package_usage(p_days integer default 30, p_limit integer default 50)`
- `public.get_library_usage_errors(p_days integer default 30, p_limit integer default 50)`
- `public.get_library_search_feedback(p_days integer default 30, p_limit integer default 50)`

Åtkomst:

- Endast plattformsadmin ska få läsa aggregerad statistik.
- Kontrollera roll via befintliga `app_private.current_user_is_platform_owner()`,
  inte via `user_metadata`.
- Returnera bara aggregeringar, aldrig råeventrader.

Minsta sammanfattningsmått:

- totala events per källa
- promptvisningar webb
- promptkopior webb
- prompt-hämtningar MCP
- paketöppningar/hämtningar
- sökningar utan träff
- fel/not_found-rate
- trend per dag för vald period

## Admin-UI

`admin.html` byggs om till en read-only dashboard.

Navigering:

- Översikt
- Prompts
- Paket
- Sökningar och saknade behov
- MCP-status
- Export

Översikt:

- 7/30/90-dagars periodväljare.
- Kort för webbvisningar, webbkopior, MCP-hämtningar, paketaktivitet och fel.
- Enkel trendtabell eller graf per dag.

Prompts:

- Mest visade prompts på webben.
- Mest kopierade prompts på webben.
- Mest hämtade prompts via MCP.
- Prompts med hög visning men låg kopieringsgrad.
- Prompts utan användning under vald period.

Paket:

- Mest öppnade paket på webben.
- Mest hämtade paket via MCP.
- Paket där många hämtar paketet men få öppnar promptarna.

Sökningar och saknade behov:

- Antal sökningar.
- Andel utan träff.
- Filter/context där resultat ofta blir tomt.
- Ingen rå söktermslista i v1.

MCP-status:

- Events per MCP-tool.
- `not_found` per slug.
- senaste aggregerade feltyper.
- enkel hälsosignal: senaste lyckade `open_mcp`-event.

Export:

- CSV/JSON-export av aggregerade tabeller via admin-RPC.
- Ingen råeventexport i v1.

## Borttagning av legacy-admin

Följande ska tas bort från den nya adminupplevelsen eller flyttas bakom separat
legacy-/plattformsväg om det måste behållas temporärt:

- `Mina prompts`
- `Förslag & granskning`
- promptformulär
- katalogpromptformulär
- katalogpaketformulär
- workspace-switch och workspacefakta som primär struktur
- medlemmar
- arbetsytor
- uppgradera/beställning
- API-nycklar
- MCP-nyckelhantering
- konto-radering från adminens huvudvy

Om gamla funktioner behöver leva kvar kortsiktigt ska de inte vara länkade från
nya `admin.html`. En separat legacy-sida är säkrare än att låta write-kod ligga i
samma dashboard.

## Integritet och dataskydd

Kort text ska läggas på lämplig publik sida, exempelvis hjälp- eller
integritetssida:

> Promptbanken samlar anonym användningsstatistik för det öppna biblioteket,
> till exempel vilka prompts som öppnas eller kopieras och vilka MCP-verktyg som
> används. Statistiken används för att förbättra biblioteket. Vi sparar inte
> promptinnehåll från användare, IP-adresser, e-postadresser eller
> personidentifierande klientdata i denna statistik.

Om cookies inte används ska texten inte kalla detta cookie-spårning. Om senare
version inför persistent identifierare, rå sökterm eller extern analysleverantör
krävs ny integritetsbedömning.

## Retention och kostnad

V1 sparar råa anonyma events för analysflexibilitet.

Policy:

- Råevents: 180 dagar.
- Dagliga aggregat: förbereds i designen men behöver inte implementeras i v1.
- När volymen växer: skapa `library_usage_daily` och rensa råevents via cron.

Förväntad kostnad är låg vid rimlig trafik eftersom varje eventrad är smal och
inte innehåller stora payloads. Risk för snabb tillväxt hanteras med:

- metadata-storleksgräns
- allowlistade eventtyper
- klientthrottling
- senare server-side rate limiting eller Edge Function om publik RPC missbrukas

## Missbruksskydd

V1-skydd:

- RPC validerar alla enumliknande fält.
- RPC avvisar för stor metadata.
- Frontend throttlar views.
- Dashboard separerar källor så spam från webben inte förväxlas med MCP-nytta.
- Adminanalys visar fel- och volymspikar per dag.

Framtida skydd:

- Edge Function med rate limiting framför tracking-RPC.
- Aggregering per dag och radering av råevents.
- Blockering av uppenbart orimliga eventvolymer per källa.

## Datakvalitet

Dashboarden måste undvika ett förenklat "mest använd" mått. Följande signaler
ska hållas separata:

- Webbvisning: svag intressesignal.
- Webbkopia: starkare nyttosignal.
- MCP-listning: klienten inventerar biblioteket, inte nödvändigtvis användning.
- MCP-get: starkare signal att en prompt/paket efterfrågas.
- `not_found`: saknad länk, hallucinerad slug eller behov som katalogen inte täcker.
- Tom sökning: saknat område eller dålig metadata.

## Verifiering

För implementationen krävs minst:

1. SQL-verifiering att `anon` kan köra tracking-RPC men inte läsa eventtabellen.
2. SQL-verifiering att vanlig `authenticated` inte kan läsa adminaggregat utan
   plattformsadminroll.
3. SQL-verifiering att plattformsadmin får aggregerad statistik.
4. Webbläsarverifiering att `prompt_view`, `prompt_copy` och `search` skickas med
   rätt payload och utan rå sökterm.
5. MCP-verifiering på hostad server att `list_prompts`, `get_prompt`,
   `get_package` och `list_package_prompts` skapar events med rätt source/outcome.
6. Build: `npm run build`.
7. Efter build: verifiera att `dist/prompts/` fortfarande finns.
8. VPS-deploy-verifiering i `mcp_promptbanken`: health check och ett testanrop mot
   den öppna MCP-endpointen efter deploy.

## Låsta implementationbeslut

1. `admin.html` ersätts direkt med den nya read-only dashboarden. Om legacy-admin
   måste bevaras sker det i separat fil och utan länk från nya adminn.
2. Admin-RPC:erna återanvänder `app_private.current_user_is_platform_owner()`.
3. Daglig aggregattabell lämnas till iteration 2 efter att råevents börjat samlas.

## Rekommenderad implementationordning

1. Skapa Supabase-migration för eventtabell, tracking-RPC och read-only
   admin-RPC:er.
2. Lägg SQL-verifieringsscenario i `supabase/tests/`.
3. Instrumentera webbkatalogen i `script.js`.
4. Bygg om `admin.html` och `src/admin.js` till read-only dashboard.
5. Instrumentera den hostade öppna MCP-servern i `mcp_promptbanken`.
6. Verifiera lokalt/staging.
7. Deploya webben och därefter MCP-servern på VPS.
