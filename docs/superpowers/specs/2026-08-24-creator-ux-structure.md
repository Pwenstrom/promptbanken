# Creator — sidstruktur och kontroller

Datum: 2026-08-24
Status: utkast för genomförande, inte godkänd design

Det här dokumentet ritar upp Creator-ytan vy för vy: vilka sektioner varje
sida har, exakt vilka knappar som finns, vad de heter, när de syns, och
varifrån data kommer. Det är avsett att kunna lämnas till ett bygge utan
ytterligare tolkning.

Flödet som ligger till grund är Peters, formulerat 2026-08-24. Det som
skiljer detta dokument från den beskrivningen är att varje punkt här är
avstämd mot vad som faktiskt finns i koden i dag.

## Vad som redan finns

| Del | Läge |
| --- | --- |
| Mina prompts — skapa, redigera, skicka in, dra tillbaka | Byggt (`creator-content.html`) |
| Mina paket — utkast, lägg till/ta bort, skicka in, dra tillbaka | Byggt (`creator-packages.html`) |
| Profil — redigera, publicera, avpublicera | Byggt (`creator-profile.html`) |
| Redaktionell granskning i admin, med AI-förgranskning | Byggt (delprojekt 4) |
| Publik creator-sida med publicerat innehåll | Byggt |
| Översikt | **Finns inte** |
| Delningar — länkar, giltighetstid, statistik | **Finns inte** |
| JSON-import och validering | **Finns inte** |
| Snapshot av inskickat innehåll | **Finns inte** |
| AI-assisterat skapande i appen | **Finns inte** |
| Creator Skill för nedladdning | **Finns inte** |
| Workflow som pakettyp för creators | **Delvis** — `catalog_packages.package_type` stödjer `workflow`, men `creator_package_drafts` har ingen typ |

Sju av tolv delar är nya. Det är värt att veta innan sekvensen bestäms.

## Navigation

Creator-ytan får en egen vänsternavigation, samma mönster som
`admin.html` använder i dag:

```
Översikt          creator.html          byggd
Mina prompts      creator-content.html  byggd
Mina paket        creator-packages.html byggd
Profil            creator-profile.html  byggd
Delningar         creator-shares.html   läggs till när vyn finns
Granskning        creator-review.html   läggs till när vyn finns
```

De två sista raderna sätts in i navigationen först när sidorna existerar.
En navigationsrad som leder till 404 är sämre än en kort navigation.

`Inställningar` ligger **inte** här utan under användarmenyn uppe till
höger, tillsammans med e-postadress och Logga ut. Motivet: inställningar
hör till kontot, inte till skapandet, och en sjunde rad i navigationen gör
de sex första svårare att se.

Obs att `creator.html` i dag är profilsidan. Den flyttas till
`creator-profile.html` och adressen återanvänds för Översikt. Gamla länkar
till `creator.html` fortsätter alltså fungera men landar på Översikt, vilket
är rätt startpunkt.

---

## 1. Översikt — `creator.html`

Syftet är att svara på tre frågor inom en skärmhöjd: vad väntar på mig, vad
höll jag på med, vad kan jag börja på.

### Sektion: Kräver åtgärd

Ligger överst och visas bara när den har innehåll. Ett kort per post.

| Situation | Kortets text | Knapp |
| --- | --- | --- |
| Prompt återsänd med motivering | "Skickades tillbaka: *motiveringen*" | **Åtgärda** → Mina prompts, kortet öppet i redigeringsläge |
| Paket återsänt | Samma | **Åtgärda** → Mina paket |
| Delning löper ut inom 7 dagar | "Delningen *namn* slutar fungera *datum*" | **Förläng** |
| Importerat utkast med öppna fynd | "*n* fynd att gå igenom" | **Öppna granskning** |

Tomt läge: "Inget väntar på dig just nu." Ingen knapp.

### Sektion: Fortsätt arbeta

De fem senast ändrade posterna, oavsett typ, sorterade på `updated_at`.
Varje rad: titel, typ (Prompt/Paket), statusetikett, relativ tid. Hela raden
är en länk till respektive vy.

Tomt läge: "Du har inte börjat på något än." Knapp: **Skapa din första
prompt**.

