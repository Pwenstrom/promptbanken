# Pilot: Ta bort död kod i promptUiMeta (script.js)

Datum: 2026-08-01
Status: Blockerad — felaktig premiss upptäckt av modulagenten

## Resultat (delvis — se Lärdomar)

Modulagenten vägrade genomföra uppdraget som skrivet. Mob-ledarens
förhandsverifiering (grep efter `promptUiMeta\s*=` + läsning av
`getPromptMeta()`) missade två skrivplatser: `registerOwnPrompts()`
(rad ~1891) och `registerProTemplates()` (rad ~1934) skriver dynamiskt
genererade Supabase-ID:n in i `promptUiMeta` vid körning för inloggade
användare, och `getPromptMeta()`s fallback-gren läser tillbaka dessa.

Endast de 20 statiska seed-posterna (rad 1131-1150) är bekräftat döda.
Behållaren `promptUiMeta` och skrivplatserna är levande. Att radera hela
objektet hade orsakat `ReferenceError` för varje inloggad användare med
egna sparade prompts eller Pro-mallar.

Ingen kodändring gjordes. `git diff` bekräftat tomt av modulagenten.

## Lärdomar

- Modulagenten stoppade sig själv på fel premiss istället för att
  genomföra blint — exakt vad "Implementering och domslut separeras"
  och "Bevis före status" är till för.
- Mob-ledarens egen förhandsverifiering var otillräcklig: en riktad grep
  (`promptUiMeta\s*=`) missade skrivplatser som inte matchade mönstret
  exakt. En fullständig `grep -n promptUiMeta` (utan ankare) hade
  hittat alla fyra träffar direkt.
- Korrekt omfattning för en ny pilot: behåll `const promptUiMeta = {}`
  (tom, inte borttagen) och radera bara de 20 statiska seed-posterna
  rad 1131-1150 samt förenkla fallback-raden i `getPromptMeta()` till att
  fortfarande läsa `promptUiMeta[prompt.id]` (nu bara aldrig
  förhandsifylld) — det är fortfarande en giltig, mindre städning, men
  kräver ett nytt uppdragskort med korrekt skrivyta.

## Mål

Ta bort det bekräftat döda `promptUiMeta`-objektet i `script.js` (och dess
nu överflödiga fallback-gren i `getPromptMeta()`) utan att ändra någon
observerbar katalogfunktion.

## Primär modul

Katalog-UI (`script.js` / `promptbanken.html`) — 🔴 röd i modulkartan
(`docs/module-map-2026-07-31.md`).

**Undantag från röd-modul-regeln, godkänt av produktägaren:** modellens
"Regler för parallellt arbete" tillåter röda moduler bara
"avgränsnings- och extraktionsarbete", inte vanligt feature-arbete. Detta
uppdrag är en ren radering av bekräftat oanvänd kod (0 av 20 nycklar i
`promptUiMeta` är unika mot `mcpPromptMeta`, verifierat mekaniskt innan
uppdraget skapades — se Bakgrund), inte en funktionell ändring. Bedömt som
lägre risk än regeln avser att stoppa. Denna bedömning gjordes av mob-ledaren
och godkändes explicit av produktägaren innan uppdraget startade.

## Bakgrund (redan verifierat av mob-ledaren innan uppdraget)

`getPromptMeta()` i `script.js` slår upp `mcpPromptMeta[prompt.id]` först;
`promptUiMeta[prompt.id]` används bara som fallback om `mcpPromptMeta` saknar
träff. Ett skript som extraherade nycklarna ur båda objekten visade:

```
promptUiMeta count: 20
mcpPromptMeta count: 21
only in promptUiMeta (live fallback): []
only in mcpPromptMeta: [ 'tydlighetskoll' ]
```

Alla 20 nycklar i `promptUiMeta` finns redan i `mcpPromptMeta`, som alltid
vinner. `promptUiMeta` nås aldrig för någon prompt som faktiskt existerar
idag.

## Tillåten skrivyta

- `script.js` — enbart: (a) radera `promptUiMeta`-objektet i sin helhet, (b)
  ta bort raden `const fallbackMeta = promptUiMeta[prompt.id] || {...}` i
  `getPromptMeta()` och ersätt med enbart de generiska defaultvärdena
  (samma objekt som redan står där som `||`-högerled).

## Läsberoenden

- `skills.json` (facit för `mcpPromptMeta`, får inte ändras)
- `prompts.json`
- `docs/module-map-2026-07-31.md`
- `docs/mob-ai-operating-model.md`

## Förbjudna och känsliga ytor

- `mcpPromptMeta`-objektet självt (får läsas, inte ändras)
- Allt annat i `script.js` utanför `promptUiMeta`/`getPromptMeta`s
  fallback-rad
- `style.css`, `promptbanken.html`, `skills.json`, `prompts.json`
- Supabase, MCP, deploykonfiguration
- Push, deploy eller produktionsändring

## Gränssnittsartefakt

Inget externt kontrakt berörs (ingen `mcp-contract.json`-post, ingen
Supabase-RPC). Det interna kontraktet är `getPromptMeta()`s returform
(samma nycklar: icon, category, audience, audiences, role, roles, risk,
example, phrase) — måste vara identisk före och efter för alla 21
`mcpPromptMeta`-ID:n och för det generiska fallback-fallet.

## Acceptanskriterier

1. `promptUiMeta`-objektet finns inte längre i `script.js`.
2. `getPromptMeta()` returnerar bitvis identiskt resultat för alla 21
   ID:n i `mcpPromptMeta`, jämfört med före ändringen.
3. `getPromptMeta()` returnerar samma generiska fallback-objekt som
   tidigare (`icon:'▤', category:'Alla kategorier', ...`) för ett ID som
   saknas i `mcpPromptMeta` (t.ex. ett Supabase-katalog-ID som
   `fc9a9805-...`).
4. Inga andra filer än `script.js` är ändrade.
5. Sidan `promptbanken.html` laddar utan nya konsolfel och katalogen
   renderar samma antal kort som innan (63 vid testtillfället).

## Obligatorisk verifiering

- `node -e "..."`-jämförelse: kör `getPromptMeta()`-liknande logik före/efter
  (eller manuell diff av de 21 ID:nas returvärden).
- `git diff --name-only` mot uppdragets commit-räckvidd: endast `script.js`.
- Live-test i browser: `promptbanken.html` lokalt, kontrollera att katalogen
  renderar, korten visar samma kategori/roll/risk-taggar som innan, inga nya
  konsolfel.
- QA-agenten kör detta i ett separat pass utan att ha sett modulagentens
  implementation i förväg (bara uppdragskortet + resultatet).

## Roller

- Mob-ledare: huvudtråden (Claude, denna session).
- Modulagent: separat Task-subagent, skrivyta enligt ovan.
- QA-agent: separat, isolerad Task-subagent — ser bara uppdragskortet och
  den färdiga diffen, inte modulagentens resonemang.
- Kontraktsdomare: behövs inte (inget externt kontrakt berört).
- Releaseagent: mob-ledaren, men releaseomfattning är lokal commit — push
  ingår inte utan uttryckligt nytt godkännande.

## Releaseomfattning

Lokal commit. Ingen push, deploy eller produktionsändring i detta uppdrag.
