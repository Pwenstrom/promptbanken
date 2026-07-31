# Mob AI First Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Göra Promptbankens interna Mob AI-modell körbar genom ett första avgränsat pilotuppdrag med återanvändbart uppdragskort, repoingång och oberoende verifiering.

**Architecture:** De styrande dokumenten ligger kvar under `docs/`. En liten operativ yta under `.agents/mob-ai/` länkar till dem, ger agenter ett standardiserat uppdragskort och sparar pilotens beslut och bevis. Ingen produktkod, runtime, databas, MCP-yta eller deploy påverkas.

**Tech Stack:** Markdown, Git och PowerShell-baserade strukturkontroller.

## Global Constraints

- Mob AI är ett internt arbetssätt, inte en publik produktfunktion.
- Ingen agent får stående behörighet att pusha, deploya eller ändra produktionsdata.
- Pilotens enda skrivytor är `AGENTS.md`, `.agents/mob-ai/` och den uttryckligen angivna delen av `docs/mob-ai-operating-model.md`.
- `script.js`, `style.css`, `src/`, `backend/`, `mcp-server/`, `supabase/`, promptregistren och produktionskonfiguration ska förbli orörda.
- `.codex-audit/` tillhör befintlig lokal verifiering och får inte staged, ändras eller tas bort.
- Dokumenten ska använda svenska där de instruerar Promptbanken-agenter. Det befintliga ASCII-mönstret i `AGENTS.md` ska bevaras.
- Ingen webbbuild krävs när den faktiska diffen endast innehåller Markdown och `AGENTS.md`; `git diff --check` och de exakta strukturkontrollerna nedan är obligatoriska.
- Implementeraren får inte ensam godkänna piloten. Task 3 ska utföras som en separat QA-/integrationsgranskning.

---

### Task 1: Skapa pilotens låsta uppdragskort

**Files:**

- Create: `.agents/mob-ai/pilots/2026-07-31-bootstrap.md`
- Read: `docs/module-map-2026-07-31.md`
- Read: `docs/mob-ai-operating-model.md`
- Read: `docs/agent-boundaries.md`

**Interfaces:**

- Consumes: Mognadsregler, roller, uppdragskortsfält och definition av klart från de tre styrande dokumenten.
- Produces: Ett komplett pilotkontrakt med exakt skrivyta och statusen `Redo för implementering`, som Task 2 måste följa.

- [ ] **Step 1: Kör strukturkontrollen och verifiera att pilotkortet ännu saknas**

Run:

```powershell
$pilotPath = '.agents/mob-ai/pilots/2026-07-31-bootstrap.md'
if (-not (Test-Path -LiteralPath $pilotPath)) {
  throw "Pilot task card is missing: $pilotPath"
}
```

Expected: FAIL with `Pilot task card is missing`.

- [ ] **Step 2: Skapa pilotkortet med exakt innehåll**

Use `apply_patch` to create `.agents/mob-ai/pilots/2026-07-31-bootstrap.md`:

```markdown
# Pilot: Mob AI-bootstrap

Datum: 2026-07-31
Status: Redo för implementering

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
```

- [ ] **Step 3: Kör pilotkortets strukturkontroll**

Run:

```powershell
$pilotPath = '.agents/mob-ai/pilots/2026-07-31-bootstrap.md'
$content = Get-Content -Raw -LiteralPath $pilotPath
$required = @(
  '## Mål',
  '## Primär modul',
  '## Tillåten skrivyta',
  '## Läsberoenden',
  '## Förbjudna och känsliga ytor',
  '## Gränssnittsartefakt',
  '## Acceptanskriterier',
  '## Obligatorisk verifiering',
  '## Roller',
  '## Releaseomfattning'
)
foreach ($heading in $required) {
  if (-not $content.Contains($heading)) { throw "Missing heading: $heading" }
}
if (-not $content.Contains('Status: Redo för implementering')) {
  throw 'Pilot status is not ready for implementation'
}
Write-Output 'Pilot task card: PASS'
```

Expected: `Pilot task card: PASS`.

- [ ] **Step 4: Verifiera diff och committa uppdragskortet**

Run:

```powershell
git diff --check
git status --short
```

Expected: no output from `git diff --check`; status lists only the new pilot card plus the pre-existing untracked `.codex-audit/` when execution happens in the current workspace.

Commit:

