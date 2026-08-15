# Creator-profiler — design

Datum: 2026-08-16
Status: godkänd, redo för implementationsplan

## Syfte

Ge inloggade användare en egen publik, SEO-indexerbar creator-profil på
`/creator/<slug>/`. Profilen är första länken i den långsiktiga loopen
(creator skapar → Promptbanken kurerar → innehåll publiceras → creatorn får
publicitet och Workshopkrediter), och den entitet som allt efterföljande
creator-arbete hänger på: utan ägarskap på en person går varken authoring,
attribution, granskning eller kreditledger att bygga.

## Sammanhang: delprojekt 2 av 7

1. ~~SEO + paketförst-IA~~ — levererad 2026-08-15
2. **Creator-profiler** ← denna spec
3. Creator-authoring med attribution och återanvändningsstyrning
4. Redaktionellt granskningsflöde
5. Kreditledger (Workshopkrediter)
6. Workshop-datamodell
7. MCP-exponering av godkänt creator-innehåll

Delprojekt 3–5 fyller sektioner som denna spec bygger i nolläge. Ett
uttryckligt designmål här är att de inte ska kräva ombyggnad av profilsidan.

## Nuvarande arkitektur (referens)

- Statisk multipage-site (Vite → GitHub Pages, `app.promptbanken.se`). Ingen
  server, ingen SSR.
- Statiska sidor genereras vid build av `scripts/generate-catalog-pages.mjs`,
  som läser publicerat innehåll via publika RPC:er med anon-nyckeln och
  skriver HTML till `dist/`. Nattlig cron plus `workflow_dispatch`.
- Återanvändbara hjälpfunktioner finns i `scripts/catalog-page-lib.mjs`:
  `isSafeSlug`, `escapeHtml`, `buildSitemap`, `absoluteUrl`, `areaAnchor`
  (med svensk teckennormalisering), `isIndexable`.
- Mallar i `scripts/catalog-page-template.mjs`. JSON-LD escapas med
  `<`-teknik för att inte kunna bryta ut ur `<script>`.
- `404.html` fångar `/paket/<slug>/` och skickar vidare till appen.
- `public.profiles` finns redan men är **arbetsyte-roller** (viewer/editor/
  workspace_owner/platform_owner per workspace), inte en visningsprofil.
  Ingen namnkrock med `creator_profiles`.
- Varje ny användare får automatiskt en personlig arbetsyta via
  `app_private.handle_new_user()`.
- Katalogens skrivmönster: `app_private`-funktion med `security definer`,
  `set search_path = ''` och rollkontroll, plus tunn `public`-wrapper med
  `revoke`/`grant to authenticated`.
- **Ingen filuppladdning finns i systemet.** Supabase Storage används inte.

## Beslut

### Vem blir Creator

Alla inloggade användare, självbetjäning. Ingen ansökan, inget
admin-godkännande av själva profilen, ingen plan-gating.

Motiv: det är *innehållet* som ska kureras (delprojekt 4), inte rätten att
presentera sig. Att gata profilen bakom godkännande lägger ett
granskningssteg utanför det flöde som ändå ska byggas.

### Profilens status

`draft` → `published`. `draft` betyder "inte klar att visa upp", inte
"väntar på godkännande". Användaren kan fylla i profilen i lugn takt och
publicera när den känns klar.

### Slug

Genereras från `display_name` vid första sparning med samma svenska
normalisering som `areaAnchor` redan använder (å→a, ä→a, ö→o, övriga
icke-alfanumeriska tecken till `-`). Redigerbar fram till första
publicering, låst därefter — ändring kräver `platform_owner`.

Motiv: samma skäl som paketens slugs. En publicerad profil kan vara delad
eller indexerad, och en tyst slug-ändring gör de länkarna döda.

### Innehållslistorna byggs i nolläge

Publicerade paket, publicerade prompts, antal bidrag och Workshopkrediter
finns inte att hämta än. Profilsidan renderar sektionerna med "Inget
publicerat ännu" och datamodellen har plats för dem, så delprojekt 3–5 bara
fyller på data.

### Avatarer skjuts upp

`avatar_url` finns i schemat men **används inte** i den här omgången.
Profilsidan renderar initialer.

