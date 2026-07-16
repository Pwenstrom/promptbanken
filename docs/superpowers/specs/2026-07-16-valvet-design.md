# Valvet — Fas 1: fristående personligt AI-valv

Status: godkänd för planering (Fas 1)
Datum: 2026-07-16
Berör repon: `promptbanken` (denna spec bor här — äger datamodellen), `mcp_promptbanken` (nya MCP-verktyg), `valvet_promptbanken` (webbapp, nytt repo på `C:\Users\petwen\OneDrive - Höglandsförbundet\Projekt\valvet_promptbanken`)

## Bakgrund

Promptbanken har hittills bara haft en kommunal ingång (`kommun.promptbanken.se`).
Valvet är en ny, bredare ingång: ett personligt lager för egna prompts och
assistenter som fungerar identiskt i ChatGPT och Claude via MCP. Samma konto,
databas, MCP-server, nycklar, betalning och arbetsytor som idag — bara en ny
ingång, ny branding och en egen gräns-/kvotmodell.

Långsiktig vision (moduler, versionering, semantisk sökning, delade valv,
inbäddning i kommun-sidan) finns beskriven men är **inte** del av Fas 1 — se
"Uttryckligen utanför scope" nedan.

## Modularkitektur (kort)

- **Valvet** = basmodul: egna insättningar (prompt/assistant), sökning, MCP,
  arkivering.
- **Kommun** = innehållsmodul: 21 fria kommunala mallar + premium, oförändrad
  i Fas 1.
- Delat: konto, inloggning, Supabase-databas, MCP-server, `api_keys`,
  betalning/plan, `workspaces`.
- Separat per modul: landningssida, målgrupp, gränser för antal poster,
  vilka MCP-verktyg som är synliga.

## Datamodell (migrationer i `promptbanken`-repot)

1. **`content_item_type`-enum**: lägg till värdet `'assistant'`. Ren etikett,
   samma kolumner som `'prompt'` (ingen ny fältstruktur).
2. **`content_items.module`** (ny kolumn, text/enum `'kommun' | 'valvet'`,
   `not null default 'kommun'`, backfyllar alla befintliga rader till
   `'kommun'`). Detta är kroken som separerar de två produkternas gränser
   och MCP-synlighet utan att dela upp databasen.
   - **Immutable efter skapande**: ny trigger (eller utökning av
     `enforce_content_access_model`) avvisar UPDATE där
     `new.module is distinct from old.module`. Förhindrar att en post
     omklassas för att kringgå en gräns.
3. **Vault-tak beräknas, lagras inte**: 50 (free) / 1000 (pro), avläst
   direkt från `workspaces.plan` i samma sats som gränskontrollen (samma
   mönster som `app_private.has_active_pro_entitlement()` redan använder —
   härlett tillstånd, inte en synkad kolumn). Undviker att behöva uppdatera
   alla befintliga upp-/nedgraderings-RPC:er (`create_pro_order`,
   `admin_downgrade_pro_order`, `redeem_pro_invite`, m.fl.) som sätter
   `max_prompts` men skulle annars behöva sättas om även för en ny
   `max_vault_items`-kolumn.
4. **Ny gräns-trigger-gren** (bredvid befintlig, oförändrad
   `enforce_content_access_model` som fortsätter styra `module='kommun'`):
   - Räknar `module='valvet' AND status<>'archived' AND owner_user_id=auth.uid()`
     inom samma workspace.
   - Blockerar när räkningen skulle överstiga `max_vault_items`.
   - **Triggas både vid INSERT och vid UPDATE som återaktiverar en post**
     (dvs. `old.status='archived' AND new.status<>'archived'` — en
     återställning). Utan detta kunde taket kringgås genom att arkivera och
     återställa poster. Arkiverade poster räknas aldrig mot taket.
   - Gäller oavsett kanal (webbens direkta Supabase-insert eller MCP:s
     `save_my_item`/`update_my_item`-RPC:er) eftersom kontrollen ligger i
     databas-triggern, inte i applikationslagret.
