# GDPR-policy & Dataskydd
## Promptmallar för kommun

**Version:** 1.1
**Datum:** 2026-07-29

---

## 1. Dataskyddspolicy - Kort Version

### 1.1 Vilka data samlar vi?

Vi samlar inte personuppgifter från användare som använder de öppna promptmallarna. Promptbanken samlar däremot anonym, aggregerad användningsstatistik för det öppna biblioteket, till exempel när en prompt visas, öppnas eller kopieras i webbgränssnittet och när öppna MCP-anrop listar, söker, öppnar eller hämtar prompts.

Statistiken används för återkoppling och produktutveckling av biblioteket, inte för individuell spårning. Payloads hålls avsiktligt små och anonyma.

**Specifikt:**
- ✅ Vi lagrar inte det som du skriver/kopierar
- ✅ Vi lagrar inte promptinnehåll från användare eller råa söktermer
- ✅ Vi använder inte statistiken för att följa enskilda personer
- ✅ Vi lagrar inte din IP-adress eller webbläsarinfo
- ✅ Vi använder inga cookies för spårning
- ✅ Vi lagrar inte e-postadresser, user-agent, nyckelmaterial eller personidentifierande klientdata i användningsstatistiken

### 1.2 Clipboard-API (kopiera-funktionen)

Knappen "Kopiera" använder webbläsarens **Clipboard-API**:
- All kopiering sker **lokalt på din dator**
- Prompttexten överförs inte över nätverk till Promptbanken
- En liten anonym användningshändelse kan skickas för att mäta att en prompt kopierades, utan promptinnehåll eller personidentifierande klientdata
- Du är ensam ansvarig för vad du gör med den kopierade texten

---

## 2. Ditt ansvar som handläggare

### 2.1 Innan du kopierar en prompt

✅ **Anonymisera alla personuppgifter från originaltexten:**
- Ersätt namn med "Person A", "Medborgare", etc.
- Ersätt personnummer med "[PERSONNUMMER]"
- Ersätt adresser och telefonnummer med "[ADRESS]", "[TELEFON]"
- Ersätt ärendenummer med "[ÄRENDENUMMER]"

### 2.2 Efter du kopierar

✅ **Du är ansvarig för:**
- Att verifiera att AI-output är korrekt
- Att AI-output inte innehåller känslig info från ditt prompt
- Att publicera/skicka endast efter mänsklig review

### 2.3 Lagring & Arkivering

✅ **Följ kommunens arkiveringsregler:**
- Arbetsutdrag sparas enligt sekretesslagen
- Mejl arkiveras enligt e-postpolicy
- Interna rutiner sparas enligt dokumentationskrav

---

## 3. Använares rättigheter (GDPR)

### 3.1 Rätt till information
Du har rätt att veta att denna webbsida använder AI-assisterade verktyg.  
→ **Implementerat:** Disclaimer på hemsidan

### 3.2 Rätt till åtkomst
Du kan begära veta vilka data vi har om dig.  
→ **Vi har inga personuppgifter eller användarpromptar från den öppna katalogen**. Den anonyma användningsstatistiken är aggregerad och är inte avsedd att kopplas till enskilda personer (se punkt 1.1).

### 3.3 Rätt till rättelse
Du kan begära att vi rättar felaktig data om dig.  
→ **Inte tillämpligt för den öppna katalogens anonyma statistik**, eftersom den inte innehåller personuppgifter eller användarpromptar som kan rättas för en enskild person.

### 3.4 Rätt till radering
Du kan begära att vi raderar data om dig.  
→ **Inte tillämpligt för den öppna katalogens anonyma statistik**, eftersom den inte är kopplad till en identifierbar användare.

### 3.5 Rätt till begränsning
Du kan begära att vi begränsar vår behandling av dina data.  
→ **Inte tillämpligt för den öppna katalogens anonyma statistik**, eftersom vi inte behandlar personuppgifter eller användarpromptar i den statistiken.

---

## 4. Kontakt för dataskyddsfrågor

**För frågor om dataskydd & GDPR:**

📧 **E-post:** peter@promptbanken.se

> Obs: Tjänsten har ännu inte formellt granskats av en kommunal dataskyddssamordnare. Innan skarp driftsättning i en kommun ansvarar respektive kommun för granskning enligt sin egen dataskyddsprocess.

---

## 5. Ändringar av denna policy

Vi kan uppdatera denna policy när som helst. Ändringar publiceras här:

- **Version 1.1 (2026-07-29):** Förtydligar anonym användningsstatistik för öppna bibliotekshändelser och kopiering
- **Version 1.0 (2026-01-26):** Initial policy

---

## 6. Juridisk grund för dataskydd

Denna tjänst är utformad enligt:
- **EU:s dataskyddsförordning (GDPR)**
- **Sekretesslagen (SekrL) för offentlig sektor**
- **Kommunens arkiveringsregler**
- **EU:s AI Act (självklassificerad Low-Risk)**

*Utformad enligt ovanstående ramverk. Formell efterlevnadsgranskning (IT-säkerhet, dataskyddssamordnare, juridik) är ännu inte genomförd – se [AI-COMPLIANCE.md](AI-COMPLIANCE.md).*

---

## 7. Checklist för handläggare

🔒 **Före varje användning av en prompt:**

- [ ] Jag har läst säkerhetsvisan på denna prompt
- [ ] Jag har anonymiserat alla personuppgifter i min text
- [ ] Jag förstår att AI-output kan innehålla fel
- [ ] Jag kommer att granska output innan publicering
- [ ] Jag vet att jag är ansvarig för resultatet, inte tjänsten

---

## 8. Skyddsåtgärder

### Tekniska åtgärder
- ✅ HTTPS (krypterad överföring)
- ✅ Prompttext och själva kopieringen hålls lokalt i webbläsaren; anonyma statistikhändelser omfattas av punkten nedan
- ✅ Små anonyma statistikhändelser kan lagras i Supabase (EU-region) för aggregerad uppföljning

### Administrativa åtgärder
- ✅ Åtkomst begränsad till behöriga handläggare
- ✅ Audit-logg (version 1.1+)
- ✅ Årlig säkerhetsgranskning

---

## Dokumenthistorik

| Version | Datum | Ändringar |
|---|---|---|
| 1.1 | 2026-07-29 | Förtydligar att prompttext stannar lokalt vid kopiering, men att en liten anonym användningshändelse kan skickas. Skiljer personuppgiftsbehandling från anonym, aggregerad användningsstatistik. |
| 1.0 | 2026-01-26 | Initial GDPR-policy |
