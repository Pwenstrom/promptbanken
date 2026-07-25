# Teknisk spec: parametriserad rendering för prompts och paket

## Syfte

Den här specen beskriver hur Promptbanken ska gå från enkel listfiltrering till
**parametriserad innehållsrendering**.

Målet är att användarens val av:

- `kontext`
- `roll`
- `målgrupp`
- `ton`

inte bara påverkar **vilka kort som syns**, utan också **hur prompttext och
paketinnehåll byggs upp**.

Det innebär att dagens fria `[]`-fält ska ersättas eller kompletteras med en
styrd modell där innehållet kan renderas konsekvent i:

- vanliga promptkort i `promptbanken.html`
- öppna katalogprompts från Supabase
- paket och arbetssätt i Supabase
- MCP-ytan, så att webben och MCP inte divergerar

## Rekommenderad modell

### 1. Kanonisk platshållarsyntax

Rekommendation: intern lagring ska använda **namngivna platshållare**, inte fria
anonyma `[]`.

Kanonisk syntax:

```text
{{kontext}}
{{roll}}
{{malgrupp}}
{{ton}}
{{avsandare}}
{{mottagare}}
{{syfte}}
```

Skäl:

- `[]` går inte att tolka säkert när flera fält finns i samma prompt
- namngivna variabler gör det möjligt att validera, förifylla och dokumentera
- frontend, Supabase och MCP kan dela samma renderlogik

Bakåtkompatibilitet:

- befintliga promptar med `[]` får stöd i en övergångsfas
- första migreringssteget mappar enkla `[]` till definierad parameterordning per
  prompt
- nya eller uppdaterade prompts ska skrivas med `{{...}}`

### 2. Fyra styrande basparametrar

Första versionen av den parametriserade modellen ska alltid stödja:

- `kontext`
- `roll`
- `malgrupp`
- `ton`

Definitioner:

- `kontext`: organisatorisk miljö, till exempel `kommun`, `skola`, `företag`,
  `förening`, `privat`
- `roll`: den som använder prompten, till exempel `handläggare`, `chef`,
  `kommunikatör`, `pedagog`
- `malgrupp`: den som texten riktas till, till exempel `invånare`,
  `vårdnadshavare`, `medarbetare`, `allmänhet`
- `ton`: önskad uttrycksform, till exempel `neutral`, `tydlig och vänlig`,
  `formell`, `rak`, `varm`

Dessa ska finnas som första klassens parametrar i modellen, inte som fria
frågesvar i ett separat formulär.

### 3. Promptspec per prompt

Varje prompt ska kunna bära en egen parameterdefinition.

Föreslagen struktur i frontendvänlig JSON:

```json
{
  "id": "mejl",
  "title": "Svar på medborgarmejl",
  "description": "Skriv ett vänligt och sakligt svar.",
  "file": "prompts/mejl.txt",
  "parameter_schema": {
    "version": 1,
    "fields": [
      {
        "key": "kontext",
        "label": "Kontext",
        "type": "enum",
        "required": true,
        "source": "global"
      },
      {
        "key": "roll",
        "label": "Din roll",
        "type": "enum",
        "required": true,
        "source": "global"
      },
      {
        "key": "malgrupp",
        "label": "Målgrupp",
        "type": "enum",
        "required": true,
        "source": "global"
      },
      {
        "key": "ton",
        "label": "Ton",
        "type": "enum",
        "required": true,
        "source": "global"
      },
      {
        "key": "syfte",
        "label": "Syfte",
        "type": "text",
        "required": false,
        "source": "local"
      }
    ]
  }
}
```

Det viktiga här är:

- varje prompt vet vilka parametrar den använder
- vissa parametrar hämtas från globala val
- vissa parametrar kan vara lokala för just den prompten

### 4. Bindings och förvalda värden

En prompt behöver inte bara veta **vilka fält som finns**, utan också hur
förvalen sätts.

Föreslagen modell:

```json
{
  "default_bindings": {
    "kontext": "kommun",
    "roll": "handläggare",
    "malgrupp": "invånare",
    "ton": "tydlig och vänlig"
  },
  "binding_overrides": [
    {
      "when": { "kontext": "skola" },
      "set": { "malgrupp": "vårdnadshavare" }
    },
    {
      "when": { "roll": "chef" },
      "set": { "ton": "rak och handlingsorienterad" }
    }
  ]
}
```

Regel:

1. börja med globala val
2. applicera promptens standardvärden där användaren ännu inte valt något
3. applicera overrides i prioritetsordning
4. rendera slutligt innehåll

Detta gör modellen flexibel utan att kräva specialkod per prompt.

## Renderkedja

### 1. Global state

Frontend ska bära ett gemensamt renderstate för sidan:

```js
{
  kontext: "kommun",
  roll: "handläggare",
  malgrupp: "invånare",
  ton: "tydlig och vänlig"
}
```

Detta state ska vara den enda sanningskällan för globala val.

Det ska kunna:

- persisteras i `localStorage`
- användas för filtrering
- användas för prompt- och paketrendering
- senare speglas i URL om det behövs

### 2. Prompt rendering

När en prompt visas eller kopieras ska följande flöde användas:

