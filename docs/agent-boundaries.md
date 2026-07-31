# Agentgränser för Promptbanken

Datum: 2026-07-31

Detta dokument är den operativa skrivpolicyn för Mob AI. Modulkartan beskriver
systemet; denna fil beskriver vad en agent får ändra. Ett konkret uppdragskort
får göra gränsen smalare, aldrig bredare utan ett nytt beslut.

## Gemensamma regler

- Läsåtkomst är bred, men skrivåtkomst ska vara explicit och liten.
- En agent ska stoppa och återlämna uppgiften om lösningen kräver en fil
  utanför skrivytan.
- Befintliga, orelaterade ändringar i arbetskatalogen ska bevaras.
- Hemligheter, service-role-nycklar och produktionsdata får aldrig skrivas in
  i repo, loggar eller frontend.
- Genererade mappar som `dist/` och installerade beroenden ska inte ändras.
- En implementerande agent får inte ensam vara kontraktsdomare för samma
  ändring.

## Modulgränser

| Agent | Tillåten skrivyta | Känsliga eller förbjudna ytor | Obligatorisk verifiering |
| --- | --- | --- | --- |
| Innehållsagent | `prompts/*.txt`, `prompts.json`, `skills.json`, motsvarande filer i `mcp-server/` och paketmetadata | Produktkod, Supabase-migrationer och osynkade enkelkopior | `promptbanken-content-sync`, register-/filkontroll och `npm run build` när webbens katalog påverkas |
| Landingagent | `index.html`, överenskomna publika marketingsidor och uttryckligen namngivna landing-selektorer i `style.css` | Kataloglogik, `src/`, Supabase och icke namngivna CSS-selektorer | `npm run build`, desktop/mobil-kontroll och kontroll mot `DESIGN.md`/`PRODUCT.md` |
| Katalog-UI-extraktionsagent | Endast filer uttryckligen angivna i en godkänd extraktionsplan | Nya katalogfunktioner i monoliten utan avgränsning; Supabase och innehåll | Bygge, relevanta användarflöden och beteendejämförelse före/efter |
| Adminagent | Namngivna filer i `src/` och tillhörande admin-HTML | RLS, migrationer, katalogmonoliten och generell `style.css` utan samgranskning | `npm run build`, auth-/rollflöden mot avsedd miljö och kontroll att publishable key används |
| Supabaseagent | Nya migrationer och relevanta scenarier i `supabase/tests/` | Frontendkod, hostad MCP och historiska migrationer | Läsning av `supabase/README.md`, relevanta SQL-tester, grants/RLS-kontroll och rollbackbedömning |
| Lokal MCP-agent | Namngivna moduler under `mcp-server/server/`, scripts och MCP-specifika tester | `mcp_server.py`, innehållsregister, router och riskkontroll om de inte uttryckligen ingår | `npm run check:python`, relevanta Python-tester och start av stdio-servern |
| Lokal chattagent | Namngivna moduler under `backend/app/` och backendtester | Supabase, webbens katalog och delade risk-/routingkopior om de inte uttryckligen ingår | Start av FastAPI och kontroll av berörda endpoints/streamflöden |
| Routingagent | Samtliga berörda kopior av `skill_router.py` i samma uppgift | Transportregistrering och riskregler | Enhetstester för rangordning och jämförelse mellan kopior/konsumenter |
| Riskagent | Samtliga berörda kopior av `risk_checker.py` i samma uppgift | Transport, UI och compliance-copy utanför riskkontraktet | Samma riskfall mot alla kopior samt regressionstest för kända fynd |
| Hostad MCP-katalogagent | Katalogmodulen i det hostade MCP-repot inom public-gruppen | Auth, Valvet, transport och kontraktsfil utan separat beslut | Public-profilens MCP-kontraktstest |
| Valvetagent | `vault.py`, Valvet-verktyg och tillhörande tester i det hostade MCP-repot | Publik katalog, auth och transport | Vault-gruppens kontrakt, kvoter, blocked calls och skrivloggning |
| Auth-/nyckelagent | Authmiddleware och funktioner för MCP-nyckelkontext | Verktygsimplementationer, Valvet och katalog | Nyckel-, plan-, workspace-, CORS- och blocked-call-scenarier |
| Kontraktsdomare | Tester, rapporter och kontraktsbedömning; kontraktsfiler endast genom separat kontraktsuppdrag | Implementationskod i uppgiften som domaren granskar | Full relevant kontraktsprofil och dokumenterat domslut |
| Releaseagent | Ingen produktkod som standard; endast uttryckligen godkänd releasekonfiguration eller versionsmetadata | Funktionella ändringar under releasepasset | Git-status, bygge, deploystatus, health endpoints och avtalade liveflöden |

## Kollisionspunkter

### `style.css`

Uppdragskortet ska ange exakta selektorer eller sektioner. Ändringen ska
granskas på alla sidor som använder dem. Generell upprensning får inte följa
med en smal UI-uppgift.

### `mcp_server.py`

Filen är en kompositionsyta, inte en modulagents normala ägande. Ändringar
kräver namngivna verktyg/endpoints, full relevant MCP-kontraktsprofil och en
separat kontraktsdomare.

### Duplicerad routing och riskkontroll

Tills ett delat paket finns ska en och samma uppgift omfatta alla kopior som
förväntas ha samma beteende. Två agenter får inte ändra varsin kopia
parallellt.

## Mognadsgrindar

En modul kan flyttas från röd till gul när den har:

- en egen namngiven kod- eller innehållsyta;
- ett beskrivet in- och utkontrakt;
- minst ett reproducerbart verifieringsflöde.

En modul kan flyttas från gul till grön när:

- den inte kräver ospecificerade ändringar i en kollisionspunkt;
- kontraktet är maskinläsbart eller tillräckligt starkt automatiserat;
- agenten kan slutföra en normal uppgift utan att skriva i en annan modul.

Ändringar av mognadsnivå ska uppdateras både här och i
`docs/module-map-2026-07-31.md`.
