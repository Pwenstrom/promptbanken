# Modulkarta: Promptbanken, MCP och Valvet

Datum: 2026-07-31

## Syfte

Modulkartan är underlag för Promptbankens interna Mob AI-arbetssätt. Varje
modul ska kunna förbättras av en avgränsad agent utan att agenten behöver
äga hela systemet. Det centrala är modulens gränssnittsartefakt: kontraktet
som agenten får förändra innanför och måste verifiera mot.

Mognadsnivåer:

- **Grön:** redo för en egen agent nu.
- **Gul:** gränssnittet finns, men läcker eller delar en kollisionspunkt.
- **Röd:** måste styckas eller få ett tydligt kontrakt innan en vanlig
  feature-agent får arbeta självständigt.

Kartan omfattar både detta repo och den separat hostade MCP-tjänsten. En
filreferens betyder därför inte automatiskt att filen finns i detta repo.

## Hostad MCP (`mcp_promptbanken`)

| Modul | Ansvar | Gränssnitt utåt | Mognad |
| --- | --- | --- | --- |
| Katalog | `pro_templates.py` och verktygen för listning, sökning, hämtning och paket | Publika RPC:er in, public-gruppen i `mcp-contract.json` ut | **Grön.** Frusen efter ChatGPT-publicering enligt `DECISIONS.md` 2026-07-31. |
| Valvet | `vault.py`, tio CRUD-verktyg och kvoter | Nyckelbundna `app_private`-RPC:er, vault-gruppen i kontraktet och `mcp_write_attempts` | **Grön.** Byggd som separat modul från start. |
| Auth och nycklar | `get_mcp_key_context`, `_mcp_key_from_request` och `BearerAuthMiddleware` | Nyckelhash till plan- och workspace-kontext | **Grön.** Framtida scopes och OAuth ska landa här. |
| Sök och routing | `skill_router.py` och sökpoäng | Ren funktion: fråga, roll och målgrupp till rankad lista | **Grön.** Sidoeffektfri och testbar utan databas. |
| Riskkontroll | `risk_checker.py` | Text till riskfynd | **Grön med villkor.** Kopian finns i två repon och ska ägas samlat tills ett delat paket finns. |
| Guard och kontrakt | `hosted_guard.py`, `mcp-contract.json` och testrunner | Är systemets externa kontrakt och domare | **Grön som granskningsfunktion.** Ingen implementerande agent får ensam äga denna yta. |
| Transport | `mcp_server.py`, endpoints och FastMCP-komposition | Registrering och komposition | **Gul.** Tunn modul, men kollisionspunkt för alla verktyg. |

## Datalager (Supabase, ägs av Promptbanken-repot)

| Modul | Ansvar | Gränssnitt utåt | Mognad |
| --- | --- | --- | --- |
| Schema och RPC | Migrationer, grants, RLS och verifieringsscenarier | RPC-signaturer som beviljas till `anon` och `mcp_server` | **Gul.** Starkt teststöd finns i `supabase/tests/`, men en maskinläsbar RPC-kontraktsfil saknas. |

## Webbapp (`promptbanken`)

| Modul | Ansvar | Gränssnitt utåt | Mognad |
| --- | --- | --- | --- |
| Innehåll | `prompts/*.txt`, `prompts.json`, `skills.json` och paket | Registren och promptfilerna; synk verifieras med `promptbanken-content-sync` | **Grön.** Redan agentifierad i praktiken. |
| Landing och marketing | `index.html`, relaterade publika sidor och landing-delen av `style.css` | `DESIGN.md` och `PRODUCT.md` | **Grön.** Designagenten arbetar mot dessa dokument. |
| Katalog-UI | `script.js` och `promptbanken.html` | Saknar ett separat kontrakt; katalog, quick-input, favoriter, export och lokal chatt delar en monolit | **Röd.** Ska styckas innan en feature-agent får ensam äga ytan. |
| Admin och workspace-UI | `src/admin.js`, relaterade `src/`-moduler och Supabase Auth | RLS, RPC:er och rollhierarki | **Gul.** Egen körväg, men delar `style.css` och datakontrakt. |
| Lokal MCP | `mcp-server/` via stdio | Innehållsregistren och en egen process | **Grön med villkor.** Isolerad, men router och riskkontroll finns som kopior. |
| Lokal chatt | `backend/` som Ollama-gateway | Egen HTTP-yta | **Grön.** Kan utvecklas och verifieras oberoende. |

## Bärande gränssnittsartefakter

- `mcp-contract.json` för den hostade MCP:ns publika och privata verktygsyta.
- `DESIGN.md` och `PRODUCT.md` för produkt- och designbeslut i webbappen.
- Supabase-RPC:ernas signaturer, grants, RLS och SQL-tester.
- `prompts.json`, `skills.json`, promptfiler och paketmetadata för innehåll.

## Saknade artefakter

1. En maskinläsbar RPC-kontraktsfil för Supabase-lagret.
2. Ett modulkontrakt för katalog-UI efter att `script.js` har styckats.

## Delade kollisionspunkter

Följande ytor får inte ändras av en ensam modulagent utan separat granskning:

- `mcp_server.py`: kräver MCP-kontraktstest.
- `style.css`: kräver kontroll mot berörda sidor och designkritik.
- Kopior av `risk_checker.py` och `skill_router.py`: alla berörda kopior ska
  hanteras i samma uppgift tills ett delat paket har extraherats.

De operativa skrivgränserna finns i `docs/agent-boundaries.md`.
