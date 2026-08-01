# Pilot: Ta bort döda seed-poster i promptUiMeta (korrigerad uppföljning)

Datum: 2026-08-01
Status: Godkänd

## Resultat

- Modulagent tog bort de 20 döda seed-posterna i isolerad worktree,
  lämnade `const promptUiMeta = {};` orört som deklaration.
- Oberoende QA-agent verifierade i samma worktree: diff-omfattning,
  `getPromptMeta()`-logik oförändrad, `registerOwnPrompts`/
  `registerProTemplates` läser aldrig `promptUiMeta` före skrivning,
  alla 20 nycklar borta utan att lämna trasiga rester, `node --check`
  syntax-OK. **QA-domslut: PASS.**
- Mob-ledaren kopierade in den granskade filen i huvudrepot, körde
  sidans egna inbyggda regressionstester live (LocalStorage Test,
  Export Modal Elements Test, Regression Test Results, Global Context
  Storage Test, Catalog Config Validation Test) — alla gröna, 0
  konsolfel, katalogen renderade 63 kort med oförändrade roll/
  målgrupp-taggar.
- `git diff --stat`: enbart `script.js`, 1 insertion, 22 deletions.

## Lärdomar

- Den korrigerade, smalare skrivytan (bara innehållet i objektlitteralen,
  inte behållaren) höll modulagenten inom säker mark på första försöket.
- Att kräva explicit läsning av `registerOwnPrompts`/`registerProTemplates`
  som eget acceptanskriterium (istället för att anta det) gjorde att både
  modulagent och QA-agent faktiskt spårade koden, inte bara upprepade
  föregångarens slutsats.
- Två-pilots-mönstret (blockerad → lärdom → korrigerad, smalare
  uppföljning) är troligen den normala vägen för röda/gula moduler, inte
  ett undantag.
Föregångare: `.agents/mob-ai/pilots/2026-08-01-remove-dead-promptUiMeta.md`
(blockerades korrekt — se den för bakgrund om varför hela objektet inte
får raderas).

## Mål

Ta bort de 20 bekräftat döda statiska seed-posterna i `promptUiMeta`
(script.js, rad ~1131-1150) utan att röra själva behållaren eller de
dynamiska skrivplatserna, så att `registerOwnPrompts`/`registerProTemplates`
fortsätter fungera oförändrat.

## Primär modul

Katalog-UI (`script.js` / `promptbanken.html`) — 🔴 röd i modulkartan.
Samma godkända undantag som föregångaren: ren radering av bekräftat död
data, inte funktionell ändring.

## Bakgrund (redan verifierat, två gånger — mob-ledare + oberoende QA)

- `promptUiMeta` har 20 statiska nycklar, alla redan shadowade av
  `mcpPromptMeta` i `getPromptMeta()` — bekräftat både av mob-ledaren och
  oberoende omräknat av QA-agenten i föregående pilot.
- `promptUiMeta[item.id] = {...}` skrivs dynamiskt vid körning från
  `registerOwnPrompts()` (rad ~1891) och `registerProTemplates()`
  (rad ~1934), anropade från `promptbanken.html` när Supabase är
  konfigurerat. Dessa MÅSTE fortsätta fungera.

## Tillåten skrivyta

- `script.js` — enbart: radera de 20 statiska nyckel-värde-paren inuti
  `promptUiMeta`-objektlitteralen (rad ~1131-1150), så att kvar blir
  `const promptUiMeta = {};` (tomt objekt). Rör INGET annat — inte
  objektets deklaration/namn, inte `getPromptMeta()`, inte
  `registerOwnPrompts`/`registerProTemplates`.

## Läsberoenden

- `mcpPromptMeta`-objektet (för att bekräfta överlappet på nytt)
- `promptbanken.html` (för att hitta anropskedjan till
  `registerOwnPrompts`/`registerProTemplates`)
- Föregående pilotkort (`2026-08-01-remove-dead-promptUiMeta.md`)

## Förbjudna och känsliga ytor

- `mcpPromptMeta`
- `getPromptMeta()`s logik (fallback-raden ska INTE ändras — den
  fungerar redan korrekt mot ett tomt objekt)
- `registerOwnPrompts`/`registerProTemplates`-funktionerna
- Allt annat i `script.js`, `style.css`, `promptbanken.html`,
  `skills.json`, `prompts.json`
- Supabase, MCP, deploykonfiguration, push, deploy

## Gränssnittsartefakt

`getPromptMeta()`s returform (samma som föregångaren). Måste vara
identisk för alla 21 `mcpPromptMeta`-ID:n och för det generiska
fallback-fallet.

## Acceptanskriterier

1. `promptUiMeta` finns kvar som `const promptUiMeta = {};` (tomt),
   inte borttagen.
2. De 20 statiska seed-posterna finns inte längre i objektlitteralen.
3. `getPromptMeta()` returnerar identiskt resultat för alla 21
   `mcpPromptMeta`-ID:n jämfört med innan (oförändrat, eftersom de aldrig
   läste seed-datan).
4. `getPromptMeta()` returnerar samma generiska fallback som innan för
   ett ID som saknas i `mcpPromptMeta` OCH inte skrivits dynamiskt.
5. **Nytt jämfört med föregångaren:** bekräfta genom kodläsning (inte
   bara antagande) att `registerOwnPrompts(items)` och
   `registerProTemplates(items)` fortfarande kan skriva
   `promptUiMeta[item.id] = {...}` mot det tomma objektet utan fel —
   dvs att inget i deras kod förutsätter att specifika statiska nycklar
   redan finns i `promptUiMeta` innan de skriver.
6. Inga andra filer än `script.js` är ändrade.

## Obligatorisk verifiering

- Läs `registerOwnPrompts`/`registerProTemplates` i sin helhet och
  bekräfta att de inte läser (bara skriver till) `promptUiMeta` innan de
  sätter sitt eget värde.
- Jämför `getPromptMeta()`s returvärde för 2-3 exempel-ID:n (t.ex. 'faq',
  'klarsprak') före/efter — måste vara bitvis identiska.
- `git diff --name-only`: endast `script.js`.
- `git diff -- script.js`: bekräfta att bara raderna inuti
  `promptUiMeta`-litteralen är borttagna, inget annat.

## Roller

- Mob-ledare: huvudtråden.
- Modulagent: separat Task-subagent i isolerad worktree.
- QA-agent: separat, isolerad Task-subagent — ser bara detta kort +
  den färdiga diffen.
- Kontraktsdomare: behövs inte.
- Releaseagent: mob-ledaren; releaseomfattning är lokal commit, ingen
  push utan nytt uttryckligt godkännande.

## Releaseomfattning

Lokal commit. Ingen push, deploy eller produktionsändring i detta uppdrag.