5. **`mcp_write_attempts`** (befintlig loggtabell, samma mönster som
   `save_workspace_prompt` redan använder): utökas med
   `idempotency_key text null` och en unik partiell index
   `(workspace_id, tool, idempotency_key) where idempotency_key is not null`.
   Används för både kvoträkning och idempotens (se nedan).

## Plangränser

| Funktion | Free | Pro |
|---|---|---|
| Aktiva valv-poster (`max_vault_items`) | 50 | 1000 |
| Typer | prompt, assistant | prompt, assistant |
| Skapa/redigera i webbapp | ja | ja |
| Läsa/lista/söka/hämta via MCP | ja | ja |
| Skapa via MCP (`save_my_item`) | ja, 5/kalendermånad | ja, ingen månadskvot |
| Uppdatera via MCP (`update_my_item`) | nej | ja |
| Arkivera/återställa via MCP (`archive_my_item`) | nej | ja |
| MCP-nycklar (delad pool med kommun) | 1 | 3 |
| Export | ja (JSON, se nedan) | ja (samma format) |

## MCP-verktyg (`mcp_promptbanken`-repot, nya tools bredvid befintliga — inget byts ut eller byter beteende)

Alla verktyg är bundna till anropande nyckels workspace via befintlig
`verify_mcp_key`-mekanism (samma modell som `get_workspace_prompts`/
`save_workspace_prompt` redan använder) — ingen tvärgång mellan workspaces
är möjlig. Alla filtrerar `module='valvet'`.

### Läsverktyg (Free + Pro)

- `list_my_items(type?, category?, status?)` — listar aktiva insättningar,
  scopat efter plan enligt samma privat/workspace-logik som
  `get_workspace_prompts` (free: bara privata; pro: privata + workspace-synliga).
- `search_my_items(query, type?, category?)` — söker titel/kategori/innehåll,
  samma scope-regler som ovan.
- `get_my_item(id)` — hämtar full post inkl. `updated_at` (behövs för
  optimistic locking vid efterföljande update).

### Skrivverktyg

- `save_my_item(idempotency_key, type, title, content, category?)`
  - **Idempotency key krävs.** Klient genererar (UUID/hash). Servern kollar
    `mcp_write_attempts` för en tidigare lyckad `save_my_item` med samma
    `(workspace_id, idempotency_key)` inom 24h — om funnen returneras samma
    resultat istället för att skapa en ny post. Skyddar mot dubbletter vid
    klient-timeout/retry, och dubbelräknar inte mot månadskvoten.
  - Free: avvisas om månadskvoten (5, räknat **per workspace**, aggregerat
    över alla nycklar på workspacet — inte per enskild nyckel) redan är
    förbrukad. Tydligt felmeddelande med hur många kvar/när det återställs.
  - Pro: ingen månadskvot, men samma tekniska rate limit som alla skrivverktyg
    (se nedan).