### Sektion: Skapa nytt

Tre kort sida vid sida:

- **Ny prompt** → Mina prompts med skapa-formuläret öppet
- **Nytt paket** → Mina paket med skapa-formuläret öppet
- **Importera JSON** → Granskning, filväljaren öppen

### Sektion: I korthet

Fyra tal på en rad, utan diagram: publicerade prompts, publicerade paket,
aktiva delningar, visningar senaste 30 dagarna. Varje tal länkar vidare.

Visas bara när creatorn har minst en publicerad post. Innan dess är
siffrorna bara nollor som ser ut som ett misslyckande.

### Data

Ny RPC `get_my_creator_overview()` som returnerar allt ovan i ett anrop.
Fyra separata anrop för fyra sektioner ger en sida som byggs i ryck.

---

## 2. Mina prompts — `creator-content.html`

Byggd. Det som beskrivs här är tilläggen.

### Sektion: Skapa ny prompt

Finns. Fält: Titel, Prompttext, Sammanfattning, Kategori. Knapp **Skapa
prompt**.

Tillägg: en flikrad överst i sektionen med två lägen.

- **Skriv själv** — dagens formulär.
- **Ta hjälp av AI** — ett fält ("Vad ska prompten göra?") och knappen
  **Föreslå utkast**. Svaret fyller i de fyra fälten, som förblir
  redigerbara. Inget sparas förrän creatorn trycker Skapa prompt.

AI-läget anropar en ny edge function `draft-creator-prompt`. Den får samma
säkerhetsgräns som `screen-creator-submission`: den skriver ingenting alls,
den returnerar bara text till klienten.

### Sektion: Mina prompts (lista)

Ett kort per prompt. Kortet visar titel, statusetikett, sammanfattning, och
motivering i rött när status är `draft` eller `archived` och `review_note`
finns.

Knappar per status:

| Status | Knappar |
| --- | --- |
| Utkast | **Redigera** · **Använd** · **Skicka in för granskning** (efter två kryssrutor) |
| Under granskning | **Dra tillbaka** |
| Publicerad | **Använd** · **Dela** |
| Arkiverad | **Redigera** (återgår till utkast) |

**Använd** är ny och öppnar prompten i en enkel körvy: prompttexten med
ifyllnadsfält, en kopieringsknapp, och ingenting som skickas någonstans.
Det är den privata användningen i Peters flöde.

**Dela** är ny och tar creatorn till Delningar med posten förvald.

### Samtycken

Tre kryssrutor vid inskick, inte två som i dag:

1. Jag godkänner att prompten publiceras i öppna Promptbanken *(krävs)*
2. Andra creators får återanvända den i sina paket *(frivillig)*
3. Innehållet är mitt eget eller jag har rätt att sprida det *(krävs för
   distribution via Open/MCP)*

Den tredje motsvarar `creator_rights_attested`, som redan finns i databasen
men saknar ruta i gränssnittet. Utan den kan innehållet aldrig nå Open/MCP,
oavsett hur granskningen går.

---

## 3. Mina paket — `creator-packages.html`

Byggd som samling. Det som saknas är typvalet och förhandsgranskningen.

### Sektion: Skapa nytt paket

Fält: Titel, Sammanfattning. **Nytt:** ett typval med två alternativ,
presenterat som två kort med förklaring, inte som en rullista:

- **Samling** — "Mallar som hör ihop. Användaren väljer själv vilken hen
  behöver."
- **Workflow** — "Steg som körs i ordning, från början till färdigt
  resultat."

Kräver en ny kolumn `creator_package_drafts.package_type` med samma
check-villkor som `catalog_packages` (`collection` / `workflow`).

### Sektion: Paketkort

Per utkast: titel, sammanfattning, typ, statusetikett, stegräknare
("4/8 prompts"), och listan över ingående prompts i ordning.

Knappar:

| Status | Knappar |
| --- | --- |
| Utkast | **Redigera** · **Lägg till prompt** · **Förhandsgranska** · **Skicka in för granskning** |
| Under granskning | **Dra tillbaka** |
| Publicerad | **Dela** |

