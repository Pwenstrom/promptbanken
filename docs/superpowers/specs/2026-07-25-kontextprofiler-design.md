# Kombinerbara kontextprofiler för katalogläsning

**Datum:** 2026-07-25
**Status:** Utkast för review

## Bakgrund

Den dynamiska katalogplattformen (`docs/superpowers/specs/2026-07-21-dynamisk-katalogplattform-design.md`)
har redan en `context_key`-modell: varje prompt/paket kan ha varianter för
`generell`, `skola`, `kommun`, `företag`, `förening`, `privat`, med `generell`
som obligatorisk fallback. Läsflödet stödjer i dag bara **en** vald
`context_key` åt gången.

Nästa steg i lanseringsordningen (octopus-planen) är att en läsare ska kunna
tillhöra flera kontexter samtidigt — t.ex. både `kommun` och `skola` — och få
relevant innehåll för alla sina profiler, inte bara en.

## Produktgräns

Denna spec gäller enbart **läsflödet**:

- read-RPC:er i Supabase (webb + hostad/lokal MCP)
- hur flera valda kontextprofiler kombineras vid listning och detaljvisning
- var profilvalet lagras hos läsaren
- motsvarande parameterändring i MCP-verktygen

Skrivsidan (datamodell, `context_key`-enum, publiceringsregler,
admin-/chattskapande av varianter) ändras inte av denna spec — den beskrivs
redan i 2026-07-21-specen och ligger fast.

Utanför scope:

- kontobunden lagring av profilval
- sammanslagning/syntes av flera varianters text till en gemensam text
- ranking/prioritering av profiler utöver den ordning läsaren angav dem i
- ändringar i publiceringsregler eller adminformulär

## Beslut

### 1. Read-RPC:er tar emot en array av context_keys

Samtliga read-RPC:er byter parameter från `p_context_key text` till
`p_context_keys text[]`, default `array['generell']`:

- `list_published_prompts(p_context_keys text[])`
- `get_published_prompt(p_slug text, p_context_keys text[])`
- `list_published_packages(p_context_keys text[], p_package_type text default null)`
- `get_published_package(p_slug text, p_context_keys text[])`
- `list_published_package_prompts(p_package_slug text, p_context_keys text[])`

Ordningen i arrayen är läsarens egen prioritetsordning (första valda profil
väger tyngst där det behövs, se listbeteende nedan).

### 2. Detaljfunktioner returnerar alla matchande varianter

`get_published_prompt` och `get_published_package` returnerar **en rad per
matchande context_key** i den ordning arrayen anger, plus alltid en
`generell`-rad som garanterad fallback om ingen av de valda profilerna har en
egen variant.

Exempel: läsaren har valt `['kommun', 'skola']` och prompten har varianter
för både `kommun` och `skola` → svaret innehåller två rader (kommun, skola).
Har prompten bara en `skola`-variant → svaret innehåller en rad (skola) plus
`generell` som fallback-referens.

### 3. Listfunktioner dedupar till en rad per post

`list_published_prompts`, `list_published_packages` och
`list_published_package_prompts` returnerar **exakt en rad per
prompt/paket-id**, oavsett hur många av de valda profilerna som har egna
varianter.

Copy på listraden hämtas från **första matchande profilen** i den ordning
läsaren angav sina profiler; om ingen av profilerna matchar används
`generell`. Detta skiljer sig medvetet från detaljvyn, som visar alla
matchande varianter.

### 4. Detaljvy: flikar mellan matchande varianter

Webbfrontend visar variantväxlare (flikar/knappar, t.ex. "Kommun" / "Skola")
på prompt- och paketsidor när fler än en profilvariant matchar. Finns bara en
matchande variant (eller bara `generell`-fallback) visas ingen flikrad.

### 5. Profilval lagras lokalt, inte på konto

Läsarens valda kontextprofiler sparas i `localStorage` i webben. Ingen ny
kolumn eller tabell för användarkonto krävs. MCP-anrop skickar
`context_keys` som ett vanligt tool-parameter per anrop — servern håller
inget profil-state mellan anrop.

