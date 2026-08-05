# OpenAI app-katalog: listningstext

## Bakgrund

Del 2 av 3 i förberedelsen för att publicera Promptbanken i OpenAI:s
ChatGPT app-katalog (del 1, teknisk readiness, spec
`2026-08-04-openai-app-directory-technical-readiness-design.md` i
`mcp_promptbanken`-repot, under implementation). Submission-portalen kräver
namn, kort/lång beskrivning, kategori, support-/privacy-/terms-URL och ett
land-tillgänglighetsval. Logo/grafik är uttryckligen utanför scope — Peters
jobb.

## Mål

Ett kopierbart textutkast för submission-portalens Info-flik, klart att
klistra in.

## Icke-mål

- Ingen logo, ingen grafisk asset.
- Inget exakt kategorival — portalens dropdown är bara synlig inloggad;
  detta dokument ger en rekommendation, Peter låser det slutgiltiga valet
  i portalen.
- Ingen ändring av `privacy.html`/`terms.html` — de återanvänds som de är.
- Ingen kod, ingen deploy — rent textleverabel.

## Leverabel

### Namn

Promptbanken

### Kort beskrivning

Öppet bibliotek med färdiga, GDPR-medvetna promptmallar på svenska — för
kommuner och organisationer som vill skriva tydligare med AI.

### Lång beskrivning

Promptbanken ger färdiga promptmallar för vanliga kommunala och
organisatoriska skrivuppgifter: klarspråk, medborgarmejl, sammanfattningar,
checklistor, mötesanteckningar och informationsutskick. Varje mall är byggd
för att minska risken för att personuppgifter eller känslig information
hamnar i en AI-modell — inte bara ett bibliotek att kopiera text från, utan
mallar som guidar användaren till en säkrare, tydligare text från början.

Sök och bläddra i det öppna biblioteket direkt i ChatGPT: hitta en mall
efter ämne, roll eller risknivå, eller be om rekommendationer utifrån din
yrkesroll. Varje mall visar sitt syfte, målgrupp och en risknivå så du vet
vad du behöver tänka på innan du använder den. Biblioteket är publikt och
kräver ingen inloggning eller nyckel.

### Logo

Brand-assetpaket mottaget 2026-08-05, sparat i
`docs/bilder/brand/` (repo). Använd `promptbanken-icon-512.png`
(512×512, avrundad ljus bakgrund — designad för app-ikon-kontext) som
submission-logo. `promptbanken-mark-transparent.png` finns som frilagd
variant om portalen kräver transparent bakgrund istället.

Samma paket har redan wirats in på sajten: favicon/apple-touch-icon i
`public/`, länkade i `<head>` på samtliga 14 sidor (commit pending).

### Kategori (rekommendation, låses i portalen)

Produktivitet / Skrivande — biblioteket löser en konkret skrivuppgift
(hitta och anpassa en mall), inte en bred assistent- eller
underhållningsfunktion.

### Support-URL

`mailto:info@promptbanken.se` (redan i bruk på `terms.html`/`privacy.html`)

### Privacy policy-URL

`https://app.promptbanken.se/privacy.html`

### Terms-URL

`https://app.promptbanken.se/terms.html`

### Country availability (rekommendation)

Sverige. Katalogens innehåll är på svenska och riktat mot svensk kommunal
kontext (`arbetsbank`, `beslutsberedning` m.fl. områden) — bredare
tillgänglighet ger sannolikt låg relevans för icke-svensktalande
användare utan att ge en produktfördel. Peter beslutar i portalen; enkelt
att utöka senare om efterfrågan uppstår.

## Verifiering

Ingen — textleverabel, inget att köra eller testa. Peter läser igenom och
justerar ton/ordval efter smak innan det klistras in i portalen.
