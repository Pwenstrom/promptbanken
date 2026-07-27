# Dynamisk katalogplattform för Promptbanken

**Datum:** 2026-07-21  
**Status:** Delvis implementerad. Publik katalog och läsflöden är i drift;
separat Admin-MCP och full redaktionell publiceringskedja återstår.

## Bakgrund

Promptbanken är på väg från en huvudsakligen fil-/repo-baserad katalog mot en
bredare produkt med:

- flera kontexter (`generell`, `skola`, `kommun`, `företag`, `förening`, `privat`)
- dynamiska paket och arbetssätt
- en hostad publik MCP som ska spegla samma innehåll som webben
- redaktionellt skapande via admin, Claude Code eller ett högbehörigt admin-MCP

Målet är att nya katalogprompts, paket och arbetssätt ska kunna skapas och
publiceras utan rebuild av MCP-servern.

## Produktgräns

Denna spec gäller endast innehållsplattformen bakom katalogen:

- datamodell för prompts, paket och kontextvarianter
- status/publicering
- admin-/chattskapande av utkast
- läsmodell för frontend och hostad MCP

Utanför scope i denna spec:

- auth/auktorisering för admin-MCP och publiceringsrättigheter
- sök/indexering/ranking på `app.promptbanken.se`
- domänflytt/ompositionering till `app.promptbanken.se`
- fri bilduppladdning

## Beslut

### 1. Databasen blir master

Supabase blir master för publicerat kataloginnehåll.

Repo och MCP-kod ska inte behöva ändras när:

- en ny katalogprompt skapas
- ett nytt paket skapas
- ett arbetssätt skapas
- en kontextvariant läggs till

### 2. Relationsmodell, inte dokumentmodell

Plattformen byggs som en ren relationsmodell. Huvudobjekten är:

- `catalog_prompts`
- `catalog_prompt_variants`
- `catalog_packages`
- `catalog_package_variants`
- `catalog_package_items`

Motivering:

- tydlig validering
- tydliga publiceringsregler
- lätt att bygga admin-UI för
- lätt att läsa från hostad MCP
- lätt att querya för framtida rekommendationer och sök

### 3. Arbetssätt är paket av typen `workflow`

Arbetssätt modelleras inte som ett eget kärnobjekt i första versionen.

I stället används:

- vanliga paket för samlingar
- `package_type='workflow'` för arbetssätt

Det gör att samma publicerings- och redigeringsflöde kan användas för både
paket och arbetssätt.

### 4. Kontextvarianter är separata child-rader

Kontextvarianter lagras inte som stora JSON-overrides på huvudposten.
De lagras som separata child-rader:

- `catalog_prompt_variants`
- `catalog_package_variants`

Det ger en stabil struktur för fallback, adminredigering och MCP-läsning.

### 5. `generell` krävs alltid som fallback

Varje prompt och varje paket måste ha en `generell` variant.

Kontextspecifika varianter (`skola`, `kommun`, `företag`, `förening`,
`privat`) är valfria tillägg.

Fallbackregel:

1. försök vald kontext
2. om saknas, använd `generell`

### 6. Kontexten ändrar främst presentation och exempel

I första versionen ska kontextvarianter främst ändra:

- titel
- summary/ingress
- exempelindata
- målgruppsord
- tonhint
- paketering runt prompten

Kärnprompten ska hållas gemensam så långt som möjligt. Hela prompttexten ska
inte divergera per kontext om det bara handlar om ordval som
`medborgare`/`vårdnadshavare`/`kund`.

### 7. Kontextvarianter skrivs manuellt av redaktionen

Kontextvarianter skapas och redigeras manuellt av redaktionen i första
versionen. De ska inte genereras automatiskt som huvudmodell.

### 8. Statusmodell: `draft` och `published`

Första versionen använder bara två statusar:

- `draft`
- `published`

Ingen separat review-status i denna fas.

### 9. Chattskapande skapar färdiga utkast direkt

Admin, Claude Code eller ett högbehörigt admin-MCP ska kunna skapa:

- en enskild prompt som utkast
- ett helt paket eller arbetssätt som utkast
- underliggande prompts i samma körning

Skapandet ska skriva riktiga databasrader direkt, inte bara ett
förhandsförslag.

## Datamodell

### `catalog_prompts`

Stabil baskärna för en prompt.

Fält:

- `id`
- `slug`
- `status` (`draft`, `published`)
- `prompt_kind` (`prompt` i första versionen)
- `icon_key`
- `image_key`
- `color_theme`
- `created_by`
- `updated_by`
- `created_at`
- `updated_at`

Denna tabell ska inte bära kontextspecifik copy.

### `catalog_prompt_variants`

Kontextspecifik presentation och innehåll för en prompt.

Fält:

- `id`
- `prompt_id`
- `context_key` (`generell`, `skola`, `kommun`, `företag`, `förening`, `privat`)
- `title`
- `summary`
- `prompt_text`
- `example_input`
- `audience_label`
- `tone_hint`
- `context_notes`
- `suggested_variables`
- `created_at`
- `updated_at`

