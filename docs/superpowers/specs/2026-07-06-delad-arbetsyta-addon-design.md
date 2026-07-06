# Design: Pro + Delad arbetsyta (addon-modell)

**Datum:** 2026-07-06
**Status:** Godkänd design (PM-beslut), inväntar spec-granskning före implementationsplan.

## 1. Bakgrund och mål

Planmodellen delas upp i två tydligt separerade världar:

- **Personlig värld:** Free → Pro → **Pro + Delad arbetsyta**
- **Organisationsvärld:** Förvaltning (`plus`) → Kommun (`enterprise`)

Dagens `start`-nivå (Team) är idag en *organisationslicens* via `pro_licenses`. Den
betydelsen fasas ut. `start` återanvänds som teknisk tier för en **liten delad
addon-yta** kopplad till personlig Pro — **inte** längre en org-licens.

Mål: minsta möjliga förändring som ändå håller de två världarna åtskilda i
datamodell, planlogik, MCP-scope och UI-copy.

## 2. Tvåvärldsmodell (låst)

| Modell | Teknisk markering | Licens | Publikt namn |
|---|---|---|---|
| Personlig gratis | `type='personal'`, `plan='free'` | ingen | Free |
| Personlig Pro | `type='personal'`, `plan='pro'` | ingen | Pro |
| Delad addon-yta | `type='organization'`, `plan='start'` | `license_id=null` + `shared_workspace_addons`-rad | **Delad arbetsyta** |
| Förvaltning | `type='organization'`, `plan='plus'` | `license_id` finns (`pro_licenses`) | Förvaltning |
| Kommun | `type='organization'`, `plan='enterprise'` | `license_id` finns (`pro_licenses`) | Kommun |

**Diskriminator:** en org-workspace är en *addon-yta* om `license_id IS NULL` och det
finns en `shared_workspace_addons`-rad; den är en *org-licensyta* om `license_id IS NOT NULL`.

Publikt får `start` aldrig visas som namn — heter alltid "Delad arbetsyta".

## 3. Datamodell

### 3.1 Ny tabell: `shared_workspace_addons`

Skild från `pro_licenses`. En rad per delad addon-yta.

```
shared_workspace_addons
  id                     uuid pk
  workspace_id           uuid not null references workspaces(id) on delete cascade  -- unik
  owner_user_id          uuid not null references auth.users(id)
  billing_owner_user_id  uuid not null references auth.users(id)  -- vem som betalar 199 kr
  max_members            integer not null default 4
  max_prompts            integer not null default 200
  price_per_month        integer not null default 199
  plan_source            text        -- 'invoice' i MVP
  plan_expires_at        timestamptz -- null = löpande
  status                 text not null default 'active'  -- 'active' | 'cancelled'
  created_at             timestamptz not null default now()
```

RLS: ägaren/billing-ägaren och `platform_owner` läser; skrivning via SECURITY
DEFINER-RPC:er och platform_owner.

### 3.2 `workspaces`

Ingen schemaändring. Addon-ytan är en vanlig org-workspace med `license_id=null`.
`plan='start'` är markören tillsammans med addon-raden.

### 3.3 `pro_licenses` — oförändrad

Rör **endast** Förvaltning/Kommun. En delad arbetsyta får **aldrig** skapa en
`pro_licenses`-rad.

## 4. Pro-rättighet (entitlement-abstraktion)

Kravet "medlem måste ha Pro" byggs mot en abstraktion, inte mot självbetald
prenumeration:

```
has_active_pro_entitlement(p_user_id uuid) returns boolean
```

MVP-källa: användaren äger en aktiv personlig `plan='pro'`-workspace
(`status='active'` och `plan_expires_at` null eller i framtiden).

Framtida källor (ej byggda nu, men abstraktionen ska tåla dem): ägar-tilldelad
Pro, organisations-/företagsfaktura, manuellt avtal. Endast funktionens *innehåll*
utökas senare — anropande kod ändras inte.

## 5. RPC: `create_shared_workspace(p_name text)`

Separat RPC (SECURITY DEFINER). **Återanvänder inte** `create_pro_order()`.

Steg:
1. Kräv `has_active_pro_entitlement(auth.uid())` — annars fel.
2. Skapa `workspaces`-rad: `type='organization'`, `plan='start'`, `license_id=null`,
   `owner_user_id=auth.uid()`, `mcp_enabled=true`, `api_enabled=false`, unik slug.
3. Skapa `shared_workspace_addons`-rad: `owner_user_id` och `billing_owner_user_id`
   = anroparen, `max_members=4`, `max_prompts=200`, `price_per_month=199`,
   `plan_source='invoice'`.
4. Skapa `profiles`-rad: anroparen som `workspace_owner`.
5. Skapa fakturapost på 199 kr enligt nuvarande fakturamodell (en engångsfaktura i
   MVP — löpande månadsdebitering är utanför scope).

## 6. Medlemskap och join-spärr