Per rad i steglistan: **Upp** · **Ner** · **Ta bort**. Ordningen skrivs med
`reorder_package_draft_items`, som redan finns men aldrig anropas från
gränssnittet.

### Lägg till prompt

En panel med två källor:

- **Mina prompts** — egna, oavsett status.
- **Från Promptbanken** — publicerade katalogprompts med
  `creator_consent_reusable = true`. Rätten finns i datamodellen sedan
  delprojekt 3; bläddra-ytan gör det inte.

### Förhandsgranska

Modal som visar paketet som en användare skulle möta det: inledning, sedan
varje steg med titel, syfte och prompttext. Knapp **Stäng**. Ingenting
sparas.

---

## 4. Delningar — `creator-shares.html`

Helt ny vy, och den största nya delen i planen.

### Sektion: Skapa delning

| Fält | Kontroll | Standard |
| --- | --- | --- |
| Vad | Rullista över egna publicerade prompts och paket | — |
| Version | **Lås till nuvarande version** / **Följ senaste** | Följ senaste |
| Giltig | **7 dagar** · **30 dagar** · **Eget datum** · **Tills vidare** | 30 dagar |
| Namn | Fritext, syns bara för creatorn | Postens titel |

Knapp **Skapa delning**. Resultatet är en creator-brandad adress:

```
https://app.promptbanken.se/d/<token>
```

### Sektion: Aktiva delningar

Tabell: namn, vad, version, giltig till, visningar, kopieringar. Per rad:
**Kopiera länk** · **Förläng** · **Avsluta**.

Avslutade delningar ligger under en hopfällbar rubrik "Avslutade", så att
statistiken inte försvinner när länken slutar gälla.

### Den publika delningssidan — `/d/<token>`

Creatorns namn och profillänk, postens titel och sammanfattning,
prompttexten med ifyllnadsfält, kopieringsknapp. Ingen inloggning. Ingen
möjlighet att ändra något.

Utgången länk visar "Den här delningen har upphört" plus en länk till
creatorns profil — inte en 404.

### Statistik

Anonym och aggregerad: antal visningar, antal kopieringar, dygn för dygn.
Ingen IP, ingen besökaridentitet, ingen hänvisande sida. Det är samma
hållning som `library_usage_events` redan har, och det gör att
integritetspolicyn inte behöver skrivas om.

### Nya tabeller

`creator_shares` (id, owner_user_id, subject_type, subject_id, token,
pinned_version, expires_at, label, revoked_at, created_at) och
`creator_share_events` (share_id, event_type, occurred_at). Token genereras
med `gen_random_bytes`, inte löpnummer.

---

## 5. Granskning — `creator-review.html`

Ny vy. Namnet är creatorns eget kvalitetsarbete *före* inskick, inte
adminets granskning.

Fem steg, visade som en stegindikator där bara ett steg är öppet i taget.

### Steg 1 — Dra in filen

Släppyta: "Dra hit en Promptbanken-JSON, eller **välj fil**." Under den en
rad: "Filen skapas av Promptbanken Creator Skill. **Hämta skillen**."

### Steg 2 — Validera

Filen kontrolleras mot schemat. Resultat i tre nivåer, med radhänvisning:

- **Fel** — filen kan inte importeras. Knapp **Välj en annan fil**.
- **Varning** — importeras, men något saknas.
- **OK**.

Knapp **Importera som utkast**, aktiv först när inga fel finns.

**Importen skapar alltid ett nytt, redigerbart utkast.** Den publicerar
ingenting och skriver aldrig över befintligt innehåll. Det står som en fast
rad i vyn, inte bara i dokumentationen — det är den viktigaste garantin i
hela importen.

### Steg 3 — Kvalitetskontroll

Kör samma regelverk som adminets förgranskning, mot
`docs/creator-publiceringsregler.md`. Resultat: Grön / Gul / Röd med fynd
per kategori.

Per fynd: fyndets text, och knappen **Åtgärda** som öppnar rätt fält i
utkastet med fyndet synligt bredvid. Knapp **Kör om kontrollen** när
ändringar gjorts.

Ett rött omdöme blockerar inte inskick. Det är rådgivande här av samma skäl
som i adminvyn.

### Steg 4 — Snapshot

