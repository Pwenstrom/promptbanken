# Statiska paketsidor och paketförst-IA — design

Datum: 2026-08-15
Status: godkänd, redo för implementationsplan

## Syfte

Promptpaket ska bli den primära enheten i Promptbankens publika frontend och
SEO-struktur. Idag finns paket bara som kort i katalogappen
(`promptbanken.html`), renderade client-side från Supabase. Sökmotorer och
sociala förhandsvisningar ser ingenting av dem, och det finns inga
paketspecifika URL:er att länka till utifrån.

Den här designen ger varje publicerat paket en riktig, indexerbar sida på
`/paket/<slug>/`, en `/paket/`-översikt som SEO-nav, och lyfter paket före
lösa prompts i katalogens informationsarkitektur.

## Sammanhang: detta är delprojekt 1 av 7

Den övergripande produktvisionen (Creator-läge, granskningsflöde,
Workshopkrediter, MCP-exponering av creator-innehåll) består av sju
delsystem. Denna spec täcker enbart det första:

1. **SEO + paketförst-IA** ← denna spec
2. Creator-profiler
3. Creator-authoring med attribution och återanvändningsstyrning
4. Redaktionellt granskningsflöde
5. Kreditledger (Workshopkrediter)
6. Workshop-datamodell
7. MCP-exponering av godkänt creator-innehåll

Delprojekt 1 är oberoende av 2–7 och kan byggas först. Ett designval här
görs uttryckligen för att inte blockera 2–3: paketsidans mall får en
källa/författare-slot redan nu, som initialt alltid renderar
"Av Promptbanken".

## Nuvarande arkitektur (referens)

- Statisk multipage-site byggd med Vite, deployad till GitHub Pages på
  `app.promptbanken.se`. Ingen server, ingen SSR.
- `.github/workflows/deploy.yml` bygger vid push till `main` och vid
  `workflow_dispatch`, med `VITE_SUPABASE_URL` och
  `VITE_SUPABASE_PUBLISHABLE_KEY` som secrets. Build-time-generering mot
  Supabase är därför möjlig utan ny infrastruktur.
- `vite.config.js` har en handskriven lista av HTML-ingångar plus
  `viteStaticCopy` för `robots.txt`, `sitemap.xml`, `script.js`, `style.css`
  m.m.
- `sitemap.xml` är handskriven och listar bara statiska `.html`-filer och
  prompttextfiler.
- Katalogschema: `catalog_packages`, `catalog_package_variants`
  (per kontext: generell/skola/kommun/företag/förening/privat, med
  `title`, `summary`, `intro_text`, `audience_label`),
  `catalog_package_items` (`sort_order`, `step_title`, `step_intro`,
  `is_required`).
- Publika läs-RPC:er: `list_published_packages`, `get_published_package`,
  `list_published_package_prompts` — alla filtrerar på publicerat.
- Befintligt metamönster på sidor: `description`, `og:type`, `og:site_name`,
  `og:title`, `og:description`, `og:url`, `twitter:card`, `canonical`.
  Ingen `og:image` finns idag. `public/brand-mark.png` finns.
- `src/admin.js` är 2953 rader.
- Delningslänk för paket finns redan: `promptbanken.html?package=<slug>`
  (se `docs/superpowers/specs/2026-08-11-package-share-link-design.md`).

## Beslut

### URL-struktur

En sida per paket, genererad från den **generella** kontextvarianten:
`/paket/<slug>/`. Kontextvalet finns kvar interaktivt i appen men påverkar
inte URL:en.

Motiv: kontextvarianterna har hög textlikhet. Sex sidor per paket skulle
läsas som tunna dubbletter av sökmotorer och kräva canonical-akrobatik utan
motsvarande vinst.

### Ombyggnadsstrategi

Statiska sidor uppdateras bara när sajten byggs om. `deploy.yml` får en
`schedule`-trigger (nattlig cron) utöver befintliga `push` och
`workflow_dispatch`. Ett nypublicerat paket når därmed webben senast
nästa natt, eller direkt via manuell körning i GitHub.

Motiv: alternativen (knapp i admin, Supabase-webhook) kräver att en
GitHub-token hanteras utanför frontend, vilket i sin tur kräver en Supabase
Edge Function. Det är eget scope och inte motiverat för första versionen.

### Redaktionella fält läggs till i databasen nu

Paketsidan ska enligt produktkraven svara på vilket problem paketet löser,
när det passar och vad användaren får ut. De fälten finns inte. De läggs
till nu, hellre än att sidan komponeras av befintliga fält och blir tunnare
än avsett.

## Datamodell

