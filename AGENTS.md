# Projektinstruktioner for Codex

Detta repo ar Promptbanken: en svensk kommunal promptkatalog med statisk/Vite-frontend, Supabase-inloggning/adminyta, en FastAPI-gateway mot Ollama och en lokal MCP skill router. Anvand den har filen som snabbstart innan du laser bredare dokumentation.

## Snabb orientering

- Frontendens publika sidor ligger i root: `index.html`, `promptbanken.html`, `prompts.html`, `help.html`, `mcp.html`, `providers.html`, `local-chat.html`.
- Stora frontendfiler: `script.js` och `style.css`. Gor sma, riktade andringar och sok efter befintliga funktioner/klasser innan du lagger till nya monster.
- Modern modulbaserad auth/admin-frontend ligger i `src/`: `supabaseClient.js`, `auth.js`, `login.js`, `admin.js`.
- Vite bygger flera HTML-ingangar via `vite.config.js`: alla `.html`-filer i rooten inkluderas som rollupOptions.input.
- `vite-plugin-static-copy` kopierar `prompts.json`, `prompts/`, `script.js`, `style.css` och `.nojekyll` till `dist/`. Vite kopierar INTE statiska rotfiler automatiskt utan detta plugin — lagg till nya statiska filer i vite.config.js om de behovs pa den deployade sidan.
- Backend for lokal LLM-gateway ligger i `backend/app/`. Startpunkt: `backend/app/main.py`.
- MCP-servern ligger i `mcp-server/`. Den har egen `server/`, `prompts/`, `scripts/`, `requirements.txt` och `package.json`.
- Prompttext finns dubbelt: `prompts/*.txt` for huvudprojektet och `mcp-server/prompts/*.txt` for MCP-paketet. Hall dem synkade nar en prompt ska galla bada ytorna.
- Skillmetadata finns i `skills.json` och `mcp-server/skills.json`. Uppdatera relevanta metadata samtidigt som promptfiler.
- Supabase-schema och RLS finns i `supabase/migrations/`; verifieringsplaner finns i `supabase/tests/`.
- Projektspecifika agentskills finns under `.agents/skills/`, framfor allt Supabase-relaterade instruktioner.

## Vanliga kommandon

Kor fran repo-roten om inget annat anges.

```powershell
npm install
npm run web:dev
npm run build
npm run preview
```

MCP-router:

```powershell
npm run setup:python
npm run check:python
npm run dev
```

Backend-gateway:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:OLLAMA_BASE_URL = "http://localhost:11434"
$env:MODEL_TIMEOUT_SECONDS = "300"
uvicorn app.main:app --reload --port 8001
```

Docker for community edition:

```powershell
docker compose up --build
```

## Verifiering

- Vid frontendandringar: kor minst `npm run build`.
- Vid auth/adminandringar: testa med Vite och `.env.local` med `VITE_SUPABASE_URL` och `VITE_SUPABASE_PUBLISHABLE_KEY`. Exponera aldrig service-role-nycklar i frontend.
- Vid backendandringar: starta `uvicorn app.main:app --reload --port 8001` fran `backend/` och kontrollera relevanta endpoints, sarskilt `/api/providers`, `/api/models`, `/api/run` eller stream-endpoints.
- Vid MCP-andringar: kor `npm run check:python` och starta `npm run dev`. MCP-servern ar stdio-baserad och kan se ut att vanta nar den fungerar.
- Vid Supabaseandringar: las `supabase/README.md`, applicera migrationer i ordning i staging och kor relevanta SQL-scenarier i `supabase/tests/`.

Det finns inga tydliga repo-tester for all frontend/backendlogik. Nar automatiska tester saknas, dokumentera exakt vilken manuell kontroll du gjorde.

## Kod- och arkitekturregler

- Hall svenska anvandartexter konsekventa med befintlig ton: klarsprak, kommunal kontext, GDPR/EU AI Act-medvetenhet.
- Forandra inte publika promptar, compliance-texter eller RLS-policyer utan att forsta konsekvensen for alla ytor.
- Undvik stora refaktorer i `script.js` och `style.css` om uppgiften ar smal. Dessa filer ar breda och riskerar regressionsfel.
- Ateranvand befintliga helpers i `src/auth.js` och `src/supabaseClient.js` for session och Supabase-klient.
- Frontend ska bara anvanda publishable Supabase key via `VITE_SUPABASE_PUBLISHABLE_KEY`.
- Backendens Ollama-konfiguration styrs via miljo, bland annat `OLLAMA_BASE_URL` och `MODEL_TIMEOUT_SECONDS`.
- MCP-servern ska leverera metadata, routing och prompttext. Den ska inte sjalv kora en LLM.
- Om du lagger till en prompt: uppdatera promptfil, metadata, eventuell statisk katalog och MCP-kopia sa att webben och MCP inte divergerar.
- Om du andrar databasytan: prioritera RLS, grants, rollbackbarhet och staging-verifiering.

## Fallgropar

- `README.md` innehaller mojibake i vissa avsnitt. Tolka projektets avsikt fran koden och andra filer innan du mekaniskt kopierar text darifran.
- `node_modules/` och `dist/` kan finnas lokalt. Andra inte genererade eller installerade filer om inte uppgiften uttryckligen kraver det.
- Rootens `package.json` startar MCP via wrapper-skript i `mcp-server/scripts/`; `mcp-server/package.json` gor motsvarande fran undermappen.
- GitHub Actions bygger via `.github/workflows/deploy.yml` och deployar `dist/` till GitHub Pages. Pages-kallan maste vara satt till "GitHub Actions" i repo-installningarna, inte "Deploy from branch".
- `import.meta.env.VITE_*`-variabler bakas in vid bygget — de kravs som GitHub Secrets (`VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`) i repot; annars ar de undefined pa live-sidan.
- `script.js` och `style.css` ar INTE bundlade av Vite (de innehaller inga ES-moduler). De kopieras som-ar till `dist/` via vite-plugin-static-copy och maste inte ha `import`-satser.
- Om `prompts.json` eller `prompts/*.txt` saknas i `dist/` visar `promptbanken.html` "0 prompter / 0 kategorier" och fastnar pa "Laddar". Verifiera alltid med `ls dist/prompts/` efter ett bygge.
- Lokalt inloggat lage kraver bade Supabase Auth-anvandare, `public.profiles` och kopplad `public.workspaces`-rad.

## Rekommenderad arbetsordning for kodagenter

1. Las denna fil, `package.json` och endast de README-avsnitt som ror uppgiften.
2. Sok med `rg` efter relevanta funktioner, ids, CSS-klasser eller prompt-id innan du oppnar stora filer.
3. Identifiera vilken yta som paverkas: statisk webb, `src/` auth/admin, backend, MCP eller Supabase.
4. Gor minsta sammanhangsriktiga andring.
5. Kor den smalaste relevanta verifieringen fran avsnittet ovan.
6. Redovisa andrade filer och verifiering kortfattat.
