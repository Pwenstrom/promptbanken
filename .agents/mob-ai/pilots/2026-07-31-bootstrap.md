# Pilot: Mob AI-bootstrap

Datum: 2026-07-31
Status: Godkänd

## Mål

Göra den godkända Mob AI-modellen lätt att hitta och återanvända för nästa
Promptbanken-uppgift utan att ändra produktens beteende.

## Primär modul

Agentdrift och projektdokumentation. Mognad: grön för denna pilot eftersom
skrivytan är ny, isolerad och saknar runtimekoppling.

## Tillåten skrivyta

- `AGENTS.md`
- `.agents/mob-ai/README.md`
- `.agents/mob-ai/task-card-template.md`
- `.agents/mob-ai/pilots/2026-07-31-bootstrap.md`
- avsnittet `Operativ ingång` i `docs/mob-ai-operating-model.md`

## Läsberoenden

- `docs/module-map-2026-07-31.md`
- `docs/mob-ai-operating-model.md`
- `docs/agent-boundaries.md`
- `docs/superpowers/specs/2026-07-31-mob-ai-operating-model-design.md`

## Förbjudna och känsliga ytor

- Produktkod, promptinnehåll, Supabase, MCP och deploykonfiguration.
- `script.js`, `style.css`, `src/`, `backend/`, `mcp-server/` och `supabase/`.
- `.codex-audit/` och andra befintliga orelaterade ändringar.

## Gränssnittsartefakt

`docs/agent-boundaries.md` är skrivpolicyn. Detta pilotkort är kontraktet för
den enskilda uppgiften.

## Acceptanskriterier

1. `AGENTS.md` pekar på den operativa Mob AI-ingången.
2. `.agents/mob-ai/README.md` anger läsordning och säkert arbetsflöde.
3. Uppdragskortsmallen innehåller alla obligatoriska fält från modellen.
4. Endast den tillåtna skrivytan har ändrats.
5. En separat QA-granskning har dokumenterats innan status blir godkänd.

## Obligatorisk verifiering

- PowerShell-kontroll av obligatoriska filer, rubriker och länkar.
- `git diff --check`.
- Git-kontroll av att ingen produktfil ingår i pilotens commits.
- Separat QA-läsning mot acceptanskriterierna.

## Roller

- Mob-ledare: avgränsar uppgiften och sammanställer resultatet.
- Modulagent: implementerar endast Task 2:s filer.
- QA-agent: utför Task 3 utan att skriva i Task 2:s implementationspass.
- Kontraktsdomare: behövs inte; inget externt kontrakt eller kollisionspunkt berörs.
- Releaseagent: verifierar commitomfång. Push och deploy ingår inte.

## Releaseomfattning

Lokala commits. Ingen push, deploy eller produktionsändring.

## Resultat

- Strukturkontroll av uppdragskort och mall: PASS.
- Kontroll av länk från `AGENTS.md`: PASS.
- Git-kontroll av Task 1 och Task 2:s skrivytor: PASS.
- `git diff --check`: PASS.
- Produktkod, promptinnehåll, Supabase, MCP och deploykonfiguration: orörda.
- QA-domslut: godkänd av en separat granskningspass.

## Lärdomar

- Skrivgränsen var begriplig och kunde verifieras maskinellt.
- Den separata QA-granskningen kunde avgöra både struktur och commitomfång
  utan att ändra implementationen.
- Överlämningen krävde inga muntliga antaganden utöver uppdragskortet.
- Mer avancerad orkestrering behövs inte innan modellen provas på nästa lilla
  ändring i en befintlig grön produktmodul.
