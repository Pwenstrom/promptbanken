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

## Team-autonomi vs uppgifts-autonomi

Modellen har två olika axlar för självständighet. De ska inte blandas ihop.

**Axel 1 — mellan moduler: full självorganisering.** Varje modul-team väljer
själv sitt arbetssätt, sin takt och sin interna rollsättning. Det enda som
är låst är gränssnittet mot andra moduler. Ska en modul ändra sitt
gränssnitt måste den antingen bygga en adapter (nya beteendet bakom det
gamla kontraktet) eller eskalera till samordning mellan de berörda teamen —
aldrig bryta kontraktet ensidigt. Detta är målet, inte ett undantag: gröna
moduler ska kunna drivas som oberoende team så länge
`Gränssnittsartefakt`-fältet i respektive uppdragskort hålls stabilt.

**Axel 2 — inuti en enskild uppgift: ingen fri rekrytering.** En modulagent
som mitt i en uppgift kallar in fler agenter för att utöka sin egen räckvidd
är inte samma sak som två team som jobbar oberoende av varandra — det är en
enskild agent som expanderar sitt uppdrag utan att uppdragskortet
uppdaterats. Stötte modulagenten på oväntad komplexitet (som i piloten
2026-08-01) är den enda tillåtna reaktionen att stanna och rapportera
tillbaka till mob-ledaren, aldrig att själv organisera om. Ett uppdragskort
får i förväg godkänna en snäv, läsande hjälpagent ("modulagenten får spawna
EN read-only undersökningsagent om den stöter på oklarhet, men den agenten
får aldrig skriva kod och måste redovisas i slutrapporten") — men skrivande
hjälp eller en ny granskningsroll kommer alltid från mob-ledaren via ett
nytt eller uppdaterat kort, aldrig genom att agenten själv rekryterar.

**Om samtidighet.** Källkonceptet (mob programming, Zuill/Justice) bygger på
att hela mobben jobbar på samma sak, samtidigt, i samma rum. Denna modell
gör det inte — agenter körs isolerat, parallellt eller i sekvens, och möts
bara vid en granskningsgrind efteråt. Det är en medveten anpassning till hur
agentverktyg faktiskt fungerar, inte en bristfällig kopia av samtidig
mobbing. Kalla den vid namn: **parallell isolerad implementation +
konvergent granskning.**

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

**Mobstorlek styrs av en regel, inte av mob-ledarens fria omdöme** — det var
exakt mob-ledarens ofullständiga förhandskoll som orsakade den första
blockerade piloten 2026-08-01, inte modulagenten eller QA-agenten.

| Modulmognad | Uppskattad diff | Minsta mob |
|---|---|---|
| Grön | Liten (enstaka fil/funktion) | Modulagent + QA-agent |
| Grön | Större (flera filer/ny funktion) | + Kontraktsdomare om ett kontrakt berörs |
| Gul | Alla storlekar | Modulagent + QA-agent + samordning med andra berörda team |
| Röd | Endast avgränsnings-/extraktionsarbete | Modulagent + QA-agent, aldrig vanligt feature-arbete |

Mob-ledaren avviker från tabellen bara med en uttrycklig, skriven motivering
i uppdragskortet (som undantaget för röd-modul-piloten 2026-08-01).

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

**Uppdragskortsmallen utvecklas via lärdomar, inte via rollrotation.**
Källkonceptets driver/navigator-rotation sprider kunskap genom att ständigt
byta vem som håller pennan. Det är meningslöst för agenter — ingen agent
"tröttnar" eller behöver omväxling. Motsvarigheten här: varje pilots
Lärdomar-avsnitt är input till nästa version av
`.agents/mob-ai/task-card-template.md`. Hittar en pilot ett hål i mallen
(som avsaknaden av "sök hela filen, inte bara det ankrade mönstret" i
piloten 2026-08-01) ska mallen uppdateras innan nästa uppgift av samma typ,
inte bara noteras i journalen.

## Operativ ingång

Repoagenter börjar i `.agents/mob-ai/README.md` och skapar ett konkret kort
från `.agents/mob-ai/task-card-template.md`. Genomförda piloter sparas i
`.agents/mob-ai/pilots/`. Dokumenten under `docs/` är fortsatt styrande om
en lokal instruktion skulle vara oklar.

## Arbetsflöde

1. **Triage:** Mob-ledaren kopplar uppgiften till modulkartan och bedömer
   mognadsnivån.
2. **Avgränsning:** Uppdragskortet låser skrivyta, kontrakt och
   acceptanskriterier.
3. **Implementering:** Modulagenten gör minsta sammanhängande ändring. För
   gula och röda moduler: om uppgiften har flera steg ska modulagenten
   rapportera tillbaka till mob-ledaren efter första steget innan den
   fortsätter — en billig motsvarighet till källkonceptets kontinuerliga
   styrning ("idén måste gå genom någon annans händer"), utan att göra hela
   uppgiften synkron. Gröna moduler kör i ett svep.
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

Dokumentationsbootstrapen för Mob AI-arbetssättet är en repetition av
agentdriften och inte denna produktmodulpilot. Den första skarpa gröna
modulpiloten återstår och ska namnge en exakt modul från modulkartan.

Först därefter bör modellen användas för gula moduler eller för arbetet med
att stycka katalog-UI:t.

## Retro-rytm

Källkonceptet har täta, korta retros som vana, inte en engångsutvärdering.
Motsvarigheten här:

- Varje pilotjournal avslutas med ett `## Lärdomar`-avsnitt — obligatoriskt,
  inte valfritt.
- Var femte pilot läser mob-ledaren igenom de ackumulerade lärdomarna från
  alla piloter sedan senaste genomgången och uppdaterar detta dokument samt
  `.agents/mob-ai/task-card-template.md` därefter.
- En pilot som inte gav någon lärdom värd att skriva in är i sig en
  observation värd att notera (mallen fungerade som den skulle).
