# 🏛️ Promptmallar för kommun

Centraliserad webbplattform med AI-assisterade kommunikationsmallar för svenska kommuner. Dessa prompter hjälper handläggare skriva tydligare, kortare och mer invånarvänlig kommunikation.

Webbplatsen är även gjord för att kunna läsas av AI-agenter och indexeringstjänster:

- Webbsida: https://kommun.promptbanken.se
- Hjälp: https://kommun.promptbanken.se/help.html
- MCP-guide: https://kommun.promptbanken.se/mcp.html
- Statisk promptkatalog: https://kommun.promptbanken.se/prompts.html
- Promptmanifest: https://kommun.promptbanken.se/prompts.json
- Agentguide: https://kommun.promptbanken.se/llms.txt
- Remote MCP demo: https://mcp.promptbanken.se/sse

**Status:** ✅ Live på GitHub Pages | **Version:** 1.0.0

---

## 🎯 Vad är detta?

Promptmallar är färdiga instruktioner för AI-verktyg (ChatGPT, Claude, etc.) som hjälper till att:
- Skriva om texter till **klarspråk** för invånare
- Svara på **medborgarmejl** på ett vänligt sätt
- Skapa **FAQ:or**, **checklistor**, **rutiner**
- Strukturera **mötes-anteckningar** och **diskussioner**

Alla prompter är utformade med **GDPR** och **EU AI Act** i åtanke. Du ansvarar alltid för att anonymisera personuppgifter innan du kopierar.

---

## 🚀 Snabbstart

### Online (GitHub Pages)
1. Öppna: https://kommun.promptbanken.se
2. **Inställningar (⚙️)**: Klicka på kugghjulet i övre högra hörnet för att:
   -aktivera anpassade prompter om du vill.
   - Aktivera **Favoritläge** för att spara och visa favoriter
3. Välj ett prompt-kort
4. Klicka **"Visa exempel"** för att se vad du ska anonymisera
5. Klicka **"Kopiera prompt"** → prompen är i ditt urklipp
6. Klistra in i ditt AI-verktyg (ChatGPT, Claude, etc.)

### Lokal utveckling (utan Docker)
```bash
# Klona repo
git clone https://github.com/username/promptbanken.git
cd promptbanken

# 1) Starta backend (gateway mot Ollama)
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
# Vid långsamma lokala modeller: höj timeout (sekunder)
export MODEL_TIMEOUT_SECONDS=300
export OLLAMA_BASE_URL=http://localhost:11434
uvicorn app.main:app --reload --port 8001

# 2) I ett nytt terminalfönster: starta frontend
cd ..
python -m http.server 8000

# 3) Öppna i webbläsare
# Frontend: http://localhost:8000
# Backend docs: http://localhost:8001/docs
```

### Community Edition på Windows med Docker (rekommenderat)
Community Edition är local-first och använder endast Ollama via backend.

1. **Installera Docker Desktop för Windows** (med WSL2 aktiverat).
2. **Installera Ollama på Windows** och starta minst en modell, t.ex.:
   ```powershell
   ollama pull llama3.1:8b
   ```
3. **Klona repot** och gå till rotmappen:
   ```powershell
   git clone https://github.com/username/promptbanken.git
   cd promptbanken
   ```
4. **Starta frontend + backend med Docker Compose**:
   ```powershell
   docker compose up --build
   ```
   > Standard i `docker-compose.yml` är `OLLAMA_BASE_URL=http://host.docker.internal:11434`, vilket gör att backend-containern når Ollama som kör lokalt på Windows.
5. **Öppna appen**:
   - Frontend: `http://localhost:8080`
   - Backend API: `http://localhost:8001/docs`

#### Vanliga kommandon
```powershell
# Starta i bakgrunden
docker compose up -d --build

# Se loggar
docker compose logs -f

# Stoppa och ta bort containrar
docker compose down
```