Motiv: utan filuppladdning skulle fältet peka på en extern adress, och varje
besökare på en publik profilsida skulle då hämta en bild från tredje part
som därmed får besökarens IP-adress. Det krockar med sajtens hållning att
inte skicka användardata vidare. När Supabase Storage införs (det behövs
ändå för delprojekt 3) laddas bilder upp till egen domän och fältet kan tas
i bruk utan schemaändring.

### Statisk generering

Samma mönster som paketsidorna: `/creator/<slug>/` genereras vid build av
det befintliga byggsteget, utökat att också hämta publicerade profiler.

## Datamodell

Ny tabell `public.creator_profiles`:

| Kolumn | Typ | Not |
|---|---|---|
| `id` | uuid pk | |
| `user_id` | uuid not null unique | `references auth.users(id) on delete cascade`; en profil per användare |
| `slug` | text not null unique | mönster `^[a-z0-9]+(?:-[a-z0-9]+)*$` |
| `display_name` | text not null | |
| `bio_short` | text | kort presentation, används som meta description |
| `bio_long` | text | längre presentation |
| `competence_areas` | text[] | kompetensområden |
| `organisation` | text | |
| `website_url` | text | valideras till http/https |
| `linkedin_url` | text | valideras till http/https |
| `avatar_url` | text | reserverad, används inte i denna omgång |
| `status` | text not null default `'draft'` | check `in ('draft','published')` |
| `published_at` | timestamptz | sätts vid första publicering |
| `slug_locked` | boolean not null default false | sätts true vid första publicering |
| `created_at` / `updated_at` | timestamptz | |

Index på `slug` (unique) och `user_id` (unique).

### RPC:er

Följer katalogens mönster (`app_private` + tunn `public`-wrapper,
`security definer`, `set search_path = ''`):

- `public.upsert_my_creator_profile(...)` — skapar eller uppdaterar den
  inloggade användarens egen profil. Kan aldrig röra någon annans.
- `public.publish_my_creator_profile()` — sätter `status = 'published'`,
  `published_at`, `slug_locked = true`. Vägrar om tröskeln (se nedan) inte
  är uppfylld.
- `public.unpublish_my_creator_profile()` — tillbaka till `draft`.
  `slug_locked` förblir true.
- `public.get_my_creator_profile()` — hämtar egen profil oavsett status.
- `public.list_published_creator_profiles()` — publik, för generatorn och
  `/creator/`-översikten.
- `public.get_published_creator_profile(p_slug text)` — publik.
- `public.admin_update_creator_profile_slug(p_user_id uuid, p_slug text)`
  och `public.admin_unpublish_creator_profile(p_user_id uuid)` — gated till
  `platform_owner`.

### RLS

`creator_profiles` har RLS på. Användaren läser och skriver bara sin egen
rad; `anon` läser bara rader med `status = 'published'`. All skrivning från
frontend går via RPC:erna, inte direkt mot tabellen.

## Säkerhet

Tre risker som uppstår just av kombinationen självbetjäning + indexerbar
publik sida.

**Impersonation.** Utan spärr kan vem som helst publicera en profil med
`display_name` "Promptbanken" på en indexerbar sida under plattformens egen
domän. Skydd:
- En reserverad lista av slugs och namn som blockeras vid sparning:
  `promptbanken`, `admin`, `support`, `official`, `kontakt`, `system`,
  `hoglandsforbundet`, `api`, `mcp`, `paket`, `creator`, samt normaliserade
  varianter. Blockeringen gäller både `slug` och `display_name`.
- `platform_owner` kan alltid avpublicera en profil.
- Profilsidan har en tydlig rad "Creator på Promptbanken" så att innehållet
  aldrig läses som officiellt.

**Länkspam.** `website_url` och `linkedin_url` valideras till `http`/`https`
(aldrig `javascript:`, `data:` eller relativa värden) och renderas med
`rel="nofollow noopener"` samt `target="_blank"`. Utan `nofollow` blir varje
självbetjäningsprofil en gratis backlink på en indexerad sida.