"Så här ser det ut när du skickar in." Hela paketet eller prompten som
adminet kommer att se det. Knapp **Skapa snapshot och skicka in**.

Snapshotet är kopian som granskas. Redigerar creatorn efteråt påverkas inte
det inskickade — det är hela poängen med steget, och det löser problemet
som `update_my_creator_prompt` i dag hanterar genom att helt enkelt vägra
redigering under granskning.

### Steg 5 — Inskickat

"Skickat för granskning *datum*. Du får besked här och på din översikt."
Knapp **Till mina prompts**.

---

## 6. Profil — `creator-profile.html`

Byggd, flyttas från `creator.html`. Sektionerna finns redan: publik adress
och status, formulär för namn, beskrivningar, organisation, länkar,
kompetensområden, samt publicera/avpublicera.

Tillägg: en **Förhandsgranska publik sida**-knapp som öppnar
`/creator/<slug>/` i ny flik, och nollägena för paket, prompts och
workshopkrediter som redan renderas på den publika sidan speglas här så att
creatorn ser vad besökaren ser.

---

## 7. Promptbanken Creator Skill

En nedladdningsbar skill som körs i creatorns egen AI-klient. Den ligger
under **Mina prompts → Ta hjälp av AI → Hämta skillen** och på Översikt.

Vad den gör:

1. Frågar vad creatorn vill bygga — prompt, paket eller workflow.
2. Söker i Promptbanken först, via den öppna MCP:n, och säger till om något
   liknande redan finns. Det är dublettkontroll innan arbetet gjorts i
   stället för efteråt.
3. Vägleder genom titel, syfte, innehåll, målgrupp, risknivå.
4. Skriver en submission-JSON enligt schemat.

Filen dras sedan in i Granskning. Skillen skickar ingenting själv och
behöver inga rättigheter mot Promptbanken.

---

## Genomgående regler

**Statusetiketter** är alltid samma fyra ord, med samma färger som
adminets granskningsvy: Utkast, Under granskning, Publicerad, Arkiverad.

**Tomma lägen** säger vad som saknas och har en knapp som skapar det.
Aldrig bara "Inga resultat".

**Fel** visas där handlingen gjordes, aldrig i en global rad överst.
Databasens felmeddelanden är redan på svenska och skrivna för en människa —
visa dem som de är i stället för att ersätta dem med "Något gick fel".

**Ingen `window.prompt`.** Adminvyn använder den i dag för slug och
motivering, och creator-ytan ska inte ärva det. Fält i sidan, inte
webbläsarens dialogruta.

**Destruktiva knappar** — Ta bort, Avsluta delning, Avpublicera — kräver ett
andra klick som bekräftar i knappen själv ("Ta bort" → "Säker?"), inte en
modal.

---

## Föreslagen ordning

1. **Översikt** — liten, och gör resten av navigationen begriplig.
2. **Samtyckesrutan för rättigheter** i Mina prompts — några rader, och
   utan den kan inget creator-innehåll nå Open/MCP oavsett vad som byggs.
3. **Paketens typval och förhandsgranskning** — bygger på det som finns.
4. **Delningar** — störst, men den funktion en creator faktiskt frågar
   efter först.
5. **Granskning med JSON-import och snapshot**.
6. **Creator Skill**.

AI-assisterat skapande i appen (steg i Mina prompts) kan vänta tills
skillen finns — de löser samma problem, och skillen löser det bättre
eftersom den har creatorns eget sammanhang.

## Öppna frågor

- **Snapshot mot dagens modell.** `submit_creator_prompt` skickar in raden
  som den är och `update_my_creator_prompt` vägrar redigering under
  granskning. Snapshot löser samma problem på ett bättre sätt, men kräver
  en kopia av innehållet vid inskick. Ska den ersätta dagens spärr eller
  ligga vid sidan av?
- **Delning av opublicerat.** Flödet säger "dela privat" om paket. Får en
  creator dela ett utkast som aldrig granskats? Om ja, måste delningssidan
  vara tydlig med att innehållet inte är granskat av Promptbanken.
- **Workflow för creators** kräver mer än en typkolumn: steg i ett workflow
  har `step_title` och `step_intro` som en samling inte har.
