# Pilot: Mob AI-bootstrap

Datum: 2026-07-31
Status: Godkänd

## Mål

Göra den godkända Mob AI-modellen lätt att hitta och återanvända för nästa
Promptbanken-uppgift utan att ändra produktens beteende.

## Primär modul

Bootstrap av Mob AI-arbetssättet (ingen produktmodul). Detta är en
dokumentations- och repetitionsuppgift för agentdriften, inte en grön
modulpilot från modulkartan. Den första skarpa gröna modulpiloten återstår
och ska använda en exakt modul från modulkartan.

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

- Bootstrapen har återställt och provat den operativa agentdriften utan att
  klassas som produktmodulpilot.
- Strukturkontroll av uppdragskort och mall: PASS.
- Kontroll av länk från `AGENTS.md`: PASS.
- Git-kontroll av Task 1 och Task 2:s skrivytor: PASS.
- `git diff --check`: PASS.
- Produktkod, promptinnehåll, Supabase, MCP och deploykonfiguration: orörda.
- QA-domslut: godkänd i ett separat granskningspass.

## Verifieringsbevis

Den oberoende QA-granskningen kördes mot de controller-godkända rangerna:

```powershell
$task1Range = '67b3a4c..c84e990'
$task2Range = 'c84e990..ceb752b'
$combinedRange = '67b3a4c..ceb752b'
$task1Files = @(git diff --name-only $task1Range | Where-Object { $_ })
$task2Files = @(git diff --name-only $task2Range | Where-Object { $_ })
$allowedTask1 = @('.agents/mob-ai/pilots/2026-07-31-bootstrap.md')
$allowedTask2 = @('AGENTS.md', '.agents/mob-ai/README.md', '.agents/mob-ai/task-card-template.md')
$badTask1 = @($task1Files | Where-Object { $_ -notin $allowedTask1 })
$badTask2 = @($task2Files | Where-Object { $_ -notin $allowedTask2 })
if ($badTask1.Count -gt 0) { throw "Task 1 scope violation: $($badTask1 -join ', ')" }
if ($badTask2.Count -gt 0) { throw "Task 2 scope violation: $($badTask2 -join ', ')" }
git diff --check $combinedRange
if ($LASTEXITCODE -ne 0) { throw 'Whitespace verification failed' }
Write-Output 'Independent Mob AI QA: PASS'
```

Faktisk sammanfattad output: Task 1 omfattade endast
`.agents/mob-ai/pilots/2026-07-31-bootstrap.md`; Task 2 omfattade endast
`AGENTS.md`, `.agents/mob-ai/README.md` och
`.agents/mob-ai/task-card-template.md`; whitespace-kontrollen gav ingen
output och QA-kommandot gav `Independent Mob AI QA: PASS`.

Efter Task 3 kördes closure-checken:

```powershell
$pilot = Get-Content -Raw -LiteralPath '.agents/mob-ai/pilots/2026-07-31-bootstrap.md'
$model = Get-Content -Raw -LiteralPath 'docs/mob-ai-operating-model.md'
if (-not $pilot.Contains('Status: Godkänd')) { throw 'Pilot is not approved' }
if (-not $pilot.Contains('## Resultat')) { throw 'Pilot result is missing' }
if (-not $pilot.Contains('## Lärdomar')) { throw 'Pilot lessons are missing' }
if (-not $model.Contains('## Operativ ingång')) { throw 'Operating entry point is missing' }
if (-not $model.Contains('.agents/mob-ai/task-card-template.md')) {
  throw 'Operating model does not link to the task-card template'
}
Write-Output 'Mob AI pilot closure: PASS'
```

Faktisk output: `Mob AI pilot closure: PASS`.

## Lärdomar

- Skrivgränsen var begriplig och kunde verifieras maskinellt.
- Den separata QA-granskningen kunde avgöra både struktur och commitomfång
  utan att ändra implementationen.
- Överlämningen krävde inga muntliga antaganden utöver uppdragskortet.
- Den första skarpa gröna modulpiloten återstår och ska köras i en befintlig
  grön produktmodul med exakt modulnamn från modulkartan.