**Escaping.** Allt profilinnehåll är användargenererad text som renderas
till statisk HTML. Samma krav som för paketsidorna: allt escapas, JSON-LD
med `<`-teknik, slugs valideras mot det strikta mönstret innan de
används som katalognamn.

## Indexerbarhet

Samma princip som paketen: en profil med bara ett namn är inget att
indexera.

Tröskel: `status = 'published'` **och** `display_name` ifyllt **och**
`bio_short` ifyllt (icke-tom efter trim).

Profiler under tröskeln får sidan genererad men med
`<meta name="robots" content="noindex">` och utelämnas ur sitemap.
`publish_my_creator_profile()` vägrar publicera under tröskeln, med ett
begripligt felmeddelande — bättre att stoppa i UI:t än att tyst producera en
osynlig sida.

## Sidor

### `/creator/<slug>/`

Egen mallmodul `scripts/creator-page-template.mjs` (håller filerna
fokuserade) som återanvänder hjälpfunktionerna i `catalog-page-lib.mjs`.

Innehåll i ordning:
1. Brödsmulor: Hem › Creators › namnet.
2. `<h1>` med `display_name`, initialer i stället för avatarbild.
3. Raden "Creator på Promptbanken".
4. `bio_short` som ingress, `bio_long` som brödtext.
5. Organisation och kompetensområden.
6. Validerade länkar med `rel="nofollow noopener"`.
7. "Publicerade paket" — nolläge: "Inget publicerat ännu."
8. "Publicerade prompts" — nolläge.
9. "Workshopkrediter" — nolläge.

Metadata: unik `<title>` och description (`bio_short`), canonical,
OG-taggar i samma form som övriga sidor, `noindex` under tröskeln.
Strukturerad data: `BreadcrumbList` och `Person`.

### `/creator/`

Översikt över publicerade, indexerbara profiler.

Motiv: utan den blir profilerna föräldralösa — indexerbara men utan en enda
intern länk, vilket sökmotorer värderar lågt. Mönstret finns redan från
`/paket/`, så kostnaden är låg. Delprojekt 3 länkar senare hit från
paketsidor.

Utelämnas ur sitemap och sätts `noindex` om ingen profil når tröskeln.

### 404-fallback

`404.html` utökas: en sökväg som matchar `/creator/<slug>/` men inte finns
visar "Profilen publiceras inom ett dygn" i stället för en generisk
felsida. Till skillnad från paket finns ingen appvy att skicka vidare till.
Slugen valideras mot samma strikta mönster och skrivs aldrig till DOM:en
som HTML.

## App och admin

**`creator.html`** — ny sida i appen för den inloggade användaren:
- Redigeringsformulär för profilens fält.
- Publicera/avpublicera.
- Visning av den publika adressen och om profilen når tröskeln.
- Nollstate-sektioner för paket, prompts och Workshopkrediter, så att
  sammanhanget syns redan innan delprojekt 3–5 finns.

Enkelt formulär, inte ett CMS. Egen modul `src/creatorProfile.js`.

**Admin** — lista över creator-profiler med två ingrepp: avpublicera och
ändra slug. Det är precis de två åtgärder som krävs för impersonation
respektive döda länkar. Egen modul `src/adminCreatorProfiles.js`, inget
tillägg i `src/admin.js`.

## Testning

- Rena funktioner (slug-generering, reserverade namn, URL-validering,
  indexerbarhetströskel, mallrendering) testas med `node --test`, som
  redan är uppsatt.
- SQL-verifiering i `supabase/tests/` enligt befintligt mönster: kolumner,
  RLS aktiverad, RPC:er anropbara, och att en användare inte kan skriva
  någon annans profil.
- Manuellt i browser: skapa profil, publicera, se den publika sidan efter
  bygge, kontrollera `noindex` under tröskeln, kontrollera att externa
  länkar har `nofollow`.

## Avgränsning

Ingår inte:
- Avatar-uppladdning och Supabase Storage.
- Creator-authoring av prompts och paket (delprojekt 3).
- Granskningsflöde (delprojekt 4).
- Kreditledger — bara nolläge visas (delprojekt 5).
- Workshop (delprojekt 6).
- MCP-exponering (delprojekt 7).
- Följare, likes, kommentarer, ranking.
