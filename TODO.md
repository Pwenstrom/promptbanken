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
