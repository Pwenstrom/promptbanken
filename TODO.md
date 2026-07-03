# TODO

- [ ] Lägg till varningstext i admin-UI vid delning av prompt till workspace ("Endast prompts du litar på — de körs direkt i kollegors AI-klienter"). Bakgrund: workspace-delade prompts (Pro/organisation) serveras oskannat via `get_workspace_prompts_for_key` till andra medlemmars MCP-klienter och körs som instruktion — ingen sanering av adversariellt promptinnehåll finns eller går att bygga bort helt, men användaren bör varnas.

## Inför öppen registrering (fritt med e-post/Google)

1. [ ] Domänbeslut: bestäm om registrering ska vara helt öppen (valfri e-post) eller begränsad/flaggad för icke-kommundomäner. Påverkar prioriteringen av allt nedan.
2. [ ] Lägg till gratis CAPTCHA (Cloudflare Turnstile rekommenderas — gratis, osynlig UX, inbyggt stöd i Supabase Auth under Bot and Abuse Protection). Alternativ: hCaptcha (också inbyggt stöd). Kräver: site key/secret + Turnstile-widget i `login.html` + token skickas med i `signUp()`-anropet i `src/login.js`.
3. [x] Self-service kontoradering (GDPR, rätten att bli glömd) + export av egna prompts. Byggt: "Exportera mina prompts" (JSON-nedladdning) i admin.html/admin.js, samt "Radera mitt konto"-knapp som anropar en ny Supabase Edge Function (`supabase/functions/delete-account`) som raderar ägda workspaces (blockerar om organisation har andra medlemmar) och sedan auth-kontot. **Kräver deploy:** `supabase functions deploy delete-account` innan den fungerar i produktion.
4. [ ] Kontrollera/lås Google OAuth redirect-URL:er i Supabase Dashboard och Google Cloud Console (skydd mot open-redirect-missbruk). Höj minimikrav på lösenordslängd (standard är 6 tecken, höj till minst 8–10).
5. [ ] Länka användarvillkor synligt i signup-flödet (finns idag bara separat GDPR-policy/privacy.html, ingen länk/kryssruta vid "Skapa free-konto").

## UX-förbättringar: admin-sidan och "Mina prompts"

**Mina prompts**
1. [x] Dölj/filtrera synlighetsval efter behörighet — var redan löst (stale TODO-rad): `renderPromptFormRules()` bygger redan synlighetsalternativen dynamiskt från `allowedVisibilityOptions()`, som redan filtrerar bort "Publik" för alla utom `platform_owner`.
2. [x] Sök/filtrera i "Mina prompts"-tabellen — nytt sökfält (`data-my-prompts-search`) filtrerar client-side på titel/kategori, egen tom-vy-text när inget matchar.
3. [x] Egen bekräftelsedialog vid radering — tvåstegsknapp ("Ta bort" → "Bekräfta radering?" inom 4 sekunder) istället för `window.confirm()`, i både "Mina prompts" och biblioteks-tabellen.
4. [x] Tydligare tom-vy/guidning för nya användare — "Du har inga prompts än. Fyll i formuläret ovan för att skapa din första!" istället för generisk text.
5. [x] Proaktiv räknare "X av N prompts använda" — ny `renderPromptCounter()`, visas i sektionsrubriken, blir röd vid gränsen.
6. [x] Förhandsgranskning/expandering av prompttext i tabellen — "Visa"-knapp per rad expanderar en extra tabellrad med full prompttext, utan att gå in i redigeringsläge.
7. [x] Varna vid oavsiktlig navigering med osparade ändringar — dirty-flag på `input`-event i formuläret + `beforeunload`-varning.

**Admin-sidan i stort**
8. [x] Riktig sidnavigering — `IntersectionObserver`-baserad scroll-spy (`initNavScrollSpy()`) uppdaterar `.active`-klass på rätt nav-länk vid scroll.
9. [x] Slå ihop MCP-nyckel och API-nycklar visuellt — ny gemensam sektion "Integrationer" (`#integrationer`) med flikar (`.integration-tab`/`.integration-panel`); nav-länken pekar dit och klick på flikarna växlar panel utan sidladdning.
10. [x] Mobilanpassning av tabellerna — ny media query (`max-width: 640px`) minskar padding/font-storlek, gör knappar i tabellceller fullbredd/staplade, och tar bort sökfältets maxbredd på smala skärmar.

