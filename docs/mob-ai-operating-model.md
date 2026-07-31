# Mob AI: operativ modell för Promptbanken

Datum: 2026-07-31

## Beslut

Promptbanken använder Mob AI först som ett internt arbetssätt för utveckling,
innehåll, kvalitetssäkring och release. Det är inte en publik produktfunktion
i denna fas.

Modellen består av flera specialiserade agentroller runt samma uppgift. En
agent implementerar inom en definierad modul, en annan granskar resultatet,
och kontrakts- eller releaseagenten avgör om ändringen får gå vidare. Den
mänskliga produktägaren behåller prioritering, undantag och releasebeslut.

## Grundprinciper

1. **Uppgiften äger en modul.** Varje uppgift ska ha en primär modul och ett
   namngivet kontrakt.
2. **Skrivytan är explicit.** Agenten får bara ändra filer som står i
   uppdragskortet.
3. **Gränssnitt går före implementation.** Beteende utanför kontraktet får
   inte ändras som en bieffekt.
4. **Implementering och domslut separeras.** Agenten som gör ändringen får
   inte ensam godkänna en kontrakts- eller releasegrind.
5. **Parallellitet följer mognad.** Gröna moduler kan köras parallellt. Gula
   moduler kräver samordning. Röda moduler får bara ta emot avgränsnings- och
   extraktionsarbete.
6. **Bevis före status.** "Klart" kräver verifieringsresultat, inte bara en
   kodändring.

## Roller

### Mänsklig produktägare

- Prioriterar problem och godkänner större produktbeslut.
- Avgör om en känd risk är accepterad.
- Beslutar om publicering när releasegrinden är grön.

### Mob-ledare

- Översätter önskemålet till ett uppdragskort.
- Väljer primär modul, skrivyta, kontrakt och verifiering.
- Stoppar eller delar upp uppgifter som korsar för många moduler.
- Sammanställer resultatet utan att dölja osäkerhet eller restpunkter.

### Modulagent

- Implementerar endast inom tilldelad skrivyta.
- Läser beroenden vid behov men ändrar dem inte utan ett nytt uppdragskort.
- Levererar ändrade filer, verifieringsbevis och kända risker.

### QA- och granskningsagent

- Testar användarflödet och söker regressioner i berörd yta.
- Kontrollerar acceptanskriterier och dokumenterar manuell verifiering när
  automatiska tester saknas.
- Ändrar inte implementationen i samma granskningspass.

### Kontraktsdomare

- Kör relevanta maskinläsbara kontrakt och skyddsregler.
- Bedömer ändringar i kollisionspunkter.
- Underkänner leveransen om kontraktet är oklart, även om happy path fungerar.

### Releaseagent

- Kontrollerar git-läge, bygge, deploystatus och liveflöden.
- Publicerar eller pushar endast när uppdraget uttryckligen omfattar detta.
- Redovisar blockerande och icke-blockerande risker separat.

En liten, grön uppgift behöver inte aktivera alla roller. Minsta säkra mob är
en modulagent och en oberoende verifierare. Kontraktsdomare krävs när ett
externt kontrakt eller en kollisionspunkt påverkas.

## Uppdragskort

Varje agentuppgift ska börja med följande information:

```text
Mål:
Primär modul:
Tillåten skrivyta:
Läsberoenden:
Förbjudna/känsliga ytor:
Gränssnittsartefakt:
Acceptanskriterier:
Obligatorisk verifiering:
Releaseomfattning:
```

Om skrivytan inte kan anges tydligt är modulen inte redo för självständig
agentutveckling.

## Arbetsflöde

1. **Triage:** Mob-ledaren kopplar uppgiften till modulkartan och bedömer
   mognadsnivån.
2. **Avgränsning:** Uppdragskortet låser skrivyta, kontrakt och
   acceptanskriterier.
3. **Implementering:** Modulagenten gör minsta sammanhängande ändring.
4. **Verifiering:** Agenten kör modulens tester och redovisar faktisk output.
5. **Oberoende granskning:** QA-agenten testar beteendet; kontraktsdomaren
   kopplas in när gränssnitt eller kollisionspunkter berörs.
6. **Integrering:** Mob-ledaren kontrollerar att inga orelaterade ändringar
   följt med och sammanställer restpunkter.
7. **Release:** Releaseagenten kör releasegrinden och den mänskliga
   produktägaren fattar publiceringsbeslut vid betydande risk.

## Regler för parallellt arbete

- Två gröna moduler får arbeta parallellt om deras skrivytor inte överlappar.
- En gul modul får bara ha en aktiv implementerande agent per kollisionspunkt.
- En röd modul får inte ta emot vanligt feature-arbete. Första uppgiften ska
  vara att extrahera en avgränsad del och skapa dess kontrakt.
- `mcp_server.py`, `style.css` och duplicerad risk-/routinglogik låser den
  berörda kollisionspunkten tills granskningen är klar.
- En agent får aldrig lösa en konflikt genom att skriva utanför sin
  tilldelade yta utan att uppdragskortet först ändras.

## Definition av klart

En uppgift är klar först när:

- acceptanskriterierna är uppfyllda;
- endast godkänd skrivyta har ändrats;
- obligatoriska tester är gröna;
- manuella kontroller är dokumenterade när automatiska tester saknas;
- kontraktsdomaren har godkänt berörda kontrakt och kollisionspunkter;
- kända risker är klassade som blockerande eller icke-blockerande;
- releaseomfattningen är utförd, eller uttryckligen lämnad till nästa steg.

## Första pilot

Modellen provas på nästa lilla ändring i en grön modul, helst innehåll,
landing eller lokal chatt. Piloten ska använda ett komplett uppdragskort,
en implementerande agent och en separat verifiering. Efter piloten bedöms:

- om skrivgränsen var begriplig;
- om granskningen hittade något implementeraren missade;
- om överlämningen innehöll tillräckliga bevis;
- om arbetssättet minskade eller ökade ledtiden på ett motiverat sätt.

Först därefter bör modellen användas för gula moduler eller för arbetet med
att stycka katalog-UI:t.