Ny migration, additiv och nullable genomgående så befintliga paket och
befintliga anrop fortsätter fungera.

`public.catalog_package_variants` får:
- `problem_text text` — vilket problem paketet löser
- `when_to_use text` — när det passar
- `outcome_text text` — vad användaren får ut

`public.catalog_packages` får:
- `area text` — område, för gruppering på `/paket/` och relaterade paket
- `tags text[]` — taggar, för interna länkar
- `is_indexable boolean` — redaktionell åsidosättning av
  indexerbarhetströskeln (nullable: `null` = använd tröskeln,
  `true`/`false` = tvinga)

Läs-RPC:erna `list_published_packages` och `get_published_package` utökas
med de nya fälten. Utökningen är additiv — nya kolumner i returtabellen,
inga ändrade parametrar, inga borttagna fält. Befintliga anrop i
`script.js` och i den separata MCP-servern (`mcp_promptbanken`) påverkas
inte.

## Indexerbarhet

En paketsida **genereras alltid** för varje publicerat paket, så att
delningslänkar och direktnavigering fungerar. Men den får `<meta
name="robots" content="noindex">` och utelämnas ur sitemap om den inte når
tröskeln.

Tröskel: `intro_text` är ifyllt **och** paketet har minst tre prompts.

`is_indexable` åsidosätter tröskeln i båda riktningarna när den är satt.

Motiv: produktkravet är uttryckligen att ett paket ska ha verkligt
redaktionellt värde för att bli indexerbart, och att automatiskt skapade
tunna landningssidor ska undvikas.

## Generatorn

Nytt script: `scripts/generate-catalog-pages.mjs`, kört efter `vite build`.
npm-scriptet `build` blir `vite build && node scripts/generate-catalog-pages.mjs`.

Beteende:
- Använder `@supabase/supabase-js` (redan en dependency) med
  `VITE_SUPABASE_URL` och `VITE_SUPABASE_PUBLISHABLE_KEY` — alltså
  anon-nyckeln och de publicerat-filtrerande RPC:erna. Opublicerat material
  kan därmed inte hamna i genererade filer.
- Hämtar publicerade paket och deras prompts, skriver
  `dist/paket/<slug>/index.html` per paket, `dist/paket/index.html` som
  översikt, och en omgenererad `dist/sitemap.xml`.
- **I CI: failar bygget** om Supabase inte svarar eller returnerar fel.
  Alternativet — att hoppa över tyst — deployar en sajt utan paketsidor och
  med amputerad sitemap, vilket är värre än ett stoppat bygge.
- **Lokalt utan env-variabler: hoppar över med varning**, så
  `npm run build` fortsätter fungera för vanligt frontendarbete.
  Skillnaden avgörs av om env-variablerna är satta, inte av en CI-flagga.

Mallrendering sker med vanliga template-literals i en egen modul, utan
ramverk, och återanvänder `style.css` samt samma header/footer-markup som
övriga sidor. Sidorna ärver därmed designsystem, mörkt läge och
responsivitet utan ny CSS-gren.

### Sitemap

`sitemap.xml` slutar vara en handskriven fil som kopieras rakt av.
Generatorn bygger den av två delar: den befintliga listan av statiska
URL:er (behålls oförändrad), plus `/paket/` och varje indexerbar
paketsida. `robots.txt` behöver ingen ändring — den pekar redan på
`sitemap.xml`.

## Sidmallen `/paket/<slug>/`

Ordning på sidan:

1. Brödsmulor: Hem › Paket › paketets titel.
2. `<h1>` från variantens `title`.
3. Ingress från `summary`.
4. **Källrad: "Av Promptbanken".** Detta är den slot som delprojekt 2–3
   senare fyller med creatorprofil och attribution. Den finns med redan nu
   just för att mallen inte ska behöva skrivas om då.
5. `intro_text`.
6. Redaktionella sektioner, var och en **utelämnad om fältet är tomt**:
   - "Vilket problem paketet löser" → `problem_text`
   - "Vem det är för" → `audience_label`
   - "När det passar" → `when_to_use`
   - "Vad du får ut" → `outcome_text`
7. Innehållsförteckning: paketets prompts i `sort_order`, med `step_title`
   och `step_intro` som redaktionell text per steg.
8. Åtgärd: "Öppna paketet i Promptbanken" → `promptbanken.html?package=<slug>`.
   Den statiska sidan står för upptäckt, appen för användning.
9. Relaterade paket från samma `area`, samt paketets `tags` som interna
   länkar till motsvarande ankare på `/paket/`.

### Metadata per sida