## Pro-läget: vad som ska ingå

Föreslagen funktionsmatris (Free vs Pro):

| Funktion                    |                Free |     Pro |
| --------------------------- | ------------------: | ------: |
| Standardmallar               |                  Ja |      Ja |
| Kopiera/anpassa prompt        |                  Ja |      Ja |
| Risk- och anonymiseringsråd  |                  Ja |      Ja |
| Egna sparade prompts          |               Max 3 | Max 100 |
| Premium-mallar                |                 Nej |      Ja |
| Premium-arbetsflöden          |                 Nej |      Ja |
| MCP-nycklar                   |                   1 |     3–5 |
| MCP till standardmallar       |                  Ja |      Ja |
| MCP till egna prompts         |    Kanske begränsat |      Ja |
| MCP till premium              |                 Nej |      Ja |
| API-nyckel                    | Nej eller begränsad |      Ja |
| Export av egna prompts        |                  Ja |      Ja |
| Export av premium/mallpaket   |                 Nej |      Ja |
| Radera egna prompts           |                  Ja |      Ja |
| Radera konto/data              |                  Ja |      Ja |
| Taggar/kategorier              | Fast: "Mina prompts" | Egen fritextkategori |
| Teamdelning                    |                 Nej |     Nej |
| Kommunadmin                    |                 Nej |     Nej |

