# Design: Enhetlig promptkatalog i webben (Fas A)

Datum: 2026-09-01
Status: design, väntar på granskning
Del av: Katalogredesign efter användartestet 2026-08-31
(`docs/user-test-promptbanken-catalog-2026-08-31.md`), Fas A av tre
(A = enhetlig lista, B = paket egen flik, C = språk/overflow — se
mockup-canvasen från samma arbetspass).

Bygger på och citerar, duplicerar inte:
`docs/superpowers/specs/2026-08-30-connect-my-library-architecture-analysis.md`
(backend redan skarpt levererat — se den specens P.4 och O.1).

## Frysta ytor (rörs inte av detta arbete)

`privacy.html`, `privacy-mcp.html`, `mcp.html`, `terms.html`,
`/paket/<slug>/`-permalänkar, paketets query-param-djuplänk
(`openCatalogPackageDetail`-routing), samt hela `mcp_promptbanken`-repot
(Open MCP 1.2.2-ansökan). Inget i denna spec kräver att röra någon av
dem — allt arbete är i `promptbanken.html`, `script.js`, `style.css`.

## Vad som redan finns (verifierat i kod, inte antaget)

- `public.add_catalog_prompt_to_library(p_prompt_id uuid)` — skarp RPC,
  skapar en referensrad (`content_items.library_ref_catalog_prompt_id`
  satt, `content` tomt). Migration `20260831090000`.
- `public.add_catalog_package_to_library(p_package_id uuid)` — samma
  mönster för paket. Migration `20260901100000`.
- `public.get_referenced_library_prompt` / `get_referenced_library_package`
  — läser originalet live via referensen.
- `window.addPublishedPromptToLibrary` i `promptbanken.html` (rad ~723)
  anropar redan `add_catalog_prompt_to_library` och togglar
  knapptext till "Tillagd ✓" i 2,5 sekunder efter klick.
- `loadMyPrompts()` (samma fil) hämtar "Dina prompter" med
  `.is('library_ref_catalog_prompt_id', null)` — referensrader är
  medvetet exkluderade därifrån redan idag.

## Vad som saknas (det denna spec bygger)

1. **Inget beständigt "redan tillagd"-tillstånd.** Knappen vet bara i
   2,5 sekunder efter egen klick att en prompt är tillagd. Vid nästa
   sidladdning, eller för en annan prompt som redan lades till
   tidigare, ser kortet ut som att inget är sparat.
2. **Inget lägg-till på paketkort.** `createCatalogPackageCard`
   (script.js ~1186) renderar bara "Läs mer om paketet" — RPC:n finns,
   knappen finns inte.
3. **Tre separata renderytor, tre separata sök/räkne-beräkningar** för
   `prompt-grid` (statisk `prompts.json`), `catalog-prompt-grid`
   (Supabase-katalog) och `my-prompts-rail` (`content_items` utan
   referens). Källa syns inte på kortet; knappuppsättningen skiljer sig
   utan förklaring (Fynd 2, 3, 5 i användartestet).

## Datamodell för renderingslagret

Ingen ny databaskolumn. Ett nytt in-memory-fält per renderat kort,
byggt i `script.js`, aldrig persisterat:

```
badge: 'inbyggd' | 'open' | 'tillagd' | 'min'
```

| Källa | Villkor | badge | Knappar |
| --- | --- | --- | --- |
| `prompts.json` (statisk) | alltid | `inbyggd` → "Promptbanken" | Välj, Förhandsvisa |
| Supabase-katalog, ej sparad | `catalog_prompts.id` finns INTE i det tillagda Setet | `open` → "Promptbanken Open" | Välj, Förhandsvisa, **Lägg till i Mitt bibliotek** |
| Supabase-katalog, sparad | `catalog_prompts.id` finns i det tillagda Setet | `tillagd` → "Tillagd från Open" | Välj, Förhandsvisa, **✓ Finns i Mitt bibliotek** |
| `content_items` utan `library_ref_*` (ägd av användaren) | alltid | `min` → "Min" | Välj, Förhandsvisa |

Samma tabell gäller paket, med `catalog_packages.id` och
`library_ref_catalog_package_id` istället.

