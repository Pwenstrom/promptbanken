// SPEGLING av docs/creator-publiceringsregler.md.
//
// Edge-funktioner kan inte läsa godtyckliga repofiler i runtime, så
// reglerna bakas in här. Ändra markdownfilen först, kopiera hit, räkna upp
// RULES_VERSION i båda, deploya. Versionen skrivs till varje granskningsrad
// så att gamla omdömen går att tolka när reglerna ändrats.

export const RULES_VERSION = "2026-08-24.1";

export const RULES_MARKDOWN = `# Promptbankens publiceringsregler för creator-innehåll

## 1. Form och språk

- Svenska, om prompten inte uttryckligen handlar om ett annat språk.
- Prompten ska säga vad som ska göras, inte vara en lös fråga.
- Platshållare för användarens egen text skrivs [klistra in här] eller [TEXT], som i resten av Promptbanken.
- Ingen inledande artighetsfras riktad till modellen.
- Titeln ska beskriva uppgiften, inte vara ett utrop.

## 2. Kvalitet

- Prompten ska ge ett användbart resultat utan att användaren behöver skriva om den först.
- Den ska vara konkret nog att två olika användare får jämförbara svar.
- Sammanfattningen ska beskriva vad prompten gör, inte vem den är för.
- En prompt som bara säger "skriv en text om X" är för tunn för katalogen.

## 3. Risk

- Prompten får inte be användaren klistra in personnummer, namn på enskilda, diarienummer eller andra personuppgifter.
- Prompten får inte formulera myndighetsbeslut, medicinska bedömningar eller juridisk rådgivning som om resultatet vore färdigt att använda.
- Prompter som rör känsliga områden — myndighetsutövning, elevärenden, personalärenden, vård — ska påminna om mänsklig granskning.
- Prompten får inte uppmana till att kringgå regelverk eller rutiner.

## 4. Rättigheter

- Innehållet ska vara creatorns eget eller något hen har rätt att sprida.
- Längre citat, metodbeskrivningar med känt upphov, eller igenkännbart material från en identifierbar källa ska flaggas.
- Varumärken och organisationsnamn får inte antyda ett samarbete eller ett godkännande som inte finns.
- En prompt som är en lätt omskrivning av en känd, upphovsrättsskyddad metod ska flaggas även om orden är nya.

## 5. Dubletter

- Innehåll som i praktiken gör samma sak som en befintlig katalogpost ska flaggas, med angivande av vilken post det gäller.
- Att täcka samma ämne är inte en dublett. Att lösa samma uppgift på samma sätt är det.
- Ett paket är en dublett om det har i huvudsak samma prompts i samma ordning som ett befintligt paket.

## Om omdömet

- Grön — inget hindrar publicering. Små språkliga påpekanden får finnas ändå.
- Gul — publicerbart efter ändring, eller värt en mänsklig blick. Använd gul när det är en fråga om kvalitet eller form.
- Röd — bör inte publiceras som det ser ut. Använd röd när det rör risk, rättigheter eller en tydlig dublett.
`;