- `update_my_item(id, expected_updated_at, title?, content?, category?, status?)`
  - Pro-only (kollas via `has_active_pro_entitlement()`). Free får tydligt
    fel: "Uppgradera till Pro för att uppdatera via MCP".
  - **Optimistic locking:** `WHERE id=$1 AND workspace_id=$ws AND updated_at=$expected_updated_at`.
    Noll uppdaterade rader → explicit konfliktfel ("Posten har ändrats sedan
    du hämtade den — hämta på nytt med `get_my_item` och försök igen"), inte
    en tyst no-op.
- `archive_my_item(id, confirm, restore?)`
  - Pro-only för själva MCP-anropet (Free arkiverar/återställer bara via
    webbappen).
  - **`confirm` måste vara explicit `true`**, annars avvisas anropet med
    förklarande fel. Skydd mot att en AI-klient arkiverar fel post baserat på
    tvetydig instruktion eller injicerad text.
  - `restore=true` vänder status tillbaka (samma tak-kontroll som ovan gäller
    då, punkt 4 i datamodellen). Ingen separat 7:e verktyg.
  - Arkivering av en redan arkiverad post (eller återställning av en redan
    aktiv post) är en säker no-op, inte ett fel.

### Rate limiting — två separata lager

1. **Teknisk rate limit** (missbruksskydd, gäller alla skrivverktyg, alla
   planer): kort fönster, t.ex. max 20 anrop/minut per MCP-nyckel. Samma
   mönster som `save_workspace_prompt`s befintliga 60-sekundersgräns. Syfte:
   skydda servern, inte styra affärsplan.
2. **Månadskvot** (affärsgräns, bara Free, bara `save_my_item`): 5/kalendermånad
   per workspace, se ovan. Oberoende av (1) — båda kontrollerna måste passera.

## Webbapp (repo `valvet_promptbanken`, egen GitHub Pages-site, `valvet.promptbanken.se`)

Sju sidor: Logga in, Mina insättningar, Ny insättning, Sök, Redigera, Arkiv,
MCP-nyckel + installationsguide.

- Delat Supabase-projekt (`VITE_SUPABASE_URL`/`VITE_SUPABASE_PUBLISHABLE_KEY`
  som GitHub Secrets, samma mönster som `promptbanken`-repot). Auth/Supabase-
  helpers porteras in från `src/auth.js`/`src/supabaseClient.js` (kopia, inte
  tvärgående import mellan repon).
- Egen inloggningssession per domän — samma konto/lösenord fungerar på både
  `kommun.` och `valvet.`, men ingen delad cookie/SSO mellan domänerna i
  Fas 1.
- CRUD sker direkt mot Supabase via RLS (samma mönster som `admin.js`), inte
  via MCP-servern — MCP är enbart AI-klienternas ingång.
- **Ny insättning/Redigera:** typ-väljare (prompt/assistent), titel,
  innehåll, kategori (fritext, ingen Free-spärr eftersom Valvet Free redan
  är rymligare än kommun-Free).
- **Arkiv:** egen vy med återställ-knapp.
  - **Arkiveringsbekräftelse:** samma tvåstegsknapp-mönster som redan finns
    i `admin.html` ("Arkivera" → "Bekräfta arkivering?" inom ett par
    sekunder) — inte en `window.confirm()`.
- **MCP-nyckel:** samma `api_keys`-tabell/gräns som kommun (1 Free / 3 Pro,
  delad pool — samma nyckel fungerar mot både kommun- och valvet-verktygen).
  Installationsguide pekar mot `mcp.promptbanken.se` (samma hostade server).
- **Export:** JSON-nedladdning, filnamn `valvet-export-YYYY-MM-DD.json`,
  array av objekt:
  ```json
  [
    {
      "id": "uuid",
      "type": "prompt | assistant",
      "title": "string",
      "content": "string",
      "category": "string|null",
      "status": "draft|review|published|archived",
      "created_at": "ISO8601",
      "updated_at": "ISO8601"
    }
  ]
  ```
  Formatet är medvetet enkelt att återimportera senare (import är roadmap,
  inte Fas 1).

## Deployment

- Repo `valvet_promptbanken` på GitHub, egen GitHub Pages-site (samma bygg-mönster
  som `promptbanken`: `npm run build` → `actions/deploy-pages`), egen
  `CNAME` = `valvet.promptbanken.se`.
- Ingen VPS-hosting i Fas 1 — VPS:en (`mcp.promptbanken.se`) har 96% disk
  använd och 16Mi ledigt RAM; att lägga en byggprocess där avfärdades.
  MCP-servern (som redan kör där) får bara nya verktyg, ingen ny tjänst.

## Uttryckligen utanför scope (Fas 1)

Versionshistorik, semantisk sökning, delade valv, import (bara export byggs),
inbäddning av Valvet som modul i `kommun.promptbanken.se`, framtida moduler
(Skola/HR/IT/Kod), delad SSO-session mellan `kommun.` och `valvet.`.

## Öppna antaganden att verifiera under implementation

- `has_active_pro_entitlement()` (byggd för "Pro + Delad arbetsyta") antas
  återanvändbar oförändrad för Valvets Pro-gating — verifiera mot aktuell
  definition i `promptbanken`-repot innan RPC:erna skrivs.
- Exakta numeriska rate limit-värden (20/min, 5/månad, 1000 Pro-tak) är
  utgångsförslag — justerbara i migration utan schemaändring.