- Unik `<title>` och `<meta name="description">` från variantens `title`
  respektive `summary`.
- `<link rel="canonical" href="https://app.promptbanken.se/paket/<slug>/">`.
- OG-taggar i samma form som befintliga sidor (`og:type`, `og:site_name`,
  `og:title`, `og:description`, `og:url`), plus `og:image` mot
  `brand-mark.png` tills paketspecifika bilder finns.
- `twitter:card` som på övriga sidor.
- `<meta name="robots" content="noindex">` när sidan inte når
  indexerbarhetströskeln.

### Strukturerad data

JSON-LD med `BreadcrumbList` och `ItemList` (paketets prompts).

`HowTo` används medvetet **inte**, inte heller för workflow-paket: Google
slutade visa den rich resulten 2023, så uppmärkningen ger ingen vinst.

## `/paket/`-översikten

Genererad sida som listar alla indexerbara paket grupperade per `area`,
med områdesrubriker som interna ankare (`#omrade-<slug>`) så taggar och
relaterade paket kan länka dit. Den blir SEO-navet för hela
paketstrukturen.

Paket som saknar `area` samlas sist under rubriken "Övriga paket", så att
inget indexerbart paket faller ur översikten. Ett paket utan `area` får
inga relaterade paket på sin egen sida — sektionen utelämnas då helt
istället för att visas tom.

Länkas från startsidans hero och från huvudmenyn.

## Ändringar i befintlig frontend

- `promptbanken.html`: paketgriden flyttas före promptgriden, med tydligare
  rubrik. Varje paketkort får en länk till sin statiska sida vid sidan av
  det befintliga klicket som öppnar detaljvyn.
- `index.html`: hero kompletteras med en länk till `/paket/`, och
  huvudmenyn får samma länk. Heron skrivs **inte** om i övrigt.

## Admin

De nya redaktionella fälten (`problem_text`, `when_to_use`, `outcome_text`,
`area`, `tags`, `is_indexable`) behöver kunna fyllas i, annars står de
tomma och sidorna blir tunna.

Fälten läggs i en **egen modul**, inte i `src/admin.js` — den filen är
redan 2953 rader och att växa den ytterligare gör den svårare att arbeta i.

Admin bör också se om ett paket når indexerbarhetströskeln eller inte, så
kvalitetskravet blir synligt vid redigering.

## Säkerhet

- **All text från databasen escapas innan den skrivs till HTML.** Detta är
  inte teoretiskt: när creator-innehåll i delprojekt 3 renderas genom samma
  mall är det användargenererad text som blir statiska sidor, och en
  oescapad titel blir då lagrad XSS för varje besökare.
- **Slugs valideras mot ett strikt mönster innan de används som
  katalognamn.** En slug som innehåller `../` skulle annars låta generatorn
  skriva filer utanför `dist/`.
- Generatorn använder anon-nyckeln och de publicerat-filtrerande RPC:erna —
  samma gräns som webbappen redan lyder under. Ingen service-nyckel
  förekommer i bygget.
- Inga nya hemligheter införs. `deploy.yml` använder de secrets som redan
  finns.

## Testning

- **Generatorns rena funktioner** (mallrendering, escaping,
  slug-validering, sitemap-bygge, indexerbarhetströskeln) testas med
  `node --test`, inbyggt i Node — inget nytt beroende. Repot saknar
  JS-testsvit idag, så detta blir den första.
- **Databasen** verifieras med en fil i `supabase/tests/` enligt befintligt
  mönster: kontrollerar att de nya kolumnerna finns och att läs-RPC:erna
  returnerar dem.
- **Manuellt i browser**, enligt projektets konvention: bygg lokalt med
  env-variabler satta, granska genererad HTML för ett paket med ifyllda
  fält och ett utan, bekräfta att det tunna paketet fått `noindex` och
  saknas i sitemap, kontrollera brödsmulor, canonical, OG-taggar och
  JSON-LD, samt mobil- och desktopvy.

## Avgränsning

Ingår inte i denna spec:

- Prompt-sidor (`/prompt/<slug>`) och korslänken "den här prompten ingår
  även i …". Eget delprojekt: det dubblar generatorn och rör
  promptvarianternas parameterrendering.
- Creator-profiler, creator-authoring, granskningsflöde, Workshopkrediter,
  workshop-datamodell (delprojekt 2–6).
- Ändringar i den hostade MCP:n (delprojekt 7). RPC-utökningarna här är
  additiva och påverkar den inte.
- Ombyggnad av startsidans hero och kort.
- Paketspecifika OG-bilder.
- Automatisk ombyggnad vid publicering (webhook/edge function).