Återanvänd befintlig mekanik oförändrad i signatur:
`invite_org_member()`, `org_join_codes`, `redeem_org_join_code()`,
befintlig profil-/medlemslogik.

Ny/ändrad **join-trigger** på `profiles` (before insert) skiljer på yttyp:

- **Addon-yta** (`type='organization'` och `license_id IS NULL` och addon-rad finns):
  1. Hård spärr: `has_active_pro_entitlement(new.user_id)` måste vara sant.
  2. Medlemsgräns: antal profiler på ytan `< shared_workspace_addons.max_members` (4, inkl. ägare).
- **Org-licensyta** (`license_id IS NOT NULL`): befintlig `enforce_org_member_limit`
  (summerat över licensens syskonytor) — **oförändrad**.
- **Personlig yta:** ingen medlemsspärr (som idag).

Den gamla `pro_licenses`-baserade medlemsgränsen gäller alltså **bara** ytor med
`license_id`. Addon-ytor styrs av `shared_workspace_addons.max_members`.

## 7. MCP-scope (låst säkerhetsmodell)

**Behörighet skiljs från hämtning.** En personlig Pro-nyckel är *behörig* till:
- användarens privata Pro-yta,
- delade addon-ytor (`plan='start'`, `license_id IS NULL`) där nyckelns ägare är
  aktiv medlem.

Men nyckeln blandar **aldrig** ihop kontexter automatiskt. Hämtning är **kontextstyrd**
via parametrar på `get_workspace_prompts_for_key(p_key_hash, p_scope, p_workspace_id)`:

- **`scope='private'`** (eller inga parametrar = default): returnera bara användarens
  privata Pro-mallar (privata + egna i den personliga Pro-ytan). Aldrig delade ytor.
- **`workspace_id=<id>`**: returnera bara delade mallar (`visibility='workspace'`,
  `status='published'`) från den angivna addon-ytan, **efter medlemskapskontroll**
  (nyckelägaren måste vara aktiv medlem, och ytan måste vara en addon-yta:
  `plan='start'`, `license_id IS NULL`). Aldrig privata mallar, aldrig andra ytor.
- **Default (varken scope eller workspace_id)**: returnera privat kontext (som
  `scope='private'`). Returnera **aldrig** privat + alla delade ytor i samma svar.

Får **aldrig** returnera, oavsett parametrar:
- Andra medlemmars privata personliga mallar.
- Mallar från Förvaltning/Kommun-ytor (`plan IN ('plus','enterprise')` eller
  `license_id IS NOT NULL`). **Hård gräns.**

**Discovery:** separat funktion `list_shared_workspaces_for_key(p_key_hash)` returnerar
vilka delade addon-ytor nyckelägaren är medlem i (id + namn — metadata, inte
mallinnehåll), så klienten kan välja `workspace_id`. Hämtning av mallar sker sedan
kontextstyrt enligt ovan.

**Säkerhetsmotivering:** default-anropet blandar aldrig ytor. Det minskar risken att
en agent råkar använda mallar från fel arbetsyta och gör beteendet förutsägbart när
en power user är medlem i flera delade ytor. Nyckeln är personlig; kontexten avgör
vad den hämtar.

**Organisationsnycklar** (nycklar på `plus`/`enterprise`-ytor) — oförändrad logik,
gäller bara sin egen org-yta. Personliga och organisationsnycklar blandas aldrig.

**MCP-server:** de lokala/hostade MCP-verktygen exponerar val av kontext (privat vs
en vald delad yta) plus ett discovery-verktyg som listar valbara delade ytor.

Att flytta en kommun-/förvaltningsmall in i en personlig Pro-yta kräver aktiv
kopiering/export/import (befintlig "spara till Mina prompts"-funktion), aldrig
direkt MCP-scope.

## 8. Gränser och enforcement

Delad arbetsyta:

| Gräns | Värde | Var enforcas |
|---|---|---|
| Medlemmar | 4 (inkl. ägare) | join-trigger, läser `shared_workspace_addons.max_members` |
| Delade mallar (`visibility='workspace'`) | 200 | `enforce_content_access_model`, ny gren för `license_id IS NULL`-org-ytor, läser `shared_workspace_addons.max_prompts` |
| Egna MCP-nycklar på ytan | 0 | `enforce_mcp_key_limit`: org-yta med `license_id IS NULL` → blockera nyckelskapande |
| Egna privata mallar på ytan | 0 | org-ytor tvingas redan till `visibility='workspace'` (befintligt) |
| API | Nej (MVP) | `api_enabled=false` sätts vid skapande |

`enforce_content_access_model` behöver en ny gren: org-workspace med
`license_id IS NULL` läser mallgränsen från `shared_workspace_addons` istället för
`pro_licenses`.

`enforce_mcp_key_limit` behöver en ny regel: org-workspace med `license_id IS NULL`
(addon) får **inte** skapa egna mcp-scopade nycklar alls.

## 9. Ändringar i `create_pro_order()`