**Explicit ej i scope:** att avgöra om en `prompts.json`-post och en
katalogpost råkar vara samma prompt i sak. Ingen länkkolumn finns
mellan de två systemen idag och ingen byggs här (beslutat med Peter
2026-09-01) — de renderas som två korrekt märkta, separata kort om de
råkar överlappa i innehåll.

## Ny fråga: "vad är redan tillagt"

En gång per sidladdning (inte per kort), efter inloggad session är
bekräftad:

```js
const { data } = await supabase
  .from('content_items')
  .select('library_ref_catalog_prompt_id, library_ref_catalog_package_id')
  .eq('workspace_id', workspaceId)
  .or('library_ref_catalog_prompt_id.not.is.null,library_ref_catalog_package_id.not.is.null');
```

Byggs till två `Set`: `addedCatalogPromptIds`, `addedCatalogPackageIds`.
Läses av kortrenderingen för badge/knapp-val. Ingen ny RPC behövs —
`content_items` är redan RLS-skyddad till ägaren, en vanlig
`select` räcker (samma mönster som `loadMyPrompts()` redan använder).

Efter ett lyckat `add_catalog_prompt_to_library`-anrop: lägg id:t i
Setet lokalt och rendera om det kortet, istället för att bara toggla
knapptext i 2,5 sekunder. Ingen omfrågning av databasen krävs.

## Enhetlig rendering

`prompt-grid`, `catalog-prompt-grid` och `my-prompts-rail` slås ihop
till EN funktion som bygger en gemensam array av korttyper (statisk +
katalog + personlig) och renderar dem i EN DOM-container: `#prompt-grid`
återanvänds som den gemensamma containern, `#catalog-prompt-grid`
slutar fyllas (Öppen katalog-sektionens egna "Enskilda prompts"-rubrik
och grid tas bort ur `promptbanken.html` i denna fas — paketdelen av
`catalog-section` rörs inte), och `<section id="my-prompts-rail">`
tas bort ur `promptbanken.html` helt (dess CSS-klasser lämnas orörda i
`style.css`, används inte längre men är ofarliga att låta ligga kvar).

En delad `applyAllFilters()`-ersättare räknar `visibleCount` och
tomt-läge över den EN sammanslagna arrayen — den nuvarande
tre-källors-summeringen (`legacyVisible + catalogPromptVisible +
catalogPackageVisible`) tas bort. Detta gör den typ av motsägelse
Fynd 4 beskrev (tomt läge + faktisk träff samtidigt) strukturellt
omöjlig, oavsett vad som orsakade den ursprungliga observationen.

Paketgridden (`catalog-package-grid`) rörs INTE av sammanslagningen —
den ligger kvar som egen sektion före listan i Fas A (flytten till
egen flik är Fas B). Paketkorten får bara den nya
lägg-till-knappen (punkt 2 ovan) i denna fas.

## Felhantering

- RPC-fel vid lägg-till: samma mönster som idag (`button.textContent`
  visar felmeddelande, återgår efter 2,5s) — men nu utan att röra
  badge/Set, så kortet inte felaktigt markeras som tillagt.
- Ej inloggad: samma redirect-till-login som idag
  (`addPublishedPromptToLibrary`s befintliga gren), oförändrad.
- "Vad är redan tillagt"-frågan failar tyst (loggas, tom Set) — då
  visas alla katalogkort som ej tillagda; ingen krasch, ingen blockerad
  rendering.

## Testning

Ingen ny Supabase-migration → inget nytt `.sql`-testfall behövs.
Frontend verifieras manuellt i webbläsare (projektets etablerade
mönster, se AGENTS.md): ladda katalogen inloggad, lägg till en
öppen-prompt, ladda om sidan, bekräfta badge/knapp visar "Tillagd från
Open" utan nytt klick. Samma för paket. Bekräfta sök på en term som
bara finns i katalogen inte visar tomt-läge samtidigt som träffen.

## Explicit utanför Fas A

- Paket till egen flik (Fas B).
- "Mitt bibliotek"-ordval, horisontell overflow (Fas C).
- Riktig dedupe mellan `prompts.json` och katalogen.
- Ny "Mitt bibliotek"-sida som visar referensrader (fanns i
  mockup-canvasen, inte i scope här — `content_items` med
  `library_ref_*` satt är idag osynliga i UI:t utanför den
  transienta knapptexten; att bygga en vy för dem är en egen,
  uppenbar nästa uppgift men inte del av detta bygge).