Status per rad (från genomgång mot koden):
- [x] Egna sparade prompts (3/100), API-nyckel, export av egna prompts, radera egna prompts/konto — redan byggt, ingen ändring behövs.
- [x] MCP till standardmallar / MCP till egna prompts (Free naturligt begränsat av 3-prompt-taket) — inget extra bygge behövs.
- [x] MCP-nycklar 1 → 5 för Pro — klart: migration `20260702150000_pro_mcp_key_limit.sql` körd mot Supabase, `admin.js`/`admin.html` uppdaterade (dynamisk gräns-text + felmeddelande).
- [~] Premium-mallar/-arbetsflöden + MCP till premium + export av premium — **innehåll klart, UI/MCP kvar.**
  - [x] **Fas 1a (innehåll + spärr):** migration `20260702160000_pro_prompt_templates.sql` med tabellen `pro_prompt_templates`, alla 42 premium-prompts i 7 områden (kommunikation, förändringsledning, processer, beslutsberedning, visuellt, ledarskap, arbetsbank), och `list_pro_templates()` (SECURITY DEFINER, teaser-läge: Free/ej inloggad får titel+syfte+outputformat men `prompt_text = null`; Pro inkl. aktiv invite-trial får allt). Målgrupp: medarbetare, tjänstemän, samordnare, chefer, kansli i svensk kommun/offentlig sektor. Varje mall har `security_examples` (anonymiseringsråd) och `[klistra in här]`-markör för snabbinmatning.
  - [x] **Fas 1b (UI):** ny egen sida `pro.html` + `src/pro.js` (ES-modul, samma mönster som `admin.js`/`invite.js` — rör inte `script.js`, som inte får ha imports). Anropar `list_pro_templates()`, grupperar de 7 områdena, teaser-lås (hänglås + "Uppgradera till Pro"-länk till `admin.html`) på låsta kort, kopiera/visa-prompt-modal för upplåsta Pro-kort. Nav-länkar tillagda i `promptbanken.html` och `index.html`. Registrerad i `vite.config.js`.
  - [x] **Fas 2 (MCP, lokal server):** klart och migration körd mot Supabase. `get_pro_templates_for_mcp_key(p_key_hash)` (samma teaser/unlocked-logik som `list_pro_templates()`, men nyckel-hash-baserad istället för `auth.uid()`, eftersom lokala stdio-MCP-servern inte har någon Supabase-inloggning). Ny `mcp-server/server/pro_templates.py` (stdlib `urllib`, ingen ny dependency) anropar RPC:n via PostgREST med `SUPABASE_URL`/`SUPABASE_ANON_KEY`/`PROMPTBANKEN_MCP_KEY` som miljövariabler. Nytt MCP-verktyg `list_pro_templates` registrerat i `mcp_server.py`. `mcp.html` uppdaterad med rätt `env`-block i Claude-konfigurationsexemplet.
  - [x] **Kolla: kommer Pro-mallarna ut i den hostade `mcp_promptbanken`-servern?** Löst 2026-07-03: nytt verktyg `list_pro_templates` + REST `GET /api/v1/pro-templates` i `mcp_promptbanken/mcp-server/server/pro_templates.py` (separat repo), anropar samma RPC med `X-MCP-Key`/`Authorization`-headern per request istället för en env-variabel (hosted-servern har flera samtidiga workspaces, inte en enda lokal användare). Tillagd i `_tool_definitions()`, JSON-RPC-dispatchen och hosted metadata-guardens allowlist. Deployat på VPS:en.
  - [x] **Fas 3:** klart. "Spara till Mina prompts"-knapp på alla upplåsta Pro-mallar (inte bara #37–42, men löser samma behov mer generellt) i `pro.html`/`pro.js` — inserterar en egen, redigerbar kopia i användarens `content_items` (privat, utkast, kategori satt till områdesnamnet) via `getPersonalWorkspaceId()` + insert. Dyker upp under "Mina prompts" i `admin.html`. Hanterar dubbelsparning (unique constraint) med tydligt felmeddelande.
- [ ] Taggar/kategorier — **beslutat, ersätter tidigare "Begränsat"-rad:** Free får en fast, låst standardkategori ("Mina prompts") på alla egna prompts. Pro kan sätta egen fritextkategori. Konkret och begripligt värde istället för en vag broms. Bygge: kategori-fältet i `admin.html`-formuläret ska vara låst/förifyllt med "Mina prompts" och inaktiverat för Free-workspaces (samma mönster som synlighetsväljaren döljs efter behörighet, se UX-punkt 1 ovan). Bör även spärras server-side i `enforce_content_access_model()` (tvinga `category = 'Mina prompts'` vid INSERT/UPDATE om `workspace.plan = 'free'`) så det inte går att kringgå klientsidan.
- [x] Teamdelning: Nej/Nej, Kommunadmin: Nej/Nej — bekräftat beslut, betyder att inget organisations-/delningsflöde behöver byggas för Pro i den här fasen.

**Nedgradering Pro → Free (bekräftat beteende):**
- [ ] Bygg nedgraderingslogik: när en Pro-användare går tillbaka till Free (uppsägning/utebliven betalning) sätts `max_prompts` tillbaka till 3, men **ingen data raderas automatiskt**. Användaren kan ha fler än 3 aktiva prompts kvar liggande (över gränsen) — de ska förbli synliga/exporterbara, men användaren ska **inte kunna skapa nya** prompts förrän de är under gränsen igen (radera manuellt) eller köper Pro på nytt. Nuvarande gräns-koll (`enforce_content_access_model()`, `prompt_count >= workspace_record.max_prompts`) tillåter redan detta naturligt vid INSERT — måste verifieras att UPDATE av befintliga prompts över gränsen inte blockeras felaktigt av samma trigger.

## Pro-test via invite-länk (MVP innan Stripe)

Idé: ge ut 30 dagars Pro-test via en unik, engångs-länk istället för att bygga betalning direkt. Bedömning: fullt möjligt, återanvänder nästan all befintlig plan-logik (`workspace.plan`/`max_prompts`/`api_enabled` styr redan alla spärrar).

**Justeringar mot ursprunglig skiss:**
- [ ] Plan/utgång ska lagras på `workspaces` (inte `profiles` — `profiles` har ingen plan-kolumn idag; `workspaces` har redan `plan`/`max_prompts`/`api_enabled`/`mcp_enabled`).
- [ ] Automatisk nedgradering vid utgång saknades i ursprungsidén — **måste** finnas, annars förblir Pro aktivt för evigt. Löses med pg_cron-jobb (se nedan), inte lat koll vid varje sidladdning (sprider ut expiry-logik på för många ställen).
- [ ] URL-form: använd `invite.html?token=xxx` (query-sträng), inte `/invite/pro/[token]` som path — sajten hostas statiskt på GitHub Pages (`kommun.promptbanken.se`, se `CNAME`), ingen server-side rewrite tillgänglig där.

**Bygglista:**
1. [x] Supabase Dashboard: aktivera `pg_cron`-tillägget — klart, migration körd (bekräftat: `cron.schedule` returnerade job-id 1).
2. [x] Migration: `workspaces.plan_source text`, `workspaces.plan_expires_at timestamptz` — klart i `20260702130000_pro_invites.sql`.
3. [x] Migration: ny tabell `pro_invites` (token, plan, days, status, expires_at, used_at, used_by, note) + RLS som stänger ute alla utom platform_owner/service-role — klart.
4. [x] Migration: RPC `redeem_pro_invite(p_token text)` — klart.
5. [x] Migration: pg_cron-jobb (dagligen 03:00) som nedgraderar workspaces där `plan_expires_at < now()` tillbaka till free — klart.
6. [x] Ny statisk sida `invite.html` + JS: läs `?token=`, kräv inloggning (skicka till login och behåll länken om ej inloggad), anropa RPC, visa resultat.
7. [x] Adminpanel istället för manuell SQL: ny sektion "Plattformsadmin" i `admin.html`/`admin.js` (synlig bara för platform_owner via befintlig `[data-platform-only]`-mekanism) med formulär för att skapa Pro-inbjudningar (genererar token, visar länk med kopiera-knapp) och en lista över skapade inbjudningar/status. Migration `20260702140000_promote_platform_owner.sql` lägger till RPC `promote_user_to_platform_owner(email)` så en admin kan göra andra användare till plattformsadmin via ett formulär i samma sektion, istället för att redigera `profiles`-tabellen manuellt.
   - [ ] **Bootstrap krävs en gång:** den allra första plattformsadmin måste sättas manuellt i SQL Editor (hönan-och-ägget: RPC:n kräver att anroparen redan är platform_owner). Logga in en gång på kontot som ska vara admin, kör sedan i SQL Editor: `update public.profiles set role = 'platform_owner' where user_id = (select id from auth.users where email = 'DIN-EPOST');`

**Separat, upptäckt under denna genomgång (inte relaterat till invite, men värt att verifiera):**
- [ ] `script.js`/`local-chat.js` räknar ut backend-adress som `window.location.origin` om inget annat satts — på `kommun.promptbanken.se` (GitHub Pages, statisk) betyder det att "Chatta lokalt" bara fungerar om `/api/*` på den domänen faktiskt routas vidare till VPS-backend (reverse proxy). Bör verifieras separat att detta är korrekt konfigurerat i produktion.

## Pro-köp via faktura + org-nivåer (Team/Förvaltning/Kommun)

**Modell:** fakturaköp, inte kortbetalning. Beställning samlar in fakturauppgifter → **Pro/org-nivå aktiveras direkt** vid beställning (inte vid betalning) → fakturan skickas/hanteras utanför systemet (t.ex. i bokföringsverktyg) → admin bevakar betalstatus manuellt och kan nedgradera om obetald i tid.

**Nivåstruktur (senaste versionen — Förvaltning/Kommun kan nu ha FLERA arbetsytor, inte bara en):**

| Plan | Typ | Svenskt namn | Arbetsytor | Medlemmar | Mallar | Nycklar | Huvudidé |
|---|---|---|---:|---:|---:|---:|---|
| Free | Personlig | Min arbetsyta | 1 personlig | 1 | 3 egna + öppna | 1 personlig MCP | Testa Promptbanken |
| Pro | Personlig | Min AI-arbetsbank | 1 personlig | 1 | 100 egna + Pro-tools | 5 personliga MCP | Bygga egen AI-arbetsbank |
| Team | Grupp | Teamets arbetsyta | 1 teamyta | 5–10 | ca 200 delade | 1–2 agentnycklar | Dela mallar i liten grupp |
| Förvaltning | Organisation | Förvaltningens mallbank | flera, t.ex. 3–5 | upp till ca 50 totalt | ca 500 totalt | 3–5 agentnycklar | Flera verksamheter inom samma förvaltning |
| Kommun | Organisation | Kommunens mallbank | flera, enligt avtal | 250+ / offert | 1000+ / offert | 5–10+ enligt avtal | Flera förvaltningar + kommunövergripande styrning |

`workspace_plan`-värdena `start`/`plus`/`enterprise` (redan i enumet, oanvända idag) mappar mot Team/Förvaltning/Kommun.

**Exempel på arbetsytor per nivå** (visar varför flera arbetsytor behövs för Förvaltning/Kommun):
- Team: "Kommunikationsgruppen", "IT-teamet", "HR-teamet" (en yta per köpt team-licens)
- Förvaltning: en förvaltning (t.ex. Barn- och utbildningsförvaltningen) delar upp sig internt i egna ytor: "BU Ledning", "Förskola", "Grundskola", "Elevhälsa", "Administration"
- Kommun: hela kommunen, en yta per förvaltning: "Kommunledning", "BU", "Socialförvaltning", "Tekniska", "HR", "Kommunikation", "IT"

**Grundprincip:**
> Arbetsytor är där mallarna bor. Medlemmar är personer som skapar och förvaltar mallar. Nycklar är tekniska ingångar för agenter, botar och integrationer.

**🔴 Arkitekturkonsekvens — nytt lager mellan beställning och workspace:**

Detta ändrar tidigare antagande (att Förvaltning/Kommun = ett enda organisations-workspace med hög gräns). Nu behövs en **licens** som äger flera workspaces, och gränserna (medlemmar/mallar/nycklar) gäller **summerat över alla arbetsytor under samma licens**, inte per enskild arbetsyta.

- [ ] **Ny tabell `pro_licenses`:** `id`, `plan` (workspace_plan-enum), `owner_user_id`, `max_workspaces`, `max_members_total`, `max_prompts_total`, `max_mcp_keys_total`, `plan_source`, `plan_expires_at`, `status`. En rad per köpt Team/Förvaltning/Kommun-licens.
- [ ] `workspaces` får en ny nullable kolumn `license_id` (FK till `pro_licenses`). Free/Pro-workspaces har `license_id = null` som idag (opåverkade). Team har en licens med `max_workspaces = 1` (samma beteende som innan). Förvaltning/Kommun kan ha flera rader i `workspaces` som pekar på samma `license_id`.
- [ ] **Ny självbetjäningsfunktion:** "Skapa ny arbetsyta" inom en befintlig Förvaltning/Kommun-licens — en `workspace_owner`/`workspace_admin` kan skapa fler arbetsytor (t.ex. lägga till "Grundskola" efter att "Förskola" redan finns) upp till `max_workspaces`. Ny RPC `create_workspace_under_license(p_license_id, p_name)`.
- [ ] **Gränser måste räknas ihop över syskon-workspaces:** `enforce_content_access_model()` (mallar) och den nya medlemsgräns-triggern måste, för workspaces med `license_id is not null`, summera över **alla** workspaces med samma `license_id` — inte bara det egna workspacet, som idag. Detta är den mest komplexa kodändringen i hela Pro-projektet hittills.
- [ ] **Ny UI-fråga:** en person kan nu tillhöra flera arbetsytor under samma licens (t.ex. jobba i både "Förskola" och "BU Ledning"). `admin.html` behöver en **arbetsyteväxlare** (workspace switcher) i sidomenyn/headern, liknande hur de flesta multi-workspace-SaaS-appar fungerar — idag visar admin.html bara ett workspace per session.

**Viktig nyansering av MCP-nycklar — två olika typer, inte en gemensam räknare:**
- **Personliga nycklar** (Free/Pro): kopplade till en enskild persons eget workspace, som idag (`enforce_mcp_key_limit()`).
- **Workspace-nycklar** (Team/Förvaltning/Kommun): delade nycklar på organisationsnivå, avsedda för integrationer/agenter (Copilot Studio-bot, intern agent, testmiljö, produktion) — inte en nyckel per person. En medlem i ett Team kan **även** ha sin egen personliga nyckel via sitt eget separata personliga workspace parallellt, om de vill — det är inte antingen-eller.
- [ ] **Kräver kodändring:** `enforce_mcp_key_limit()` kollar idag bara gräns för `type = 'personal'` — organisationsworkspaces har **ingen gräns alls** just nu (hål i nuvarande kod, oavsiktligt). Måste utökas med en nivå→gräns-mappning som täcker `start`/`plus`/`enterprise` också.

**Viktigt förtydligande:** org-nivåerna handlar om att *workspacet* får starkare API/MCP-nycklar som kan kopplas in i delade agenter/integrationer — **men** ett Team ska även kunna dela prompts mellan sina egna, riktigt inloggade medlemmar (upp till 10), inte bara agera nyckel-till-en-bot. Det innebär att medlemsinbjudan **återinförs i scopet** (jag strök det för snabbt tidigare) — åtminstone för Team, sannolikt även Förvaltning/Kommun.

- **Delning i sig fungerar redan tekniskt:** `content_items.visibility = 'workspace'` finns redan, och "Promptbibliotek"-listan i `admin.html` visar redan sådana prompts för alla i samma organisation (`enforce_content_access_model()` kräver redan `visibility='workspace'` för organisationsprompts). Inget nytt behövs där.
- **Det som faktiskt saknas:** ett sätt att **bjuda in en kollega** till workspacet. Idag skapas `profiles`-rader bara automatiskt för personliga workspaces (`ensure_personal_workspace()`) — det finns ingen "bjud in via e-post"-funktion för organisationer alls.
**Två parallella sätt att få in medlemmar i ett organisations-workspace (bekräftat: bygg båda):**

**A. Direktinbjudan via e-post** (för ägare som redan vet exakt vilka kollegor som ska in)
- [ ] `invite_org_member(p_workspace_id, p_email, p_role)`-RPC (SECURITY DEFINER, kollar att anroparen är `workspace_owner`/`workspace_admin`/`platform_owner` i det workspacet) som hittar mottagarens `user_id` via e-post (de måste redan ha ett Promptbanken-konto — enklast för v1, ingen e-postutskicksfunktion behövs då) och skapar en `profiles`-rad åt dem i organisationens workspace.
- [ ] UI: formulär i "Medlemmar"-sektionen i `admin.html` (som idag bara listar, aldrig bjuder in).

**B. Delad join-länk/kod** (samma mönster som `pro_invites`/`invite.html`, enklare onboarding för en hel grupp på en gång)
- [ ] Ny tabell `org_join_codes` (eller utöka `pro_invites` med `workspace_id`/`kind='org_join'`): token, `workspace_id`, `role` (vilken roll den som joinar får, t.ex. `editor`), `status` (unused/revoked — **ej engångs**, kan användas av flera personer upp till platsgränsen), `expires_at`.
- [ ] `redeem_org_join_code(p_token)`-RPC: verifierar koden, kollar platsgräns, skapar `profiles`-rad åt anroparen i workspacet.
- [ ] Återanvänd `invite.html`-mönstret: `?team_token=xxx` (eller egen sida `team-invite.html`) — logga in/skapa konto, joina automatiskt.
- [ ] UI för att generera/visa join-koden: i "Medlemmar"-sektionen, bredvid direktinbjudan — "Generera join-länk" + kopiera-knapp, samma UX som Pro-inbjudningarna i Plattformsadmin.

**Gemensamt för A och B:**
- [ ] Platsgräns per nivå (Team: 10, Förvaltning: 50, Kommun: 250 eller obegränsat/offert) — enkel räkne-trigger på `profiles`-insert, samma mönster som `enforce_mcp_key_limit()`, gäller oavsett om medlemmen kom in via A eller B.
- [ ] Redan bekräftat: en person kan redan ha flera workspace-medlemskap samtidigt (`profiles` har `unique(user_id, workspace_id)`, inget hindrar att någon har både sitt egna personliga Pro-workspace *och* är medlem i ett Team-workspace) — ingen schemaändring behövs för det.

**Datamodell:**
- [ ] Ny tabell `pro_orders`: `id`, `license_id` (för Team/Förvaltning/Kommun) eller `workspace_id` (för personligt Pro), `user_id`, `status` (`pending`→`invoiced`→`paid`|`overdue`|`cancelled`), `requested_plan` (workspace_plan-enum), `requested_workspaces` (hur många arbetsytor kunden vill ha, för Förvaltning/Kommun), `billing_company_name`, `billing_org_number`, `billing_address`, `billing_reference`, `billing_email`, `created_at`, `due_date`, `note`. RLS: platform_owner ser allt, beställaren ser sin egen order.
- [ ] Ny tabell `pro_licenses` (se arkitektur-avsnittet ovan) — krävs innan `pro_orders` kan peka på den för org-nivåer.
- [ ] Bredda "har premiumåtkomst"-kollen i `list_pro_templates()`, `get_pro_templates_for_mcp_key()` och `enforce_mcp_key_limit()` så `start`/`plus`/`enterprise` räknas som premium, inte bara `pro` (idag hårdkodat till exakt `plan = 'pro'`).
- [ ] Nivå→gräns-mappning (`max_prompts_total`/`max_members_total`/`max_mcp_keys_total`/`max_workspaces` per plan enligt tabellen ovan), lagrad på `pro_licenses`-raden vid köp.

**Beställningsflöde:**
- [ ] `create_pro_order(p_requested_plan, p_requested_workspaces, billing-fält...)`-RPC: för personligt Pro — aktiverar direkt på beställarens egna workspace, som innan. För Team/Förvaltning/Kommun — **skapar en `pro_licenses`-rad** + en första arbetsyta under licensen (namn från `billing_company_name`), sätter gränserna enligt tabellen, skapar `pro_orders`-raden med `status='pending'`, `plan_source='invoice'`.
- [ ] `create_workspace_under_license(p_license_id, p_name)`-RPC: självbetjäning för att lägga till fler arbetsytor under en redan köpt Förvaltning/Kommun-licens, upp till `max_workspaces`.
- [ ] Ny sektion "Uppgradera till Pro" i `admin.html` (synlig för Free-workspaces) — formulär: företagsnamn/kommun, org.nr, fakturaadress, referens/kostnadsställe, fakturamejl, val av nivå (Pro/Team/Förvaltning/Kommun), och för Förvaltning/Kommun: önskat antal arbetsytor att börja med.
- [ ] Bekräftelsetext efter beställning: "Pro är redan aktiverat. Faktura skickas till [e-post]."
- [ ] Arbetsyteväxlare i `admin.html` för konton som tillhör flera arbetsytor under samma licens.

**Admin-granskningsläge (ny flik under Plattformsadmin):**
- [ ] Lista alla `pro_orders`: licens/kommunnamn, nivå, antal arbetsytor, **fakturamejl (tydligt synligt/kopierbart för påminnelser)**, status (färgkodad), förfallodatum.
- [ ] Åtgärder: "Markera fakturerad" (sätt `due_date`), "Markera betald", **"Nedgradera till Free"** (sätter `plan='free'` på licensen — nedgraderar samtliga arbetsytor under licensen samtidigt; samma säkra beteende som redan gäller: data ligger kvar, bara nya prompts blockeras över gränsen). Ingen automatisk cron-nedgradering — du sa uttryckligen att nedgradering vid obetald faktura ska vara ett manuellt beslut du tar, eftersom ingen automatik kan veta om en extern faktura faktiskt betalats.

**Kort säljtext per nivå (för prissida/marknadsföring):**

| Plan | Text |
|---|---|
| Free | Testa öppna kommunala AI-mallar. |
| Pro | Bygg din egen AI-arbetsbank med Pro-tools och egna mallar. |
| Team | Dela prompts och arbetssätt i en mindre grupp. |
| Förvaltning | Samla flera verksamheters mallar i en gemensam förvaltningslicens. |
| Kommun | Styr och distribuera godkända AI-mallar till hela kommunen och dess agenter. |

**Byggordning (uppdaterad med licens-lagret):**
1. [x] Migration `20260703110000_pro_licenses_and_orders.sql` — körd mot Supabase.
2. [x] Migration `20260703120000_create_pro_order.sql` — körd mot Supabase.
3. ✅ Ingår redan i steg 1 (mall- och medlemsgränserna summeras över licensen direkt i samma migration, byggdes inte som separat steg).
4. [x] Migration `20260703130000_org_member_invites.sql`: `invite_org_member(p_workspace_id, p_email, p_role)` (A — hittar mottagaren via e-post, kräver befintligt konto, blockerar `workspace_owner`/`platform_owner`-roller via inbjudan), `org_join_codes`-tabell + RLS (bara workspace-ägare/admin/platform_owner) + `redeem_org_join_code(p_token)` (B — återanvändbar tills återkallad/utgången, hanterar redan-medlem snyggt). Platsgränsen från steg 1 (`enforce_org_member_limit`) gäller automatiskt för båda vägarna. **Kvar: köra mot Supabase.**
5. [ ] UI: "Bjud in medlem" (e-post) + "Generera join-länk" i Medlemmar-sektionen; ny `team-invite.html`-sida (eller `?team_token=` på `invite.html`) för att lösa in join-koden; arbetsyteväxlare för konton med flera ytor
6. [ ] "Uppgradera till Pro"-formulär i admin.html/admin.js
7. [ ] Adminfaktura-granskning (lista + statusknappar + nedgradera-knapp)