```powershell
git add -- .agents/mob-ai/pilots/2026-07-31-bootstrap.md
git commit -m "docs: add first mob ai pilot card"
```

---

### Task 2: Skapa den operativa Mob AI-ingången

**Files:**

- Create: `.agents/mob-ai/README.md`
- Create: `.agents/mob-ai/task-card-template.md`
- Modify: `AGENTS.md:5-18`
- Read: `.agents/mob-ai/pilots/2026-07-31-bootstrap.md`

**Interfaces:**

- Consumes: Pilotkortets tillåtna skrivyta och acceptanskriterier.
- Produces: En stabil startpunkt på `.agents/mob-ai/README.md`, en återanvändbar mall med tio obligatoriska rubriker och en upptäckbar länk från `AGENTS.md`.

- [ ] **Step 1: Kör en förkontroll som ska misslyckas före implementation**

Run:

```powershell
$requiredFiles = @(
  '.agents/mob-ai/README.md',
  '.agents/mob-ai/task-card-template.md'
)
foreach ($file in $requiredFiles) {
  if (-not (Test-Path -LiteralPath $file)) { throw "Missing Mob AI file: $file" }
}
$agents = Get-Content -Raw -LiteralPath 'AGENTS.md'
if (-not $agents.Contains('.agents/mob-ai/README.md')) {
  throw 'AGENTS.md does not link to the Mob AI entry point'
}
```

Expected: FAIL on the first missing Mob AI file.

- [ ] **Step 2: Skapa den operativa README-filen**

Use `apply_patch` to create `.agents/mob-ai/README.md`:

```markdown
# Mob AI för Promptbanken

Detta är den operativa ingången för agentarbete enligt Promptbankens Mob
AI-modell. Ytan ger inga extra behörigheter och ersätter inte projektets
övriga instruktioner.

## Läsordning

1. Läs rotens `AGENTS.md`.
2. Läs `docs/module-map-2026-07-31.md` och identifiera primär modul.
3. Läs `docs/agent-boundaries.md` och lås skrivytan.
4. Läs `docs/mob-ai-operating-model.md` för roller och arbetsflöde.
5. Skapa ett uppdragskort från `.agents/mob-ai/task-card-template.md`.

## Minsta säkra mob

- En mob-ledare avgränsar uppgiften.
- En modulagent implementerar inom uppdragskortets skrivyta.
- En separat QA-agent verifierar acceptanskriterierna.
- En kontraktsdomare kopplas in när ett externt kontrakt eller en
  kollisionspunkt påverkas.

## Stoppregler

- Stoppa om den nödvändiga filen ligger utanför uppdragskortets skrivyta.
- Stoppa om modul eller gränssnittsartefakt inte kan namnges.
- Stoppa om en röd modul får vanligt feature-arbete utan extraktionsplan.
- Stoppa före push, deploy eller produktionsändring utan uttryckligt uppdrag.

## Pilotjournal

Genomförda piloter sparas i `.agents/mob-ai/pilots/`. Journalen ska innehålla
uppdragskort, verifieringsbevis, QA-domslut och lärdomar.
```

- [ ] **Step 3: Skapa den återanvändbara uppdragskortsmallen**

Use `apply_patch` to create `.agents/mob-ai/task-card-template.md`:

```markdown
# Mob AI-uppdragskort

Använd instruktionerna under varje rubrik när ett nytt kort skapas. Det
färdiga kortet ska ersätta instruktionerna med konkreta beslut.

## Mål

Skriv en verifierbar mening som beskriver vilket resultat uppgiften ska ge.

## Primär modul

Namnge exakt en modul från modulkartan och ange grön, gul eller röd mognad.

## Tillåten skrivyta

Lista varje fil eller avgränsat sökvägsmönster som agenten får ändra.

## Läsberoenden

Lista kontrakt, dokument och kod som får läsas men inte ändras.

## Förbjudna och känsliga ytor

Lista kollisionspunkter, hemligheter, produktionsytor och orelaterade filer.

## Gränssnittsartefakt

Namnge kontraktet som måste förbli giltigt efter ändringen.

## Acceptanskriterier

Skriv numrerade, observerbara villkor med tydligt godkänt eller underkänt.

## Obligatorisk verifiering

Ange exakta kommandon, manuella flöden och förväntade resultat.

## Roller

Namnge mob-ledare, modulagent, QA-agent, eventuell kontraktsdomare och
releaseagent för uppgiften.

## Releaseomfattning

Ange uttryckligen om uppgiften slutar vid lokal ändring, commit, push, deploy
eller liveverifiering.
```

