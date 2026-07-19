# Rollbaserade rekommendationer (delprojekt 5)

**Datum:** 2026-07-19
**Status:** Godkänd design (rollmappning godkänd av Peter i konversationen 2026-07-19)
**Berörda repos:** `mcp_promptbanken` (ett nytt MCP-verktyg, ingen DB-ändring, ingen webbändring)

## Bakgrund

Sista delprojektet i Promptbanken/Valvet-visionens 6-punktslista. Ingen
befintlig data representerar en Valvet-användares yrkesroll — `profiles.role`
är bara behörighetsnivå (viewer/editor/.../platform_owner), inte
yrkesfunktion. Den enda plats roller finns som data är den statiska
`skills.json` (21 skills, fält `roles`/`audiences`, matchade av
`SkillRouter.route()` i `skill_router.py`).

## Produktbeslut (Peter, 2026-07-19)

- Rekommenderar **promptpaket** (de 7 områdena, delprojekt 3), inte
  enskilda mallar.
- Rollen **kommer från klienten** — AI-klienten frågar användaren om den
  inte redan vet rollen, och skickar den som en verktygsparameter. Ingen ny
  DB-kolumn, ingen lagrad roll, ingen webb-UI.
- Återanvänder **exakt samma rollvokabulär och matchningsmönster** som
  `SkillRouter.route()` redan använder (svensk normalisering + exakt
  jämförelse efter normalisering, inte fri textmatchning).
- Ytan är **bara MCP** — inget i Valvets webbflik ändras.

## Verktyg

**`recommend_packages(role: string)`** — nytt, read-only MCP-verktyg.
**Kräver ingen MCP-nyckel** (till skillnad från `list_active_packages` m.fl.)
— rollen skickas som parameter, resultatet beror inte på anroparens
identitet eller workspace. Ren funktion av `role` → matchande områden ur
den redan öppna `pro_prompt_templates`-datan.

## Rollmappning (statisk, i kod — godkänd av Peter)

| `area` | Rekommenderade roller |
|---|---|
| `kommunikation` | kommunikator, handlaggare, kundcenter |
| `forandringsledning` | samordnare, verksamhetsutvecklare, chef |
| `processer` | verksamhetsutvecklare, utredare, samordnare |
| `beslutsberedning` | utredare, handlaggare, chef, sekreterare |
| `visuellt` | kommunikator, pedagog |
| `ledarskap` | chef, samordnare |
| `arbetsbank` | universellt — ingen rollbegränsning (meta-verktyg för att bygga/förbättra egna mallar, inte kopplat till en specifik yrkesfunktion) |

Rollvokabulären (samma 13 värden som redan finns i `skills.json`):
`administrator`, `administratör`, `analytiker`, `chef`, `facilitator`,
`handlaggare`, `kommunikator`, `kundcenter`, `pedagog`, `samordnare`,
`sekreterare`, `utredare`, `verksamhetsutvecklare`. (Not: `administrator`/
`administratör` förekommer båda i källdatan — okorrigerad pre-existing
dubblett, inte denna specs problem att lösa.)

## Matchning

Återanvänder `SkillRouter._normalize` (statisk metod i `skill_router.py`,
redan bevisad kod — svensk NFKD-normalisering, `å→a` osv.) direkt, inga nya
normaliseringsregler. Algoritm:

1. `normalized_role = SkillRouter._normalize(role)`.
2. Om `normalized_role` matchar (exakt, efter normalisering) minst en roll
   i ett områdes rollista (eller området är `arbetsbank`, som alltid
   matchar): området är en rekommendation.
3. Om **ingen** roll i indata känns igen mot NÅGOT område (dvs. rollen är
   helt okänd, t.ex. felstavning eller en roll utanför vokabulären):
   returnera **alla 7 områden** med `role_recognized: false` — aldrig ett
   tomt svar (samma princip som `SkillRouter._fallback` redan tillämpar för
   `route_skill`).
4. Om rollen känns igen: returnera bara de matchande områdena (kan vara
   1–7 stycken; `arbetsbank` alltid med) med `role_recognized: true`.

Resultatet per område: `area`, `area_label`, antal mallar (`count(*)` mot
`pro_prompt_templates` för det området, hämtat en gång vid modulstart eller
per anrop — implementationsplanen avgör om cache behövs; datan ändras
sällan så ett enkelt per-anrop-RPC-anrop mot `list_pro_templates()` internt
räcker, ingen ny DB-funktion krävs).

## Verktygsschema

```json
{
  "name": "recommend_packages",
  "description": "Recommend prompt packages (areas) suited to a job role. Pass a short role term (e.g. 'chef', 'kommunikator') -- if the calling client doesn't know the user's role, it should ask the user first. If the role isn't recognized, all packages are returned with role_recognized=false rather than an empty result.",
  "inputSchema": {
    "type": "object",
    "properties": { "role": { "type": "string" } },
    "required": ["role"],
    "additionalProperties": false
  }
}
```

Svarsform: `{"role_recognized": bool, "packages": [{"area": str, "area_label": str, "template_count": int}]}`.

## Implementation (kort, litet ingrepp)

- Ny fil `mcp-server/server/package_recommendations.py`: den statiska
  rollmappningen (dict `area -> set[str] | None` där `None` = universellt)
  + funktionen `recommend(role: str, templates: list[dict]) -> dict`.
  Importerar `SkillRouter._normalize` från `skill_router.py` (redan i
  samma paket, ingen cirkelimport eftersom `skill_router.py` inte
  importerar något paketspecifikt).
- `mcp_server.py`: samma tre inkopplingsställen som delprojekt 4
  (`_tool_definitions()`, manuell JSON-RPC-dispatch, `@mcp.tool()`) plus en
  REST-endpoint `GET /api/v1/vault/packages/recommendations?role=...`
  (läsverktyg, samma REST-mönster som `/api/v1/pro-templates`).
- `hosted_guard.py`: lägg till `recommend_packages` i allowlist med
  tillåtet argument `{"role"}`.
- Datan hämtas via befintlig `pro_templates.list_pro_templates("")`
  (redan öppen, kräver ingen nyckel) för att räkna mallar per område —
  ingen ny RPC eller migration behövs alls. **Detta delprojekt kräver
  ingen DB-migration.**

## Felhantering

`role` som tom sträng eller icke-sträng avvisas av `hosted_guard.py`/
dispatchens vanliga argumentvalidering (samma mönster som övriga verktyg).
Inga andra felvägar — verktyget är rent beräknande, inga externa anrop
utöver den redan cachade/öppna mall-listan.

## Verifiering

1. `curl tools/call recommend_packages` med `role: "chef"` → `ledarskap`,
   `forandringsledning`, `beslutsberedning`, `arbetsbank` (4 områden),
   `role_recognized: true`.
2. Samma med `role: "något-okänt"` → alla 7 områden, `role_recognized: false`.
3. Samma med `role: "KOMMUNIKATÖR"` (versaler) → matchar ändå (normalisering
   är case-insensitive), bekräftar att `SkillRouter._normalize` återanvänds
   korrekt.
4. `python -m py_compile` på de ändrade filerna.

## Utanför scope

Ny DB-kolumn/lagrad roll, webb-UI, enskilda mall-rekommendationer (bara
delprojekt 3:s paket), rollbaserad filtrering av `list_pro_templates` eller
`copy_template_to_valvet` (dessa förblir helt rolloberoende).
