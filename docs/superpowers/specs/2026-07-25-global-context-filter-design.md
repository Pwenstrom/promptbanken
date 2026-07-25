# Globalt kontextfilter för hela promptbanken

## Mål

Gör kontextfiltreringen till en tydlig, global del av `promptbanken.html` i stället
för en separat katalogfunktion längst ned på sidan. Användaren ska uppleva att hen
filtrerar **hela katalogen**, inte byter till ett annat system.

## Beslut

### 1. Ett aktivt profilval i taget

Hela sidan ska använda exakt en aktiv kontext åt gången:

- `Alla` eller `Generell` som standardläge
- `Kommun`
- `Skola`
- `Företag`
- `Förening`
- `Privat`

Flera samtidiga profilval används inte i huvudsidans UX. Skälet är att ett enda
aktivt val är tydligare, lättare att förklara och faktiskt känns som filtrering.

### 2. Filtret gäller hela sidan

Kontextvalet ska påverka:

- promptlistor på sidan
- öppna katalogprompts från Supabase
- paket och arbetssätt från Supabase

Användaren ska inte behöva förstå skillnaden mellan statiskt innehåll och
databasladdat innehåll för att använda filtret.

### 2.1 Målbild för parametrisering av innehåll

Den långsiktiga målbilden är att filter och val inte bara styr **vilka kort som
visas**, utan också **hur själva innehållet i prompts och paket renderas**.

Följande variabler ska kunna påverka innehållet:

- `kontext`
- `roll`
- `målgrupp`
- `ton`

Det betyder att `[]`-fält i promptar och paket på sikt inte ska vara generiska
tomma hål, utan fyllas eller bytas ut utifrån användarens val.

Exempel:

- `Kommun + handläggare + invånare + tydlig och vänlig`
- `Skola + rektor + vårdnadshavare + lugn och förtroendeskapande`
- `Företag + chef + medarbetare + rak och handlingsorienterad`

I den modellen ska samma grundprompt kunna få olika standardvärden,
hjälptexter eller textblock beroende på vald kombination.

### 3. Filtret flyttas högt upp

Kontextfiltret ska flyttas från den nedre katalogsektionen till en tydlig plats
högre upp i sidan, nära den huvudsakliga katalogintroduktionen och innan större
resultatlistor.

Rubrik/etikett ska vara begriplig, till exempel:

- `Anpassa innehåll efter din kontext`

Det ska också finnas en liten statusrad som visar aktuell vy, till exempel:

- `Visar innehåll för: Företag`

### 4. En sammanhållen katalogvy

Sidan ska upplevas som en enda katalog med sektioner, inte två separata system.

Rekommenderad informationsstruktur:

1. sidhuvud / introduktion
2. globalt kontextfilter
3. prompts
4. paket och arbetssätt

Det är okej att prompts och paket fortsatt renderas i olika sektioner, så länge de
lyder under samma filterlager.

### 5. Fallback från generell ska finnas kvar, men bli synlig

Datamodellen ska fortsatt få falla tillbaka till `generell` när vald kontext saknar
egen variant. Annars blir katalogen onödigt tom.

Men fallback får inte vara osynlig för användaren. Om en post visas via generell
variant i en kontextvy ska det framgå diskret, till exempel:

- `Generell version`
- `Saknar egen företagsvariant`

Detta behövs för att filtret ska kännas ärligt. Annars ser det ut som att alla
profiler visar samma sak utan förklaring.

## Konsekvenser för implementation

### Statiska prompts

De befintliga statiska promptarna i `prompts.json` behöver en enkel
kontextklassning så att även de kan filtreras av det globala profilvalet.

Miniminivå:

- varje statisk prompt får minst `generell`
- vissa prompts får dessutom `kommun`, `skola`, `företag`, `förening` eller
  `privat` enligt konservativ klassning

På sikt behöver de också kunna bära metadata om vilka parametrar som styr
deras `[]`-fält, minst:

- vilken `roll` prompten riktar sig till
- vilken `målgrupp` svaret riktar sig till
- vilken `ton` som rekommenderas eller förvaljs

Första versionen behöver inte bygga hela parametermotorn, men specen ska styra
mot den modellen.

### Dynamiska katalogposter

Supabase-katalogen använder redan `context_key` och fallbacklogik. Den behöver
anpassas från fler-vals-UI till ett aktivt val i taget i frontend.

Nästa steg efter detta är att samma katalogposter också ska kunna beskriva
vilka parametrar som används för:

- förvalda `[]`-värden
- tonalitet i prompttext
- skillnader mellan roller och målgrupper
- skillnader mellan kortversion och mer avancerad version av samma innehåll

Det gäller både enskilda prompts och paket/arbetssätt.

### Renderregel för `[]`-fält

Målbilden är:

1. användaren väljer `kontext`
2. användaren väljer `roll`
3. användaren väljer `målgrupp`
4. användaren väljer `ton`
5. prompten eller paketet renderas om med dessa värden

I första hand ska detta fylla eller byta ut `[]`-fält i texten.

I andra hand får modellen också styra:

- förslag på rubriker
- exempel på formuleringar
- rekommenderade nästa steg
- vilka delar av en prompt som ska betonas eller tonas ned

Detta ska gälla konsekvent för både promptkort och paketdetaljer, så att
användaren upplever att valen faktiskt anpassar innehållet och inte bara
filtrerar listan.

### URL och localStorage

Det aktiva profilvalet ska fortsatt persisteras lokalt, men modellen blir ett
enskilt värde i stället för en lista.

Det får gärna vara möjligt senare att spegla valet i URL eller deep-linking, men
det är inte krav i första versionen.

## UX-regler

- Standardläget ska aldrig kännas tomt.
- Profilväxling ska ge synlig effekt i listan.
- Om ingen post matchar exakt vald profil ska användaren fortfarande kunna se
  generell fallback, men med tydlig märkning.
- Om en sektion saknar innehåll helt ska den visa en begriplig tomstatus, inte en
  blank yta.

## Rekommenderad första version

Första versionen bör göra följande och inget mer:

1. flytta filtret till toppen
2. byt från checkboxar till ett aktivt enkelval
3. låt valet styra hela sidan
4. lägg till enkel fallback-märkning
5. behåll prompts och paket som separata sektioner i samma flöde

Detta är minsta förändring som ger tydlig UX-förbättring utan att kräva en total
ombyggnad av sidan.
