# Organisatoriska planer: planer.html, admin.html, login.html

**Datum:** 2026-07-20
**Status:** Godkänd av Peter, redo för implementationsplan

## Bakgrund

Delprojekt 6 (öppen katalog, 2026-07-19) gjorde hela promptbiblioteket öppet
och tog bort Pro-menyn/pro.html från kommun.promptbanken.se. Kvar stod tre
sidor som fortfarande pratar om personligt Free/Pro på promptbanken.se:
`planer.html`, `admin.html` och `login.html`. Samtidigt finns Valvet
(valvet.promptbanken.se) som redan är byggt för precis det personliga
användningsfallet (spara egna prompts, promptpaket, personlig MCP-nyckel,
Free/Pro-gränser).

Den här specen reder ut vad de tre sidorna ska bli nu.

## Beslut: personligt flyttar helt till Valvet

promptbanken.se blir renodlat organisatoriskt. Personliga konton
(spara egna mallar, personlig MCP-nyckel, Free/Pro-gränser) finns bara i
Valvet härifrån och framåt. promptbanken.se behåller enbart de tre
organisatoriska nivåerna: **Arbetsyta**, **Förvaltning**, **Kommun**.

Ingen datamigrering behövs — inga riktiga användare har personliga
Free/Pro-konton på promptbanken.se idag (bekräftat med Peter).

## Beslut: Arbetsyta blir fristående, inte Pro-beroende

Idag: "Delad arbetsyta" = Pro + 199 kr/mån, nås via medlemmarnas personliga
Pro-nycklar. Den kopplingen försvinner tillsammans med personligt Pro.

Arbetsyta blir istället en egen, fristående nivå: medlemmar läggs till med
arbetsyte-ägda MCP-nycklar (redan hur nycklar tekniskt fungerar — bara
`plan`-kravet i uppgraderingsflödet som ändras), inget krav på att
medlemmarna har ett personligt Pro/Valvet-konto. Ingen ny
cross-app-integration mot Valvet byggs.

## Beslut: allt organisatoriskt blir kontaktbaserat

Idag är Förvaltning/Kommun redan offert/kontaktbaserade; bara Arbetsyta har
ett självköpsflöde (`admin.html#uppgradera`). Det självköpsflödet är inte i
faktiskt bruk (ingen riktig betalningsintegration). Istället för att riva
koden byts dess CTA/submit-beteende till en kontakt-länk
(`info@promptbanken.se`) för alla tre nivåer. Markupen/formuläret i
`#uppgradera` lämnas orörd i koden så den kan återaktiveras senare.

Priser tas bort helt ur `planer.html` — alla tre nivåer blir
"Pris enligt offert" (tidigare hade Arbetsyta ett cirkapris, det försvinner
nu när även den är kontaktbaserad).

## Sidorna

### login.html

- Tar bort fliken "Skapa free-konto" och hela `auth-plan-compare`-blocket
  (Free/Pro-jämförelsen + länken till planer.html).
- Kvar: "Logga in" + "Glömt lösenord" + "Fortsätt med Google".
- Ny rad längst ner: hänvisning till Valvet för personligt bruk, och till
  `info@promptbanken.se`/den egna administratören för organisatorisk åtkomst.

### admin.html

- **Ej medlem i någon org-arbetsyta** (workspace `type='personal'` — sker
  idag automatiskt via `ensure_personal_workspace()` vid inloggning utan
  inbjudan): istället för dagens personliga panel visas en enkel skärm:
  "Du är inte medlem i någon organisations-arbetsyta ännu. För eget bruk,
  använd Valvet. För åtkomst via din kommun/företag, kontakta din
  administratör eller info@promptbanken.se."
  `ensure_personal_workspace()`-RPC:n behålls oförändrad i backend (ofarlig
  att fortsätta anropa) — bara admin.html:s rendering för `type='personal'`
  byts ut.
- **"Din plan"-panelen** (`#plan`): tas bort för personal-fallet (ersätts av
  skärmen ovan). För org-workspaces visas fortsatt aktuell nivå
  (Arbetsyta/Förvaltning/Kommun), utan pris eller "Pro"-språk.
- **"Mina prompts"**: synlighetsvalet Privat/Workspace tas bort ur
  skapa-formuläret — allt som skapas här blir `visibility='workspace'`
  (delat inom organisationen). Mallgräns/kvot-räknaren finns kvar, kopplad
  till org-nivåns gräns istället för personligt Free/Pro.
- **`#uppgradera`-formuläret**: markup/kod kvar, men submit-knapp och
  CTA-texter ("Uppgradera till Pro" m.fl.) byts till en kontakt-CTA
  ("Kontakta oss på info@promptbanken.se för att uppgradera") för alla tre
  nivåer. Inget faktiskt köp triggas längre av formuläret.
- **`#kom-igang-personlig`** (onboarding: "skapa en personlig MCP-nyckel")
  tas bort — ersätts av Valvet-hänvisningen i inte-medlem-skärmen.
- **Org-onboarding** (`#kom-igang`, delad MCP-nyckel), medlemshantering,
  granskning och bibliotek-sektionerna är oförändrade.

### planer.html

- Ny rad överst: "Letar du efter ett personligt konto? Använd
  [Valvet](https://valvet.promptbanken.se) för att spara egna prompts."
- Free- och Pro-korten tas bort helt ur `plan-grid`.
- Kvar: Arbetsyta, Förvaltning, Kommun — alla tre "Pris enligt offert".
- "Så fungerar köpet"-sektionen skrivs om: alla tre nivåer är förfrågan, vi
  återkommer med offert (inget självköp kvar ens för Arbetsyta).
- "Vad är skillnaden"-sektionen: tar bort meningen om att alla medlemmar har
  sin egen Pro. Arbetsyta beskrivs som fristående — medlemmar läggs till med
  arbetsyte-ägda MCP-nycklar, inget personligt Pro/Valvet-krav.

## Utanför scope

Statistik för öppen MCP-användning (vilka prompter som används, för
plattformsadmin) är ett separat, efterföljande spår — kräver ny
DB-instrumentering (inget persistent användningsspår finns idag, bara
efemär Docker-stdout-loggning, se research 2026-07-20). Egen
brainstorm/spec, inte del av den här.

Kontextval/profiler (kommun/skola/företag/privat/generell,
kombinerbara profiler) är också ett separat, ej påbörjat spår — se
`TODO.md`.