1. hämta rå prompttext
2. hämta promptens `parameter_schema`
3. bygg slutliga bindings från global state + promptspecifika defaults
4. ersätt `{{...}}`-variabler
5. visa renderad text i kort, detaljpanel och kopierad/exporterad variant

Föreslagen rendering:

```js
renderPromptTemplate(rawTemplate, bindings)
```

Exempel:

```text
Skriv ett svar i {{ton}} ton till {{malgrupp}}.
Utgå från att avsändaren är {{roll}} i {{kontext}}.
```

renderas till:

```text
Skriv ett svar i tydlig och vänlig ton till invånare.
Utgå från att avsändaren är handläggare i kommun.
```

### 3. Paket rendering

Paket och arbetssätt ska använda samma modell, men på två nivåer:

- paketnivå: introtext, målbild, rekommenderad användning
- itemnivå: varje prompt eller steg i paketet

Föreslagen regel:

- paketet ärver global state
- paketet kan ha egna defaults och overrides
- varje item kan i sin tur ha egna overrides ovanpå paketet

Prioritet:

1. global state
2. paketdefaults
3. paketoverrides
4. itemdefaults
5. itemoverrides

Detta gör att ett paket kan säga:

- standardton är `lugn och trygg`
- men ett visst steg ska vara `mer formellt`

utan att duplicera hela paketet.

## Datamodell i lagring

### Alternativ A: metadata i `prompts.json` och `skills.json`

Bra för statiska prompts och första frontendversionen.

Fördelar:

- snabbt att införa
- enkelt att versionshantera i git
- passar dagens statiska webb

Nackdelar:

- risk för duplicering mellan webb och MCP
- svårare att redigera i admin senare

### Alternativ B: metadata i Supabase

Bra för öppna katalogen, paket och framtida adminflöde.

Rekommenderad struktur på sikt:

- `parameter_schema jsonb`
- `default_bindings jsonb`
- `binding_overrides jsonb`
- eventuell `render_hints jsonb`

Det bör finnas både för:

- promptvarianter
- paketvarianter
- eventuellt paketitems om itemnivå behöver avvika

### Rekommendation

Använd en hybridmodell:

- **statiska prompts**: metadata i `prompts.json` i första versionen
- **öppna katalogen och paket**: metadata i Supabase
- **MCP**: läser samma metadata eller exporterad gemensam modell

Det viktiga är att samma begrepp används överallt:

- samma parameternamn
- samma tonvärden
- samma renderregler

## Tonmodell

`ton` ska inte vara ett löst textfält i första hand, utan ett styrt urval.

Föreslagna startvärden:

- `neutral`
- `tydlig och vänlig`
- `formell`
- `rak och handlingsorienterad`
- `varm och trygg`
- `pedagogisk`

Varje prompt behöver inte stödja alla toner.

Därför ska `parameter_schema` kunna ange:

- vilka tonvärden som är tillåtna
- vilket som är standard
- om tonen också påverkar hjälprader eller exempeltext

Exempel:

```json
{
  "key": "ton",
  "type": "enum",
  "options": ["neutral", "tydlig och vänlig", "formell"],
  "default": "tydlig och vänlig"
}
```

## Övergång från dagens `replaceInputMarkers`

I dag ersätts text med en enklare modell i `script.js`.

Målbilden är att ersätta den med två tydliga lager:

1. `resolvePromptBindings(state, schema, defaults, overrides)`
2. `renderPromptTemplate(template, bindings)`

Bakåtkompatibilitet under övergången:

- gamla prompts med `[]` kan fortsätta fungera via en adapter
- nya prompts ska inte använda fler anonyma `[]`

Rekommenderad adapter:

- om en prompt bara har ett enda anonymt `[]`, mappa det till `{{input}}`
- om en prompt har flera `[]`, måste den få explicit parameterdefinition innan
  den räknas som fullt migrerad

## UX-regler

- användaren ska förstå varför texten ändras när valen ändras
- om en prompt inte använder en parameter ska det inte kännas som ett fel
- om en parameter saknar värde ska användaren få ett begripligt defaultläge
- användaren ska kunna se och kopiera den renderade versionen, inte råmallen
- samma val ska ge samma resultat i webb och MCP

## Fasindelning

### Fas 1

- global state för `kontext`, `roll`, `malgrupp`, `ton`
- metadata för statiska prompts
- enkel rendering av `{{...}}`
- adapter för befintliga `[]`

### Fas 2

- samma modell för öppna katalogprompts
- samma modell för paket och arbetssätt
- exaktare fallback- och variantmärkning

### Fas 3

- adminstöd för att redigera parameterdefinitioner
- MCP läser samma modell direkt
- eventuell URL/deep-linking för delade vyer

## Beslut

Rekommenderad teknisk riktning är:

1. gå över till namngivna platshållare `{{...}}`
2. bygg ett gemensamt globalt renderstate för `kontext`, `roll`, `malgrupp`,
   `ton`
3. låt varje prompt och paket bära egen `parameter_schema`
4. använd samma logiska modell i frontend, Supabase och MCP
5. behåll adapterstöd för `[]` bara som övergång, inte som slutmodell

Detta är den minsta robusta modellen som gör att användarens val faktiskt kan
ändra innehållet, inte bara filtrera listan.