### 6. MCP och webb delar samma parameterform

`mcp-server/server/catalog.py` och motsvarande `@mcp.tool()`-funktioner i
`mcp_server.py` byter `context_key: str = "generell"` mot
`context_keys: list[str] = ["generell"]` och anropar samma
array-medvetna read-RPC:er som webben. Det håller webb och MCP i synk enligt
grundprincipen "frontend och hostad MCP läser samma publicerade katalogdata"
från 2026-07-21-specen.

## Datamodell

Ingen schemaändring. `catalog_prompts`, `catalog_prompt_variants`,
`catalog_packages`, `catalog_package_variants`, `catalog_package_items` och
`context_key`-checken (`generell`, `skola`, `kommun`, `företag`, `förening`,
`privat`) är oförändrade. Endast läs-RPC-signaturerna och deras interna
join-/coalesce-logik ändras.

## Läsmodell i detalj

### Listning (dedup, en rad per post)

```sql
-- pseudologik för list_published_prompts(p_context_keys text[])
select cp.*,
       coalesce(
         (select v.title
            from catalog_prompt_variants v
           where v.prompt_id = cp.id
             and v.context_key = any(p_context_keys)
           order by array_position(p_context_keys, v.context_key)
           limit 1),
         (select title from catalog_prompt_variants
           where prompt_id = cp.id and context_key = 'generell')
       ) as title
  from catalog_prompts cp
 where cp.status = 'published';
```

Samma mönster gäller `summary`, `intro_text`, `audience_label` m.fl. i
paketvarianten.

### Detaljvy (alla matchande varianter + garanterad generell)

```sql
-- pseudologik för get_published_prompt(p_slug text, p_context_keys text[])
select v.*
  from catalog_prompt_variants v
  join catalog_prompts cp on cp.id = v.prompt_id
 where cp.slug = p_slug
   and cp.status = 'published'
   and (v.context_key = any(p_context_keys) or v.context_key = 'generell')
 order by
   case when v.context_key = 'generell' then 1 else 0 end,
   array_position(p_context_keys, v.context_key);
```

`array_position` returnerar `null` för `generell` när den inte finns i
arrayen — sorteringen ovan hanterar det explicit så `generell` alltid hamnar
sist bland de returnerade raderna.

### list_published_package_prompts

Samma dedup-princip som `list_published_prompts`, men joinat via
`catalog_package_items` och med relationfälten (`sort_order`, `step_title`,
`step_intro`, `is_required`) oförändrade från 2026-07-21-specen.

## MCP-gränssnitt

```python
def list_published_prompts(context_keys: list[str] = ["generell"]): ...
def get_published_prompt(slug: str, context_keys: list[str] = ["generell"]): ...
def list_published_packages(context_keys: list[str] = ["generell"], package_type: str | None = None): ...
def get_published_package(slug: str, context_keys: list[str] = ["generell"]): ...
def list_published_package_prompts(package_slug: str, context_keys: list[str] = ["generell"]): ...
```

`@mcp.tool()`-wrapperna i `mcp_server.py` exponerar samma
`context_keys`-parameter till MCP-klienten (inget separat profil-state på
serversidan).

## Frontend-gränssnitt

- Nytt profilval (kryssrutor) i UI: Kommun, Skola, Företag, Förening, Privat.
- Valet sparas i `localStorage` under en egen nyckel (t.ex.
  `promptbankenContextProfiles`), oberoende av Supabase-konto.
- Listvyer anropar read-RPC:erna med den sparade arrayen; ändras valet,
  anropas listan om.
- Detaljvyer renderar variantväxlare enligt regel 4 ovan.

## Utanför scope / nästa specs

- Kontobunden lagring av profilval för inloggade användare.
- Sammanslagning av flera matchande varianter till en enda text.
- Prioritets-/ranking-algoritm utöver läsarens egen valordning.
- Ändringar i publicerings- eller adminflöden för kontextvarianter.