- [ ] **Step 4: Länka Mob AI-ingången från projektinstruktionen**

Use `apply_patch` to insert this block in `AGENTS.md` immediately before `## Vanliga kommandon`:

```markdown
## Mob AI

- Vid Mob AI-arbete: las `.agents/mob-ai/README.md` efter snabb
  orientering.
- Skapa ett uppdragskort innan implementation och hall dig inom dess
  skrivyta.
- Modulmognad och kollisionspunkter finns i
  `docs/module-map-2026-07-31.md` och `docs/agent-boundaries.md`.

```

- [ ] **Step 5: Kör struktur- och omfångskontroller**

Run:

```powershell
$readme = Get-Content -Raw -LiteralPath '.agents/mob-ai/README.md'
$template = Get-Content -Raw -LiteralPath '.agents/mob-ai/task-card-template.md'
$agents = Get-Content -Raw -LiteralPath 'AGENTS.md'
$requiredHeadings = @(
  '## Mål',
  '## Primär modul',
  '## Tillåten skrivyta',
  '## Läsberoenden',
  '## Förbjudna och känsliga ytor',
  '## Gränssnittsartefakt',
  '## Acceptanskriterier',
  '## Obligatorisk verifiering',
  '## Roller',
  '## Releaseomfattning'
)
foreach ($heading in $requiredHeadings) {
  if (-not $template.Contains($heading)) { throw "Template missing: $heading" }
}
if (-not $readme.Contains('docs/agent-boundaries.md')) {
  throw 'README does not link to agent boundaries'
}
if (-not $agents.Contains('.agents/mob-ai/README.md')) {
  throw 'AGENTS.md does not link to Mob AI README'
}
$allowed = @(
  '.agents/mob-ai/README.md',
  '.agents/mob-ai/task-card-template.md',
  'AGENTS.md'
)
$changed = @(git diff --name-only)
$unexpected = @($changed | Where-Object { $_ -notin $allowed })
if ($unexpected.Count -gt 0) { throw "Unexpected files: $($unexpected -join ', ')" }
Write-Output 'Mob AI entry point: PASS'
```

Expected: `Mob AI entry point: PASS`.

Run:

```powershell
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 6: Committa den operativa ingången**

```powershell
git add -- AGENTS.md .agents/mob-ai/README.md .agents/mob-ai/task-card-template.md
git commit -m "docs: add mob ai agent entry point"
```

---

### Task 3: Oberoende QA och stängning av piloten

**Files:**

- Modify: `.agents/mob-ai/pilots/2026-07-31-bootstrap.md`
- Modify: `docs/mob-ai-operating-model.md:76-94`
- Read: `.agents/mob-ai/README.md`
- Read: `.agents/mob-ai/task-card-template.md`
- Read: `AGENTS.md`

**Interfaces:**

- Consumes: De två commits som Task 1 och Task 2 producerar samt pilotkortets fem acceptanskriterier.
- Produces: Ett separat QA-domslut, en stängd pilotjournal och en permanent länk från den operativa modellen till `.agents/mob-ai/`.

- [ ] **Step 1: Utför en separat, skrivskyddad QA-granskning**

Assign this step to a fresh QA reviewer. The reviewer must not edit files.

Run:

```powershell
$requiredFiles = @(
  'AGENTS.md',
  '.agents/mob-ai/README.md',
  '.agents/mob-ai/task-card-template.md',
  '.agents/mob-ai/pilots/2026-07-31-bootstrap.md'
)
foreach ($file in $requiredFiles) {
  if (-not (Test-Path -LiteralPath $file)) { throw "Missing required file: $file" }
}
$template = Get-Content -Raw -LiteralPath '.agents/mob-ai/task-card-template.md'
$headings = @(
  '## Mål', '## Primär modul', '## Tillåten skrivyta', '## Läsberoenden',
  '## Förbjudna och känsliga ytor', '## Gränssnittsartefakt',
  '## Acceptanskriterier', '## Obligatorisk verifiering', '## Roller',
  '## Releaseomfattning'
)
foreach ($heading in $headings) {
  if (-not $template.Contains($heading)) { throw "Missing template heading: $heading" }
}
$agents = Get-Content -Raw -LiteralPath 'AGENTS.md'
if (-not $agents.Contains('.agents/mob-ai/README.md')) {
  throw 'Mob AI entry point is not discoverable from AGENTS.md'
}
$task1Files = @(git show --format= --name-only HEAD~1 | Where-Object { $_ })
$task2Files = @(git show --format= --name-only HEAD | Where-Object { $_ })
$allowedTask1 = @('.agents/mob-ai/pilots/2026-07-31-bootstrap.md')
$allowedTask2 = @('AGENTS.md', '.agents/mob-ai/README.md', '.agents/mob-ai/task-card-template.md')
$badTask1 = @($task1Files | Where-Object { $_ -notin $allowedTask1 })
$badTask2 = @($task2Files | Where-Object { $_ -notin $allowedTask2 })
if ($badTask1.Count -gt 0) { throw "Task 1 scope violation: $($badTask1 -join ', ')" }
if ($badTask2.Count -gt 0) { throw "Task 2 scope violation: $($badTask2 -join ', ')" }
git diff --check HEAD~2..HEAD
if ($LASTEXITCODE -ne 0) { throw 'Whitespace verification failed' }
Write-Output 'Independent Mob AI QA: PASS'
```

Expected: `Independent Mob AI QA: PASS`. If any assertion fails, stop and return the finding to the Task 2 implementer; do not mark the pilot approved.

- [ ] **Step 2: Lägg till den permanenta operativa ingången i modellen**

After the QA step passes, use `apply_patch` to insert this section in `docs/mob-ai-operating-model.md` immediately before `## Arbetsflöde`:

