# TODO

## Nu / att diskutera

- [ ] Flytta frontend till Cloudflare Workers.
  - [x] Bygg från `dist/` är konfigurerad; stora OpenAI-demo-videon exkluderas från statiska assets och har en R2-rutt med stöd för videons byte-ranges.
  - [ ] Logga in i Cloudflare, skapa R2-bucketen `promptbanken-media` och ladda upp `openaimcpssubmission.mp4` med `video/mp4` som innehållstyp.
  - [ ] Deploya Worker, koppla `app.promptbanken.se` och verifiera startsida, inloggning, OAuth-samtycke, 404-sida och demo-video live.
- [x] Bygg Supabase OAuth-samtycke på `/oauth/consent/` i en isolerad Connect-gren, inklusive säker login-retur, klient/scopes, godkänn och neka.
- [ ] Publicera samtyckessidan på `app.promptbanken.se` och verifiera den live innan Supabase OAuth Server aktiveras.
- [x] Supabase-migrationerna `20260725133000_catalog_parameter_schemas.sql` och `20260725140000_sync_parameterized_catalog_prompts.sql` finns i både lokal och remote migrationshistorik.
- [ ] Rätta tre äldre `supabase db lint`-fel: tvetydiga variabler i `promote_user_to_platform_owner`, `create_pro_order` och `admin_activate_pro_order`.
- [ ] Gå igenom Supabase säkerhetsrådgivarens befintliga varningar, främst körbara `SECURITY DEFINER`-funktioner, två muterbara `search_path` och avstängt leaked-password-skydd.
- [ ] Domänbeslut för öppen registrering: ska registrering vara helt öppen (valfri e-post) eller begränsad/flaggad för icke-kommundomäner?
- [ ] Lägg till gratis CAPTCHA i öppet registreringsflöde (Cloudflare Turnstile rekommenderas; alternativt hCaptcha).
- [ ] Kontrollera/lås Google OAuth redirect-URL:er i Supabase Dashboard och Google Cloud Console. Höj minimikrav på lösenordslängd.
- [ ] Länka användarvillkor synligt i signup-flödet.
- [ ] Lägg till varningstext i admin-UI vid delning av prompt till workspace: "Endast prompts du litar på — de körs direkt i kollegors AI-klienter".

## Öppen MCP / katalog som produkt

- [x] Connectorgränsen är införd: `/mcp` är publik read-only med exakt nio katalogverktyg och `/mcp/key` är den autentiserade kompatibilitetsytan för Free/Pro/Valvet. Långsiktigt OAuth- och Admin-MCP-upplägg återstår som separata arkitekturbeslut.

- [x] VPS SSH/deploy fungerar med nyckeln `C:\Users\petwen\.ssh\promptbanken_vps`. Deploy- och återställningsflödet finns i Codex-skillen `promptbanken-vps-deploy`.

- [x] Hostad `mcp_promptbanken`-server har autentiserade kontextverktyg på `/mcp/key`:
  - `list_my_private_prompts`
  - `list_my_shared_workspaces`
  - `list_shared_workspace_prompts`

- [ ] Målbild: dynamisk katalog/publicering för Promptbanken + öppen MCP.
  - Paket och standardprompts ska kunna skapas utan rebuild av MCP-servern.
  - Målscenario: skapa paketet **Skola** med 6 prompts + en ny standardprompt, publicera det och få det att synas direkt både på Promptbanken-sidan och via den hostade publika MCP:n.
  - MCP-koden ska vara stabil och generell; innehåll (promptar, paket, ikoner, bilder, sortering, rekommendationer) ska vara data, inte hårdkodad Python/JSON.
  - Supabase blir master för publicerat kataloginnehåll (promptar, paket, metadata, relationer).
  - "Standard skill" i detta sammanhang = vanlig katalogprompt, inte en ny MCP-tool/serverfunktion.
  - Webb och MCP ska spegla samma publicerade katalog.
  - Innehållet ska helst kunna skapas via Claude Code eller en högbehörig MCP/adminyta snarare än via manuell repo-ändring.

- [x] Separat spec för datamodell och publiceringsflöde för dynamisk katalog.
  - Kandidatmodell:
    - `catalog_prompts`
    - `catalog_packages`
    - `catalog_package_items`
  - Behöver beskriva:
    - migrationsmodell från dagens txt/sql-hybrid
    - redaktörsflöde
    - lagring av media/assets
    - review/publiceringsstatus
    - hur Valvet, Promptbanken och MCP delar samma katalogindex
  - Finns nu beskrivet i:
    - spec: `docs/superpowers/specs/2026-07-21-dynamisk-katalogplattform-design.md`
    - implementationsplan: `docs/superpowers/plans/2026-07-21-dynamisk-katalogplattform.md`

## Kontextval / profiler i Promptbanken

- [x] Planera kontextval/profiler i Promptbanken.
  - Kontext ska påverka ordval, exempel, sortering, rekommendationer och paketförslag utan att duplicera samma prompt.
  - Diskuterade huvudkontexter:
    - Generell
    - Kommun
    - Skola
    - Företag
    - Privat
  - Kontexter ska kunna kombineras i profiler, t.ex.:
    - Kommun + Skola
    - Kommun + Ledarskap
    - Företag + Kommunikation
    - Privat + Föreningsliv
  - En profil kan innehålla mer än bransch, t.ex. roll, målgrupp och ton.
  - Principer:
    - användaren kan ha flera profiler men en aktiv åt gången
    - öppna Promptbanken kan spara valet lokalt i webbläsaren
    - prioritet: explicit val → aktiv profil → arbetsytans kontext → generell fallback
  - Kräver brainstorming/spec innan implementation.

## Senare / ej blockerande nu

- [ ] Löpande månadsdebitering för Pro/arbetsytor (Stripe/prenumeration/cron) — utanför nuvarande MVP.
- [ ] Verifiera separat att `script.js` / `local-chat.js` pekar rätt mot backend i produktion för "Chatta lokalt".

## Klart

- [x] **Organisatoriska planer (2026-07-20 → 2026-07-25):** promptbanken.se renodlad till organisatoriskt (Arbetsyta/Förvaltning/Kommun) — personligt Free/Pro flyttat till Valvet. `login.html` tappade signup-flödet, `planer.html` tappade Free/Pro-korten, `admin.html`/`admin.js` visar "inte medlem"-skärm för personliga workspaces, synlighetsvalet döljs för vanliga org-medlemmar, `#uppgradera` är kontaktbaserat för alla nivåer (självköpskoden rivs inte, bara omkopplad). Se `docs/superpowers/plans/2026-07-20-organisatoriska-planer.md` (alla steg avklarade och verifierade mot grep-checkarna), 9 commits på `main` t.o.m. `e6bafb4`.
