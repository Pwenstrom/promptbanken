# Promptbanken Anvandartest Atgardspec

**Datum:** 2026-07-31

**Mal:** Atgarda de sista anvandbarhetsproblemen fran live-testet pa `app.promptbanken.se` utan att andra Promptbankens grundflode: hitta prompt, valj prompt, anonymisera egen text och kopiera prompt.

## Scope

- Forbattra mobilflodet i `promptbanken.html`, `style.css` och `script.js`.
- Gora forhandsvisningens effekt tydlig.
- Se till att tomresultat bara exponeras nar det faktiskt ar tomt.
- Minska risken att dolda knappar och gamla kortytor hamnar i tillganglighetstradet.

## Krav

1. Katalogen ska fortfarande visa antal prompter, filter, sortering och promptkort pa desktop.
2. Pa mobil ska anvandaren komma till promptlistan snabbare; statistik och sekundar metadata ska inte ta over forsta arbetsflodet.
3. `Fler filter` ska oppna och stanga extra filter pa mobil och uppdatera `aria-expanded`.
4. Nar en sokning har traffar ska tomresultatets text och knapp vara `hidden`, inte bara visuellt irrelevant.
5. `Forhandsvisa` i detaljpanelen ska oppna en tydlig modal med aktuell renderad prompttext.
6. Modal ska ha dialogsemantik, stangknapp med begriplig aria-label och `aria-modal`.
7. Dolda kortknappar och textareas i promptkorten ska inte exponeras for tangentbord eller hjalpmedel.
8. Desktopens befintliga trepanelsarbetsyta ska bevaras.

## Implementation

- `promptbanken.html`
  - Uppdatera modalens semantik.
  - Gora filteromradet till ett tydligare mobilkontrollerat block.
  - Markera promptkortens dolda textarea som intern teknisk lagring via JS.
- `script.js`
  - Lagg till `setElementHiddenState` for att samordna `hidden`, `aria-hidden` och `inert` dar det ar sakert.
  - Anvand helpern nar promptkort filtreras och nar tomresultat visas/doljs.
  - Lagg till mobilfilter-toggle.
  - Gora `Forhandsvisa` i detaljpanelen till en direkt modaloppning for vald prompt.
  - Stoppa promptkortets generella klick fran att dubbelkora nar anvandaren klickar pa kortknappar.
- `style.css`
  - Justera mobilnavigering sa den horisontella listan inte later hela sidan overflowa.
  - Gora promptlistan mer framtradande pa mobil och kompaktera intro/anpassningsyta.
  - Sakerstalla att tomlage och modal har tydliga visuella tillstand.

## Verifiering

- Kor `npm run build`.
- Verifiera lokalt med Vite eller preview:
  - desktop: sok `klarsprak`, valj prompt, skriv text, kopiera, forhandsvisa.
  - mobil 390px: promptlistan ska vara nabar utan horisontell sidoverflow; `Fler filter` ska oppna/stanga.
  - tom sokning: endast tomlage ska visas och `Rensa filter` ska aterstalla.
