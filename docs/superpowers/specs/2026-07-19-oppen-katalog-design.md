# Öppen katalog — avveckla Pro-gating i Promptbanken (delprojekt 6)

**Datum:** 2026-07-19
**Status:** Godkänd design
**Berörda repos:** `promptbanken` (migration + kommun-webbtexter), `valvet_promptbanken` (förenklad katalogläsning), `mcp_promptbanken` (verktygsbeskrivningar + deploy)

## Bakgrund: visionslistan (dokumenteras här permanent)

Promptbanken/Valvet-visionen består av sex delprojekt (prioritetsordning
bekräftad av Peter 2026-07-19; ursprungligen ur brainstorm 2026-07-18):

1. Plansida för Valvet (`planer.html`) — **klar**
2. Kopiera prompt → Valvet — **klar** (spec `valvet_promptbanken/docs/superpowers/specs/2026-07-18-kopiera-prompt-till-valvet-design.md`)
3. Promptpaket — aktivera/avaktivera paket av katalogprompts i valvet — ej påbörjad
4. MCP-exponering av katalogsökning/kopiering — ej påbörjad
5. Rollbaserade rekommendationer — ej påbörjad
6. Öppen katalog — avveckla Pro-gating i Promptbanken — **denna spec** (prioriterad före 3 eftersom paketlogiken annars måste ta höjd för en gating som ändå rivs)

Kärnidén: Promptbanken är den öppna, kurerade katalogen; Valvet är
användarens privata arbetsbank och enda ingången för att spara/aktivera.

## Produktbeslut

- **Pro för katalogaccess avvecklas.** Alla katalogprompts (`module='kommun'`)
  ska vara öppna och synliga för alla — besökare, Free och Pro.
- **Pro-planen behålls för Valvet** (1000 insättningar, 3 MCP-nycklar,
  obegränsade MCP-sparningar och katalogkopior; Free: 50/1/5/5). Ingen
  Valvet-gräns ändras i detta delprojekt.
- **Kommun-sidans licens-/arbetsytemekanik rörs inte** (pro_licenses, delade
  arbetsytor, create_pro_order osv. står kvar). Delprojektet gäller enbart
  katalogaccess.
- **Alias-strategi:** inget som externa klienter kan peka på tas bort —
  `published_workspace_content`-vyn och MCP-verktyget `list_pro_templates`
  behålls med oförändrade namn men returnerar nu samma mängd som den öppna
  katalogen. Fullständig utrivning är ett eventuellt senare städdelprojekt.

## Sektion 1 — DB (`promptbanken`, en ny migration)

1. **Datamigrering:**
   `update public.content_items set visibility='public' where module='kommun' and visibility='workspace';`
   Alla rader, inte bara publicerade — utkast ska bli publika när de
   publiceras; katalogen har inga privata poster.
2. **`copy_catalog_item_to_valvet`:** synlighetsvillkoret
   `visibility='public' or (visibility='workspace' and v_is_pro)` ersätts med
   `visibility in ('public','workspace')` — hängslen ifall en rad missas av
   migreringen. Kopieringskvoten (Free 5/kalendermånad via
   `app_private.valvet_catalog_copies`) **behålls oförändrad** — den är
   Valvet-sidans affärsgräns.
3. **`get_pro_templates_for_mcp_key`:** Pro-entitlement-checken tas bort —
   returnerar hela publicerade katalogen oavsett nyckelns plan. Namn och
   signatur oförändrade.
4. **Vyer:** `published_public_content` täcker efter migreringen hela
   katalogen. `published_workspace_content` behålls orörd som alias.
5. **`get_plan_usage` rörs inte** — katalogkopior-kvoten står kvar.
6. Samma härdningskonvention som övriga migrationer: `security definer`
   med `set search_path = ''` och fullt schemakvalificerade referenser
   där funktioner återskapas.

## Sektion 2 — MCP-servrar

Repo `mcp_promptbanken` (hostade servern, `mcp.promptbanken.se`):

1. **Ingen logikändring** — gaten låg i DB-RPC:n.
2. **`list_pro_templates`** beskrivs om på BÅDA definitionsställena
   (`@mcp.tool()`-docstring och `_tool_definitions()`): "Pro-mallar" →
   "hela Promptbanken-katalogen (namnet är historiskt)".
3. **DECISIONS.md:** daterat tillägg om att katalog-Pro avvecklats, med
   referens till migrationen. Historik skrivs inte om.
4. **Deploy:** `git pull` + `docker-compose up -d --build` på VPS:en
   (ContainerConfig-workaround vid behov: `stop` → `docker rm -f` → `up -d`).

Repo `promptbanken` (lokala stdio-servern i `mcp-server/`):

5. Motsvarande textjustering i den lokala serverns
   `list_pro_templates`-beskrivning.

## Sektion 3 — Webbappar

Repo `valvet_promptbanken`:

1. `loadCatalog`/`updateCatalogQuota` väljer idag vy efter plan (de
   motsatt-polariserade ternärer som slutgranskningen 2026-07-18 flaggade
   som latent risk) — förenklas till att alltid läsa
   `published_public_content`. Granskningsfyndet dör därmed.
2. Kvottexterna ("X av 5 kopior denna månad" / "Obegränsad kopiering
   (Pro)") behålls — de gäller Valvet-kvoten, inte katalogaccess.

Repo `promptbanken` (kommun-webben):

3. Alla texter som påstår att Pro ger mallaccess/premium-mallar uppdateras.
   Verifierat 2026-07-19: `script.js` (katalog-UI:t) har INGA premium-lås
   eller badges — gaten fanns enbart i DB/vyerna. Ändringen är därför ren
   text: `planer.html`-raderna "✗ Premium-mallar" / "Hela premiumbiblioteket"
   m.fl. skrivs om (tiers behåller sälj av egna mallar, arbetsytor,
   MCP-nycklar), plus motsvarande påståenden på övriga sidor om grep hittar
   fler under implementationen.
4. Inga nya sidor, ingen ny CSS.

## Felhantering

Inga nya felvägar. Kopierings-RPC:ns befintliga svenska felmeddelanden
räcker. Enda datarisken är halvmigrerade rader — täcks av
hängslen-villkoret i sektion 1 punkt 2.

## Verifiering

1. **SQL-checklista** (ny fil i `supabase/tests/`, samma konvention som
   `verify_copy_catalog_item_to_valvet.sql`):
   - Före: räkna `visibility='workspace'`-rader i katalogen. Efter
     migrering: 0.
   - Som Free-användare: kopiera en f.d. workspace-mall via
     `copy_catalog_item_to_valvet` — ska lyckas.
   - `get_pro_templates_for_mcp_key` med Free-nyckel — returnerar hela
     publicerade katalogen.
2. **MCP:** `curl` `tools/call list_pro_templates` med Free-nyckel mot
   `mcp.promptbanken.se` efter deploy — full lista.
3. **Browser:** kommun-katalogen visar inga lås/premium-badges; Valvets
   "Bläddra i Promptbanken" listar hela katalogen för ett Free-konto.

## Utanför scope

- Kommun-sidans licens-/arbetsytemekanik.
- Borttagning av alias-vyn eller verktygsnamnet (ev. senare
  städdelprojekt).
- Promptpaket (delprojekt 3) och MCP-katalogsökning (delprojekt 4).
- Stripe/köpflöde för Valvet-Pro.

## Ordningsföljd

promptbanken-migration → kommun-webbtexter → valvet-förenkling →
mcp-texter + VPS-deploy. Öppningen är bakåtkompatibel — klienter som läser
`published_public_content` ser bara fler rader, så ingen
deploy-ordningsrisk.
