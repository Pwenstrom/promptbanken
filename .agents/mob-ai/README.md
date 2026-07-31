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