```markdown
## Operativ ingång

Repoagenter börjar i `.agents/mob-ai/README.md` och skapar ett konkret kort
från `.agents/mob-ai/task-card-template.md`. Genomförda piloter sparas i
`.agents/mob-ai/pilots/`. Dokumenten under `docs/` är fortsatt styrande om
en lokal instruktion skulle vara oklar.

```

- [ ] **Step 3: Stäng pilotjournalen med verifieringsbevis och lärdomar**

Use `apply_patch` to change:

```text
Status: Redo för implementering
```

to:

```text
Status: Godkänd
```

Then append this exact section to `.agents/mob-ai/pilots/2026-07-31-bootstrap.md`:

```markdown
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
```

- [ ] **Step 4: Verifiera den stängda piloten**

Run:

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
$allowed = @(
  '.agents/mob-ai/pilots/2026-07-31-bootstrap.md',
  'docs/mob-ai-operating-model.md'
)
$changed = @(git diff --name-only)
$unexpected = @($changed | Where-Object { $_ -notin $allowed })
if ($unexpected.Count -gt 0) { throw "Unexpected closure files: $($unexpected -join ', ')" }
Write-Output 'Mob AI pilot closure: PASS'
```

Expected: `Mob AI pilot closure: PASS`.

Run:

```powershell
git diff --check
git status --short
```

Expected: no output from `git diff --check`; status contains only the two closure files plus the pre-existing untracked `.codex-audit/` when execution happens in the current workspace.

- [ ] **Step 5: Committa pilotens QA-domslut**

```powershell
git add -- .agents/mob-ai/pilots/2026-07-31-bootstrap.md docs/mob-ai-operating-model.md
git commit -m "docs: complete first mob ai pilot"
```

- [ ] **Step 6: Gör slutlig releaseöverlämning utan push**

Run:

```powershell
git status --short --branch
git log -3 --oneline
```

Expected: current branch is ahead of its remote by the Mob AI documentation and pilot commits; no tracked file is modified; `.codex-audit/` may remain untracked. Report that push and deploy were intentionally excluded by the pilotkort.

---

## Plan Self-Review

- **Spec coverage:** Task 1 creates the explicit task contract; Task 2 creates the reusable operational entry point; Task 3 separates QA from implementation, records evidence, closes the pilot, and links the runtime artifacts back to the approved model.
- **Boundary coverage:** Every write path is named, product/runtime paths are excluded, and each task checks its own changed-file set.
- **Interface consistency:** The same ten mandatory task-card headings are used in the pilot card, template, Task 2 verification, and Task 3 QA.
- **Testing:** The plan uses a fail-before/create/pass cycle for both new operational artifacts and ends with independent commit-scope verification.
- **Placeholders:** No implementation step depends on an unspecified file, command, role, field, or expected result. The reusable template contains instructional copy by design; completed pilot data is concrete.