- **Ta bort den aktiva `start`-grenen** som skapade `pro_licenses` + org-workspace.
- `create_pro_order()` hanterar hädanefter bara: `pro` (personlig, direkt),
  `plus`/`enterprise` (väntande förfrågan → `admin_activate_pro_order`).
- Om `p_requested_plan='start'` skickas in: avvisa med fel som pekar mot
  `create_shared_workspace()`.

## 10. UI och copy

- Publikt namn: **Delad arbetsyta** överallt (aldrig "start"/"Team").
- `planer.html`: Delad arbetsyta som Pro-tillägg (Pro + 199 kr/mån), max 4
  Pro-användare, 200 delade mallar, "inga egna nycklar — nås via medlemmarnas
  personliga Pro-nycklar". Pro: MCP-tak 3 (ej 5), API borttaget (MVP).
- `admin.html`/`admin.js`: uppgraderingsflödet pekar delad-yta-valet mot
  `create_shared_workspace`; ta bort `start` ur `create_pro_order`-nivåväljaren.
- Label-mappar (`planNameLabels`, `planPricing`): `start` → "Delad arbetsyta".

## 11. Migrering och seed (pre-launch)

Inga skarpa kunder finns → ingen produktionsdatamigrering krävs. **Men verifiera
före patch** (säker förkontroll, ska ingå i planen som ett tidigt steg):

- Sök efter `pro_licenses` med `plan='start'`.
- Sök efter `workspaces` med `plan='start'` och `license_id IS NOT NULL`.
- Om sådana rader finns: **stoppa och rapportera** innan någon ändring görs — då
  finns oväntad `start`-org-licensdata som måste hanteras medvetet först.

Antag alltså ingen skarp migrering, men bekräfta antagandet mot databasen innan
migrationen körs. För MVP räcker det annars att hantera: seed-data, demo-/testdata,
eventuell intern testlicens, och UI-copy där `start` tidigare betydde Team/Arbetsyta
som org-licens.

- Befintliga test-/seed-`start`-ytor med `license_id` är enbart testdata.
  `scripts/seed-test-users.mjs` uppdateras så delade ytor skapas via den nya
  modellen (addon-rad, ingen licens), eller så tas `start`-testytorna bort.
- Migrationen skapar `shared_workspace_addons`, uppdaterar de tre triggerfunktionerna
  (`enforce_content_access_model`, `enforce_mcp_key_limit`, join-trigger),
  `get_workspace_prompts_for_key`, `has_active_pro_entitlement`,
  `create_shared_workspace`, och neutraliserar `start`-grenen i `create_pro_order`.

## 12. Verifieringspunkter (måste kontrolleras vid implementation)

1. Inga gamla `start`-flöden skapar org-licens (`pro_licenses`).
2. UI säljer inte längre `start` som org-plan; publikt namn = "Delad arbetsyta".
3. `create_pro_order()` har ingen aktiv `start`-gren för org-licens.
4. `create_shared_workspace()` är enda vägen till ny delad yta.
5. `license_id=null` bryter inte befintliga RLS/policies på org-workspaces.
6. Join-triggern skiljer korrekt mellan addon-yta (`license_id null` + addon-rad)
   och org-licensyta (`license_id` finns).
7. MCP-scope följer låst modell:
   - personlig Pro-nyckel *får* nå delad addon-yta där användaren är medlem —
     men bara kontextstyrt (`workspace_id`), aldrig i default-svaret,
   - default-anrop (utan scope/workspace_id) returnerar bara privat yta, aldrig
     privat + delade blandat,
   - personlig Pro-nyckel *får inte* nå `plus`/`enterprise`-ytor oavsett parametrar,
   - organisationsnycklar gäller bara `plus`/`enterprise`.
8. `list_shared_workspaces_for_key` returnerar bara metadata (id + namn) för ytor
   där nyckelägaren är aktiv medlem, inte mallinnehåll.
9. Addon-yta kan inte skapa egna MCP-nycklar (0 egna).
10. Medlemsgräns 4 och mallgräns 200 läses från `shared_workspace_addons`, inte `pro_licenses`.
11. Säker förkontroll (avsnitt 11) körs och är grön innan migrationen appliceras.

## 13. Utanför scope (MVP)

- Löpande månadsdebitering (Stripe/prenumeration/cron) — addon faktureras som
  engångsfaktura tills detta byggs.
- API-nycklar (av i hela MVP).
- Ägar-/organisationsbetald Pro för medlemmar — abstraktionen `has_active_pro_entitlement`
  förbereder det, men bara självbetald Pro är källa i MVP.
- Arbetsyteväxlare för konton med flera ytor (separat, redan känt gap).

## 14. Öppna antaganden

- **Antagande:** inga skarpa kunder på `start` idag → ingen prod-migrering. Bekräftas
  före körning av migrationen mot Supabase.
- **Antagande:** medlemmens Pro-rättighet räcker som premium-åtkomst; den delade
  ytan behöver inte själv ge premium (medlemmar når premium via sin personliga
  Pro-nyckel).