### Starta backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8001
```

### Framtida förbättringar
- Byt MVP-token till riktig authn/authz (OIDC/SSO + roller).
- Nyckelrotation med versionshantering och audit-logg.
- Stöd för fler providers (Azure OpenAI, Ollama Cloud, Anthropic) via samma `ProviderConfigService`i PRO.

## 🌐 Deploy (GitHub Pages via Actions)

- Workflow: .github/workflows/pages.yml (triggas på push till main eller manuellt via Actions → pages).
- Första körning sätter Pages-källa till GitHub Actions och publicerar hela root-katalogen.
- Så verifierar du efter deploy:
  1. Öppna senaste körningen under Actions → pages → Deploy to GitHub Pages och kontrollera att den är grön.
  2. Följ `page_url` i körloggarna (ex. https://username.github.io/promptbanken).
  3. Ladda sidan: säkerställ att prompts renderas, copy/ℹ️-modal/favoriter fungerar, samt att footer-länkar (GDPR, AI-compliance, MIT-licens) öppnas.

---

## ✨ Nya funktioner

- **Inställningsmeny (⚙️)**: Kugghjulsmeny i övre högra hörnet för att aktivera avancerat läge och favoritläge
  - Responsiv design som anpassar sig för mobila enheter
  - Dropdown-meny som stannar inom viewport-gränser
  - Placerad i dedikerad container för att undvika överlappning med kort
- Kopiera utan anonymiserings-checkbox (snabbare flöde)
- Favoriter med stjärna + localStorage-cache
- Snabbmeny "⭐ Mina Favoriter" och knapp för att rensa alla
- ℹ️ "Se hela prompt"-modal för full text
- Ny prompt #15: 📣 Skapa informationsutskick

---

## MCP och agentanvändning

Promptbanken kan användas på två sätt:

1. Som vanlig webbplats där användaren läser och kopierar promptar manuellt.
2. Som MCP-källa i AI-klienter som stödjer MCP.

Remote MCP-demo:

```json
{
  "mcpServers": {
    "promptbanken": {
      "url": "https://mcp.promptbanken.se/sse"
    }
  }
}
```

För AI-agenter som bara kan läsa ett begränsat crawldjup finns:

- `llms.txt` med agentinstruktioner
- `prompts.html` som statisk promptkatalog
- `prompts.json` som manifest
- direkta filer under `prompts/*.txt`
- `robots.txt` och `sitemap.xml`

Rekommenderad agentinstruktion:

> När jag ber om svenska texter, kommunala underlag, mejl, rutiner, checklistor, informationsutskick, FAQ eller beslutsunderlag ska du först kontrollera om Promptbanken har en relevant mall. Om en mall passar ska du använda den och säga vilken mall du valt.

## 📋 Tillgängliga prompter (16 st.)

| # | Prompt | Syfte |
|---|--------|-------|
| 1 | Tydlighetskoll | Granska ansvar, beslut, nästa steg och risk för missförstånd |
| 2 | Skriv om till klarspråk | Gör text kortare och lättare att förstå |
| 3 | Svar på medborgarmejl | Skriv vänligt och sakligt svar |
| 4 | Gör en FAQ | Skapa frågor och svar från dokument |
| 5 | Skapa checklista | Omvandla instruktioner till checklista |
| 6 | Skriva kallelse | Skriv formell men enkel kallelse |
| 7 | Beslutsunderlag | Sammanfatta för beslutande organ |
| 8 | Rutiner & anvisningar | Gör instruktioner tydliga |
| 9 | Två versioner | Omvandla mellan formell och vardaglig text |
| 10 | Reflektionsfrågor | Skapa frågor för djupare tänkande |
| 11 | Samtalskompass | Strukturera möte eller workshop |
| 12 | Sammanfattning | Förkorta längre text |
| 13 | Strukturera anteckningar | Organisera mötesanteckningar |
| 14 | Diskussionsfrågor | Driva diskussion framåt |
| 15 | Extrahera nyckelord | Identifiera centrala termer |
| 16 | Skapa informationsutskick | Skriv tydligt utskick med rubrik, sammanfattning och nästa steg |

---

## 🔒 Säkerhet & Compliance

Denna plattform följer:
- **EU AI Act** – klassificerad som "Low-Risk AI Application" (LAAF)
- **GDPR** – ingen data lagras lokalt; du är ansvarig för anonymisering
- **Offentligrättslig** – granskat av dataskyddssamordnare och juridik

**Viktigt:** Du är ansvarig för att anonymisera personuppgifter innan du kopierar prompen. Klicka **"Visa exempel"** på varje kort för att se vad du ska ta bort.

**Läs mer:**
- [EU AI Act Compliance](AI-COMPLIANCE.md)
- [GDPR Policy](GDPR-POLICY.md)
- [Compliance Review Checklista](COMPLIANCE-REVIEW-CHECKLIST.md)

---

## 🛠️ Teknisk arkitektur

- **Frontend:** Vanilla JavaScript (ingen ramverk)
- **Backend:** FastAPI-gateway (`/api/providers`, `/api/models`, `/api/run`) för flera providers (lokal Ollama, Ollama Cloud, OpenAI)
- **Providers:** Lokal Ollama + valfria molnproviders via backend-proxy (frontend anropar aldrig leverantörer direkt)
- **Data:** JSON-config + txt-filer (gitbar)
- **Copy-mekanik:** navigator.clipboard API
- **Hosting:** Frontend statiskt + lokal backend-tjänst
- **Design:** CSS Grid/Flexbox, responsiv, WCAG AA

### GDPR och fritextruta (egen roll)

- **Ingen data lagras:** Allt du skriver i fritextrutan för "Annan/Egen roll" hanteras endast lokalt i din webbläsare och sparas inte.
- **Personuppgifter:** Ange aldrig personuppgifter i fritextrutan. Du ansvarar för att all text är anonymiserad.
- **Privacy by design:** Ingen information skickas till server eller tredje part.

### Inställningsmeny (Settings Menu)
- **Positionering:** `.settings-container` med flexbox (justify-content: flex-end) för högerjustering
- **Responsiv:** Media query (@768px) anpassar dropdown-bredd för mobila enheter
- **Z-index:** 1001 för att ligga över annat innehåll
- **Viewport-säker:** `max-width: calc(100vw - 2rem)` förhåller overflow
- **Design-motivering:** Placerad i separat container utanför `<main>` för att undvika överlappning med prompt-kort i dokumentflödet

**Filstruktur:**
```
├── index.html              # Promptkatalog och användargränssnitt
├── help.html               # Hjälp och vägledning
├── mcp.html                # MCP-guide
├── prompts.html            # Statisk promptkatalog för indexering/agenter
├── llms.txt                # Agentinstruktioner
├── robots.txt              # Indexeringspolicy
├── sitemap.xml             # Sitemap
├── local-chat.html         # Lokal chattsida
├── script.js               # Logik för startsidan, promptkort och filinläsning
├── local-chat.js           # Logik för lokal chatt via backend/Ollama
├── style.css               # Gemensam styling för startsidan
├── local-run.css           # Styling för lokal körning och local-chat
├── prompts.json            # Prompt-konfiguration
├── prompts/                # Promptfiler
├── backend/
│   ├── app/
│   │   ├── main.py         # API för modeller och chat/stream
│   │   └── llm_clients.py  # Koppling mot Ollama/modellbackend
│   └── Dockerfile
├── Dockerfile              # Frontend-container
├── docker-compose.yml      # Docker-setup
├── nginx.conf              # Reverse proxy för frontend/api
├── README.md
├── LICENSE
├── AI-COMPLIANCE.md
├── GDPR-POLICY.md
└── COMPLIANCE-REVIEW-CHECKLIST.md

---

🤝 Bidra

Vi tar gärna emot idéer och förbättringar – men bidrag hanteras manuellt och kontrollerat.

🐞 Rapportera problem

Öppna ett GitHub Issue.

💡 Föreslå ny prompt

Skicka ditt förslag via e-post istället för Pull Request.

📧 Maila: peter@promptbanken.se

Inkludera:

Prompten

Kort beskrivning av användningsområde

Exempel på input/output (om möjligt)

🚫 Pull Requests

Vi tar i nuläget inte emot Pull Requests för nya prompts.
Detta för att säkerställa kvalitet, struktur och konsistens i promptbanken.

---

## 📜 Licens

MIT-licens © Peter Wenström. Se detaljer i [LICENSE](LICENSE)-filen i projektroten eller på GitHub: [promptbanken](https://github.com/BUsavsjo/promptbanken).

---

## ❓ FAQ

**F: Var lagras mina data när jag kopierar en prompt?**
A: Ingenstans! Clipboard API är lokal – data lämnar aldrig din webbläsare.

**F: Kan jag använda detta för hemlig/klassificerad information?**
A: Nej. Du måste se till att all data är anonymiserad före kopia. Se "Visa exempel" på varje prompt.

**F: Vilka AI-verktyg fungerar?**
A: Alla! ChatGPT, Claude, Gemini, etc. Kopiera bara prompen och klistra in i ditt verktyg.

**F: Kan jag redigera prompterna?**
A: Ja! Du kan redigera .txt-filerna och skapa pull requests. Eller använd dem som utgångspunkt för dina egna.

---

## Exportfunktionalitet

### Funktioner
- **LocalStorage**: Exportinställningar sparas lokalt i webbläsaren.
- **Exportmodul**: Användare kan öppna, kopiera och ladda ner instruktioner.
- **Knappsynlighet**: "Kopiera prompt"-knappen döljs automatiskt när "Anpassa prompt" (avancerat läge) är aktivt, och visas annars. Detta minskar risken för felkopiering och gör flödet tydligare.

### Testning
1. Kontrollera att LocalStorage sparar och hämtar data korrekt.
2. Verifiera att exportmodulen fungerar utan fel:
   - Öppna och stäng modalen.
   - Använd kopieringsknappen.
   - Ladda ner filen.

### Kända Begränsningar
- LocalStorage är begränsat till webbläsaren och kan rensas av användaren.
- Exportmodulen kräver JavaScript aktiverat.

---

## Deploy-Ready Version

### Compliance Information
- **EU AI Act**: Marked as a low-risk AI application.
- **GDPR**: Privacy notice and no data tracking.

### Deployment Steps
1. Ensure all prompts are visible and functional.
2. Verify AI Act disclaimer is displayed.
3. Deploy to the municipality's server.

### Version
- Current version: 1.0.0

*Skapad för att göra kommunal kommunikation tydligare, snabbare och bättre.* 🚀

## 🆕 Senaste ändringar (jan 2026)

- Snabbinmatningstexten ("quick input") injiceras nu automatiskt i alla promptflöden:
  - "Kopiera prompt" ersätter både `[klistra in här]` och `[TEXT]`-markörer med din snabbinmatning.
  - "Se hela prompt"-modal visar prompten med din snabbinmatning på rätt plats.
  - "Anpassa prompt" (export) inkluderar snabbinmatning i förhandsvisning och export.
- Gäller även prompten "📣 Skapa informationsutskick" och framtida prompts med `[TEXT]`-markör.
- Ingen snabbinmatning lagras eller skickas – allt sker lokalt i webbläsaren.
- förbättra UI på landningssida
- stöd för community ollama lokal backend och frontend med docker. 


## 🔒 Integritet och lokal hantering

- Ingen snabbinmatning eller promptdata lagras på servern eller skickas till tredje part.
- All bearbetning sker lokalt i din webbläsare.
- Endast favoriter och exportinställningar sparas i din webbläsares localStorage (kan rensas när som helst).
- Du ansvarar alltid för att anonymisera personuppgifter innan du kopierar eller exporterar en prompt.

### Export och kopiera prompt

- **Knappbeteende:**
  - När "Anpassa prompt" är aktivt, döljs knappen "Kopiera prompt" för att undvika förvirring.
  - När "Anpassa prompt" är inaktiv, visas knappen "Kopiera prompt" som vanligt.
- **Tillgänglighet:**
  - Fokus och tabbning fungerar korrekt oavsett knappens synlighet.
- **Användning:**
  - Aktivera "Anpassa prompt" via inställningsmenyn för att justera struktur och ton innan export.
  - Kopiera prompten direkt när "Anpassa prompt" är avstängd.