Regler:

- en `generell` variant krävs för varje prompt
- en prompt får ha flera kontextvarianter
- om kontextvariant saknas används `generell`

`suggested_variables` får användas för små strukturerade hjälpfält, men inte
som ersättning för den relationsbaserade modellen.

### `catalog_packages`

Stabil baskärna för paket och arbetssätt.

Fält:

- `id`
- `slug`
- `status` (`draft`, `published`)
- `package_type` (`collection`, `workflow`)
- `icon_key`
- `image_key`
- `color_theme`
- `created_by`
- `updated_by`
- `created_at`
- `updated_at`

### `catalog_package_variants`

Kontextspecifik copy för paket och arbetssätt.

Fält:

- `id`
- `package_id`
- `context_key`
- `title`
- `summary`
- `intro_text`
- `audience_label`
- `created_at`
- `updated_at`

Regler:

- en `generell` variant krävs för varje paket
- paket får ha flera kontextvarianter

### `catalog_package_items`

Relation mellan paket och prompts.

Fält:

- `id`
- `package_id`
- `prompt_id`
- `sort_order`
- `step_title`
- `step_intro`
- `is_required`

Regler:

- samma prompt får ingå i flera paket
- ordning och stegcopy ligger på relationen, inte i prompten
- `workflow` använder denna relation för att beskriva stegordning

## Skapandeflöde

### Skapa prompt via admin eller admin-MCP

När en prompt skapas ska systemet:

1. skapa rad i `catalog_prompts`
2. skapa obligatorisk `generell` variant i `catalog_prompt_variants`
3. sätta status till `draft`

Obligatoriskt vid skapande:

- `slug`
- generell titel
- generell summary
- generell prompttext

Valfritt direkt:

- ikon
- bildnyckel
- färgtema
- exempel
- målgruppslabel
- tonhint

### Lägg till kontextvarianter

Efter skapande kan redaktionen lägga till varianter för:

- `skola`
- `kommun`
- `företag`
- `förening`
- `privat`

Varianterna ska i första versionen främst ändra presentation och exempel,
inte skapa helt separata promptfamiljer.

### Skapa paket eller arbetssätt

När ett paket skapas ska systemet:

1. skapa rad i `catalog_packages`
2. skapa obligatorisk `generell` variant i `catalog_package_variants`
3. sätta status till `draft`

När prompts kopplas in används `catalog_package_items` för:

- ordning
- stegtext
- stegintroduktion
- obligatorisk/valfri-markering

## Chattskapande

### Enskild prompt från chatt

Admin-MCP/Claude ska kunna skapa en ny prompt direkt från chatt som:

- baskärna i `catalog_prompts`
- `generell` variant i `catalog_prompt_variants`
- status `draft`

### Helt paket eller arbetssätt från chatt

Admin-MCP/Claude ska kunna skapa ett helt paket i ett svep:

- ett paket som `draft`
- flera nya underliggande prompts som `draft`
- generella varianter för samtliga
- relationer i `catalog_package_items`

I första versionen ska chattflödet inte behöva skapa alla kontextvarianter.
Det ska i stället skapa en fungerande generell grund och förbereda
strukturerade fält för framtida kontextvarianter.

## Publiceringsregler

### Prompt

En prompt får publiceras när:

- den har en `generell` variant
- obligatoriska fält är ifyllda

### Paket

Ett paket får publiceras när:

- det har en `generell` variant
- det innehåller minst en prompt
- alla ingående prompts är publicerade

Detta förhindrar att publicerade paket pekar på utkast.

## Läsmodell för frontend och hostad MCP

Frontend och hostad MCP ska läsa samma publicerade katalogdata.

Rekommenderade läsytor:

- `list_published_prompts(context_key)`
- `get_published_prompt(slug, context_key)`
- `list_published_packages(context_key, package_type)`
- `get_published_package(slug, context_key)`
- `list_published_package_prompts(package_slug, context_key)`

Fallbacklogik ska ligga i läslagret:

1. försök vald kontext
2. fall tillbaka till `generell`

Frontend och MCP ska bara läsa `published`-innehåll i första versionen.

## Adminoperationer i första versionen

Minsta kompletta skrivplattform:

- skapa promptutkast
- uppdatera promptutkast
- lägga till/uppdatera promptvariant
- publicera prompt
- skapa paketutkast
- uppdatera paketutkast
- lägga till/uppdatera paketvariant
- lägga till prompt i paket
- uppdatera ordning och stegcopy
- ta bort prompt från paket
- publicera paket
- skapa promptutkast från chatt
- skapa paketutkast från chatt

## Utanför scope / nästa specs

Följande ska beskrivas i separata specs:

- auth/auktorisering för admin-MCP och publicering
- sök/indexering och ranking på `app.promptbanken.se`
- domän- och produktompositionering (`kommun` → `app`)
- fri mediauppladdning
- versionshistorik/revisioner utöver `draft`/`published`
