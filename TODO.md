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

**Nivåstruktur (bekräftad):**

| Nivå | Typ | Målgrupp | `workspace_plan`-värde | Egna mallar (`max_prompts`) | MCP-nycklar |
|---|---|---|---|---|---|
| Free | Personlig | 1 användare | `free` | 3 | 1 |
| Pro | Personlig | 1 användare | `pro` | 100 | 5 |
| Team | Organisation | 5–10 användare, delad via en agent | `start` *(redan i enumet, oanvänt idag)* | 200 | 5 |
| Förvaltning | Organisation | En förvaltning/avdelning, delad via en agent | `plus` *(redan i enumet, oanvänt idag)* | 500 | 5 |
| Kommun | Organisation | Hela kommunen, delad via en agent | `enterprise` *(redan i enumet, oanvänt idag)* | 1000 | 5 |

**Viktigt förtydligande (ändrar tidigare antagande):** org-nivåerna handlar **inte** om flera inloggade medlemmar i admin.html — de handlar om att *workspacet* får en starkare API/MCP-nyckel som kopplas in i en delad agent (t.ex. Copilot Studio-bot eller intern chatbot) som många anställda använder utan att själva logga in i Promptbanken. Alltså: **ingen medlemsinbjudan/platsgräns-funktion behövs** — det kritiska gapet vi först flaggade (att "Medlemmar"-sektionen bara listar, aldrig bjuder in) är **inte** relevant för den här funktionen och stryks från scopet.

**Datamodell:**
- [ ] Ny tabell `pro_orders`: `id`, `workspace_id`, `user_id`, `status` (`pending`→`invoiced`→`paid`|`overdue`|`cancelled`), `requested_plan` (workspace_plan-enum), `billing_company_name`, `billing_org_number`, `billing_address`, `billing_reference`, `billing_email`, `created_at`, `due_date`, `note`. RLS: platform_owner ser allt, beställaren ser sin egen order.
- [ ] Bredda "har premiumåtkomst"-kollen i `list_pro_templates()`, `get_pro_templates_for_mcp_key()` och `enforce_mcp_key_limit()` så `start`/`plus`/`enterprise` räknas som premium, inte bara `pro` (idag hårdkodat till exakt `plan = 'pro'`).
- [ ] Nivå→gräns-mappning (`max_prompts` per plan enligt tabellen ovan) i samma triggrar som redan sätter `max_prompts` vid planbyte.

**Beställningsflöde:**
- [ ] `create_pro_order(p_workspace_id, p_requested_plan, billing-fält...)`-RPC: kollar behörighet (ägare för personligt Pro; `workspace_owner`/`workspace_admin`/`platform_owner` för org-nivåer), **skapar ett nytt organisations-workspace** om beställningen gäller Team/Förvaltning/Kommun och beställaren inte redan äger ett (namn från `billing_company_name`), sätter `plan`/`max_prompts`/`api_enabled`/`mcp_enabled` direkt, skapar `pro_orders`-raden med `status='pending'`, `plan_source='invoice'`.
- [ ] Ny sektion "Uppgradera till Pro" i `admin.html` (synlig för Free-workspaces) — formulär: företagsnamn/kommun, org.nr, fakturaadress, referens/kostnadsställe, fakturamejl, samt val av nivå (Pro/Team/Förvaltning/Kommun).
- [ ] Bekräftelsetext efter beställning: "Pro är redan aktiverat. Faktura skickas till [e-post]."

**Admin-granskningsläge (ny flik under Plattformsadmin):**
- [ ] Lista alla `pro_orders`: workspace/kommunnamn, nivå, **fakturamejl (tydligt synligt/kopierbart för påminnelser)**, status (färgkodad), förfallodatum.
- [ ] Åtgärder: "Markera fakturerad" (sätt `due_date`), "Markera betald", **"Nedgradera till Free"** (sätter `plan='free'` direkt på workspacet — samma säkra nedgraderingsbeteende som redan gäller: data ligger kvar, bara nya prompts blockeras över gränsen). Ingen automatisk cron-nedgradering — du sa uttryckligen att nedgradering vid obetald faktura ska vara ett manuellt beslut du tar, eftersom ingen automatik kan veta om en extern faktura faktiskt betalats.

**Byggordning:**
1. Migration: `pro_orders`-tabell + RLS + breddad premium-koll i befintliga funktioner + nivå→gräns-mappning
2. `create_pro_order()`-RPC (inkl. organisations-workspace-skapande för Team/Förvaltning/Kommun)
3. "Uppgradera till Pro"-formulär i admin.html/admin.js
4. Adminfaktura-granskning (lista + statusknappar + nedgradera-knapp)
