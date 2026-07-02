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
1. [ ] Dölj/filtrera synlighetsval efter behörighet — visa bara "Publik"-alternativet i formuläret för roller som faktiskt får publicera publikt (idag ser alla det men får serverfel om de väljer det utan rättighet).
2. [ ] Sök/filtrera i "Mina prompts"-tabellen — saknas helt idag, blir opraktiskt vid fler än ~5–6 rader (särskilt Pro/organisation med upp till 100 prompts).
3. [ ] Egen bekräftelsedialog vid radering istället för nativ `window.confirm()` — mjukare, stylbar UX.
4. [ ] Tydligare tom-vy/guidning för nya användare med 0 prompts (t.ex. "Skapa din första prompt nedan" istället för tom tabell).
5. [ ] Proaktiv räknare "X av 3 prompts använda" i sektionsrubriken, innan gränsen nås (inte bara felmeddelande efteråt).
6. [ ] Förhandsgranskning/expandering av prompttext direkt i tabellen, utan att behöva klicka "redigera".
7. [ ] Varna vid oavsiktlig navigering med osparade ändringar i redigeringsformuläret.

**Admin-sidan i stort**
8. [ ] Riktig sidnavigering istället för ankarlänkar på en lång sida — nav-menyns `.active`-klass är hårdkodad på första länken och uppdateras aldrig vid scroll/klick.
9. [ ] Slå ihop MCP-nyckel och API-nycklar visuellt (t.ex. under gemensam "Integrationer"-rubrik med flikar) — två nästan identiska sektioner gör sidan onödigt lång.
10. [ ] Verifiera/förbättra mobilanpassning av tabellerna (`workspace-table-wrap` ger horisontell scroll — utvärdera om kort-layout är bättre på smala skärmar).

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
- [ ] MCP-nycklar 1 → 3–5 för Pro — kräver migration: `enforce_mcp_key_limit()`-triggern har idag `existing_count >= 1` hårdkodat oavsett plan, måste bli plan-medveten.
- [ ] Premium-mallar/-arbetsflöden + MCP till premium + export av premium — **stort separat projekt.** Kräver att premiuminnehåll flyttas från statiska `prompts.json`/`prompts/*.txt`-filer (öppna för alla idag) till Supabase med en `plan_required`-kolumn, nya RLS-regler och en plan-medveten gren i MCP-RPC:erna.
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
1. [ ] Supabase Dashboard: aktivera `pg_cron`-tillägget (Database → Extensions) — manuellt engångssteg, kan inte göras via migration.
2. [ ] Migration: `workspaces.plan_source text`, `workspaces.plan_expires_at timestamptz`.
3. [ ] Migration: ny tabell `pro_invites` (token, plan, days, status, expires_at, used_at, used_by, note) + RLS som stänger ute alla utom platform_owner/service-role.
4. [ ] Migration: RPC `redeem_pro_invite(p_token text)` — SECURITY DEFINER, kollar giltighet/engångsbruk, sätter plan+expiry på anroparens personliga workspace, markerar token använd.
5. [ ] Migration: pg_cron-jobb (dagligen) som nedgraderar workspaces där `plan_expires_at < now()` tillbaka till free (samma beteende som "Nedgradering Pro → Free" ovan).
6. [x] Ny statisk sida `invite.html` + JS: läs `?token=`, kräv inloggning (skicka till login och behåll länken om ej inloggad), anropa RPC, visa resultat.
7. [x] Adminpanel istället för manuell SQL: ny sektion "Plattformsadmin" i `admin.html`/`admin.js` (synlig bara för platform_owner via befintlig `[data-platform-only]`-mekanism) med formulär för att skapa Pro-inbjudningar (genererar token, visar länk med kopiera-knapp) och en lista över skapade inbjudningar/status. Migration `20260702140000_promote_platform_owner.sql` lägger till RPC `promote_user_to_platform_owner(email)` så en admin kan göra andra användare till plattformsadmin via ett formulär i samma sektion, istället för att redigera `profiles`-tabellen manuellt.
   - [ ] **Bootstrap krävs en gång:** den allra första plattformsadmin måste sättas manuellt i SQL Editor (hönan-och-ägget: RPC:n kräver att anroparen redan är platform_owner). Logga in en gång på kontot som ska vara admin, kör sedan i SQL Editor: `update public.profiles set role = 'platform_owner' where user_id = (select id from auth.users where email = 'DIN-EPOST');`

**Separat, upptäckt under denna genomgång (inte relaterat till invite, men värt att verifiera):**
- [ ] `script.js`/`local-chat.js` räknar ut backend-adress som `window.location.origin` om inget annat satts — på `kommun.promptbanken.se` (GitHub Pages, statisk) betyder det att "Chatta lokalt" bara fungerar om `/api/*` på den domänen faktiskt routas vidare till VPS-backend (reverse proxy). Bör verifieras separat att detta är korrekt konfigurerat i produktion.
