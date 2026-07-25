-- Genererad av scripts/generate-catalog-parameterized-prompts.mjs.
-- Synkar de tio filbaserade parametriserade prompterna till Öppen katalog.
-- Kör efter 20260725133000_catalog_parameter_schemas.sql.

create temporary table parameterized_catalog_prompt_seed (
    slug text primary key,
    package_slug text not null,
    sort_order integer not null,
    icon_key text not null,
    color_theme text not null,
    title text not null,
    summary text not null,
    prompt_text text not null,
    parameter_schema jsonb not null,
    default_bindings jsonb not null,
    binding_overrides jsonb not null
);

insert into parameterized_catalog_prompt_seed (
    slug,
    package_slug,
    sort_order,
    icon_key,
    color_theme,
    title,
    summary,
    prompt_text,
    parameter_schema,
    default_bindings,
    binding_overrides
) values
    ('klarsprak', 'kommunikation', 100, 'message', 'blue', $title_klarsprak$📝 Skriv om till klarspråk$title_klarsprak$, $summary_klarsprak$Gör text kortare och lättare att förstå för invånare.$summary_klarsprak$, $prompt_klarsprak$Skriv om till klarspråk
Gör text kortare och lättare att förstå för invånare. Behåll innehållet men förenkla språket.

Du är en expert på att göra tung text lätt att läsa. Din uppgift är att omformulera texten för invånare som ska förstå den utan särskilda kunskaper.

**Regler:**
1. Använd korta meningar (8–12 ord per mening)
2. Byt svåra ord mot enkla motsvarigheter (ex: "verkställa" → "göra", "hållas" → "äger rum")
3. Struktur: Numrerade listor och korta stycken – max 4–5 meningar per stycke
4. Minska längd med 30–50% (slopa upprepningar, fluff, juridiska fraser)
5. Exempel: "I enlighet med gällande lagstiftning föreskrivs att..." → "Enligt lag måste vi..."

**Före/efter-exempel:**

*Innan (svårt):*
"Verksamheten förutsätter en saklig och opartisk handläggning vilken bygger på väl underbyggda faktiska förhållanden i enlighet med lagstiftningen."

*Efter (enkelt):*
"Vi granskar ärendet objektivt och baserar beslutet på sakliga fakta enligt lag."

**Output-format:**
- Början: Kort sammanfattning (1 mening) av vad texten handlar om
- Mellandelar: Numrerade punkter eller korta stycken
- Slut: Nästa steg eller kontaktuppgifter (om relevant)

Input:
[klistra in här]$prompt_klarsprak$, $schema_klarsprak${"version":1,"legacy_fallback_field":"input","fields":[{"key":"kontext","type":"enum","source":"global","required":true},{"key":"roll","type":"enum","source":"global","required":true},{"key":"malgrupp","type":"enum","source":"global","required":true},{"key":"ton","type":"enum","source":"global","required":true,"options":["neutral","tydlig och vänlig","formell"]}]}$schema_klarsprak$::jsonb, $defaults_klarsprak${"ton":"tydlig och vänlig"}$defaults_klarsprak$::jsonb, $overrides_klarsprak$[{"when":{"kontext":"skola"},"set":{"malgrupp":"vårdnadshavare"}}]$overrides_klarsprak$::jsonb),
    ('mejl', 'kommunikation', 101, 'message', 'blue', $title_mejl$📧 Svar på medborgarmejl$title_mejl$, $summary_mejl$Skriv ett vänligt och sakligt svar på mejl från invånare.$summary_mejl$, $prompt_mejl$Svar på medborgarmejl
Skriv ett {{ton}} svar till {{malgrupp}}. Sammanfatta problemet, ge nästa steg och kontaktväg.

Du har rollen {{roll}} i {{kontext}} och svarar på mejl från {{malgrupp}}. Ditt mål är att vara vänlig, professionell och tydlig.

**Ton och struktur:**
1. **Öppning:** Tacka för mejlet, bekräfta att vi mottagit det
2. **Sammanfattning:** Kort återgivning av frågan/problemet (visa att du läst den)
3. **Svar:** Ge konkret svar eller förklaring
4. **Nästa steg:** Berätta vad som händer härnäst (tidsram, process)
5. **Avslutning:** Kontaktuppgifter, erbjud hjälp till nya frågor

**Tonfall:**
- Vänlig men professionell (inte för familjär)
- Kort och tydlig (max 200 ord)
- Använd "vi" när det gäller kommunen
- Undvik byråkratiska fraser

**Före/efter-exempel:**

*Innan:*
"Vi kan ej godkänna er ansökan på grund av att erforderliga dokument ej bifogats."

*Efter:*
"Vi behöver ett par dokument till för att kunna behandla din ansökan. Läs vad du ska skicka här: [länk]. Frågor? Ring oss på XXX."

Input:
[klistra in här]$prompt_mejl$, $schema_mejl${"version":1,"legacy_fallback_field":"input","fields":[{"key":"kontext","type":"enum","source":"global","required":true},{"key":"roll","type":"enum","source":"global","required":true},{"key":"malgrupp","type":"enum","source":"global","required":true},{"key":"ton","type":"enum","source":"global","required":true,"options":["neutral","tydlig och vänlig","formell"]}]}$schema_mejl$::jsonb, $defaults_mejl${"roll":"handläggare","malgrupp":"invånare","ton":"tydlig och vänlig"}$defaults_mejl$::jsonb, $overrides_mejl$[{"when":{"kontext":"företag"},"set":{"malgrupp":"företagare"}}]$overrides_mejl$::jsonb),
    ('faq', 'kommunikation', 102, 'message', 'blue', $title_faq$❓ Gör en FAQ$title_faq$, $summary_faq$Skapa 8–12 frågor och svar baserat på ett dokument eller policy.$summary_faq$, $prompt_faq$Gör en FAQ
Skapa 8–12 frågor och svar baserat på ett dokument eller policy. Riktat till {{malgrupp}}.

Du har rollen {{roll}} i {{kontext}}. Din uppgift är att omvandla ett komplext dokument till {{ton}} svenska och enkla frågor/svar för {{malgrupp}}.

**Process:**
1. Läs texten och identifiera de viktigaste punkterna
2. Omvandla varje punkt till en fråga som {{malgrupp}} faktiskt ställer (börja ofta med "Vad...", "Hur...", "Kan jag...")
3. Svara kort och tydligt på varje fråga (2–3 meningar max)
4. Använd samma enkla språk som i Klarspråk-prompten (korta meningar, vanliga ord)
5. Skapa 8–12 fråga/svar-par

**Format för varje fråga/svar:**
```
**F: [Vanlig fråga från invånare]**
S: [Kort, tydligt svar. Börja med det viktigaste. Länka vidare vid behov.]
```

**Före/efter-exempel:**

*Innan (från dokument):*
"Verksamheten hålls i enlighet med kvalitetsstandarder enligt kommunens policy för servicenivåer."

*FAQ-fråga:*
"F: Hur vet jag att servicen är bra? S: Vi följer Kommunens kvalitetskrav. Du kan läsa dem här: [länk]."

**Målgrupp:** {{malgrupp}}

Input:
[klistra in här]$prompt_faq$, $schema_faq${"version":1,"legacy_fallback_field":"input","fields":[{"key":"kontext","type":"enum","source":"global","required":true},{"key":"roll","type":"enum","source":"global","required":true},{"key":"malgrupp","type":"enum","source":"global","required":true},{"key":"ton","type":"enum","source":"global","required":true,"options":["neutral","tydlig och vänlig","formell"]}]}$schema_faq$::jsonb, $defaults_faq${"roll":"kommunikatör","malgrupp":"invånare","ton":"tydlig och vänlig"}$defaults_faq$::jsonb, $overrides_faq$[{"when":{"kontext":"skola"},"set":{"malgrupp":"vårdnadshavare"}},{"when":{"kontext":"företag"},"set":{"malgrupp":"företagare"}}]$overrides_faq$::jsonb),
    ('kallelse', 'kommunikation', 103, 'message', 'blue', $title_kallelse$📋 Skriva kallelse$title_kallelse$, $summary_kallelse$Skriv en formell men vänlig kallelse till möte, event eller träff.$summary_kallelse$, $prompt_kallelse$Skriva kallelse
Skriv en formell men vänlig kallelse till möte, event eller träff.

Du är administratör som skickar kallelser. Din uppgift är att skapa ett tydligt, kortfattat brev som säger VAD, NÄR, VAR och VAD MAN SKA FÖRBERED.

**Struktur (följ denna ordning):**
1. **Rubrik:** "Kallelse till [möte/event]"
2. **Hälsning:** "Ni/Du är härmed kallad till..."
3. **Tid & Plats:** Datum, tid (ankomsttid + sluttid), plats, sal/rum
4. **Dagordning:** Numrerad lista (1. Öppnande, 2. Ärendet, 3. Övrigt, etc.)
5. **Praktik:** Parkeringsinfo, köp biljett (om aktuellt), anmälan krävs? Senast när?
6. **Bilagor:** "Se bifogat: Dokumentation, rapport, etc."
7. **Avslutning:** "Vid frågor, kontakta [namn & tel]"

**Tonfall:**
- Formell men vänlig (inte militärisk)
- Använd "ni" för större grupper, "du" för personlig inbjudan

**Före/efter-exempel:**

*Innan:*
"Vi håller möte på torsdag i sal B gällande budgetfrågor."

*Efter:*
```
KALLELSE TIL BUDGETMÖTE
Ni är härmed kallad till möte om kommunens budget 2027.

DATUM & TID
Torsdag 14 februari, 14:00–16:30
Plats: Kommunhuset, sal B

DAGORDNING
1. Öppnande
2. Kommunens övergripande budget 2027
3. Avdelningsbetänkanden
4. Övrigt

PRAKTIK
Parkering finns på gården. Anmälan senast tisdag till Anna (anna@kommun.se / 0123–456 789).

Se bifogat: Budgetförslag 2027
```

Input:
[klistra in här]$prompt_kallelse$, $schema_kallelse${"version":1,"legacy_fallback_field":"input","fields":[{"key":"kontext","type":"enum","source":"global","required":true},{"key":"roll","type":"enum","source":"global","required":true},{"key":"malgrupp","type":"enum","source":"global","required":true},{"key":"ton","type":"enum","source":"global","required":true,"options":["neutral","tydlig och vänlig","formell"]}]}$schema_kallelse$::jsonb, $defaults_kallelse${"roll":"administratör","ton":"formell"}$defaults_kallelse$::jsonb, $overrides_kallelse$[{"when":{"kontext":"skola"},"set":{"malgrupp":"vårdnadshavare"}}]$overrides_kallelse$::jsonb),
    ('beslutsunderlag', 'beslutsberedning', 104, 'clipboard', 'slate', $title_beslutsunderlag$🎯 Beslutsunderlag$title_beslutsunderlag$, $summary_beslutsunderlag$Sammanfatta ett ärende eller förslag som presenteras för ett beslutande organ.$summary_beslutsunderlag$, $prompt_beslutsunderlag$Skriva beslutsunderlag
Sammanfatta ett ärende eller förslag som presenteras för ett beslutande organ.

Du har rollen {{roll}} i {{kontext}} och förbereder ärenden för {{malgrupp}}. Din uppgift är att presentera ärendet sakligt och strukturerat så att {{malgrupp}} kan fatta informerat beslut.

**Strikt struktur (följ denna ordning):**

1. **Rubrik:** Ärendet (ex: "Beslut om ny matpolicy")
2. **Sammanfattning** (3–5 rader max): Vad är ärendet? Vad föreslår vi? Varför? Vad är beslutet?
3. **Bakgrund:** Historik och kontext (5–10 rader). Varför är detta aktuellt nu?
4. **Analys/Förslag:** Alternativen och rekommendationen (numererad lista):
   - Alt. 1 (kortfattat + för/nackdelar)
   - Alt. 2 (kortfattat + för/nackdelar)
   - **Rekommendation:** Alt. X för dessa skäl...
5. **Konsekvenser:** Vilka effekter får beslutet? (personell, operationell, strategisk, kommunal)
6. **Ekonomi:** Kostnad/besparingar. Täcks det i budget? Resursbehov? (2–3 rader)
7. **Juridik:** Lagliga krav/riktlinjer? (1–2 rader, eller "Ingen" om N/A)
8. **Beslut:** "Nämnden beslutar [vad]/[hur]/[när]"

**Tonfall:** Saklig, neutral, ingen värderingar

**Målgrupp:** {{malgrupp}}

**Max längd:** 2 sidor (använd kortfattat språk, nämnder läser snabbt)

Input:
[klistra in här]$prompt_beslutsunderlag$, $schema_beslutsunderlag${"version":1,"legacy_fallback_field":"input","fields":[{"key":"kontext","type":"enum","source":"global","required":true},{"key":"roll","type":"enum","source":"global","required":true},{"key":"malgrupp","type":"enum","source":"global","required":true}]}$schema_beslutsunderlag$::jsonb, $defaults_beslutsunderlag${"roll":"utredare","malgrupp":"beslutsfattare"}$defaults_beslutsunderlag$::jsonb, $overrides_beslutsunderlag$[{"when":{"kontext":"kommun"},"set":{"malgrupp":"nämnd"}},{"when":{"kontext":"skola"},"set":{"malgrupp":"ledning"}}]$overrides_beslutsunderlag$::jsonb),
    ('rutin', 'processer', 105, 'list', 'teal', $title_rutin$⚙️ Rutiner & anvisningar$title_rutin$, $summary_rutin$Gör instruktioner tydliga för anställda eller kollegor.$summary_rutin$, $prompt_rutin$Skriva rutin eller arbetsanvisning
Gör instruktioner tydliga för {{malgrupp}}.

Du har rollen {{roll}} i {{kontext}}. Din uppgift är att skapa en steg-för-steg rutin som {{malgrupp}} kan följa utan att fråga mer än nödvändigt.

**Struktur (följ denna ordning):**

1. **Rubrik:** Rutinens namn (ex: "Så hanterar du en skadeanmälan")
2. **Syfte:** Vad är målet med denna rutin? Vilken process är detta? (1–2 rader)
3. **Ansvarig:** Vem gör detta? (titel/avdelning)
4. **Förutsättningar:** Vad måste finnas på plats innan start? (material, åtkomst, godkännande)
5. **Steg-för-steg instruktioner:** Numrerad lista, en handling per steg. Använd imperativ:
   - "Logga in på systemet..."
   - "Öppna dokumentet..."
   - "Skicka mejl till..."
   - **Tips:** Lägg till varningar/tips för trickiga steg (markera med ⚠️ eller "OBS")
6. **Kontrollpunkter:** Vad ska man kontrollera innan nästa steg? (checkbox-format)
7. **Vad gör man om något går fel?** Felsökning/eskalering (kort tabell eller lista)
8. **Dokumentation:** Vad sparas var? Vilken mall används?
9. **Kontakt:** Vem frågar man om det uppstår problem?

**Tonfall:** Praktisk, direkt, ingen onödig teori

**Målgrupp:** {{malgrupp}}

**Exempel-struktur:**
```
RUTIN: Hantering av skadeanmälan

SYFTE: Registrera och eskalera skador enligt försäkringsavtal.

ANSVARIG: Fastighetsteam

STEG:
1. Ta emot anmälan (mejl, telefon, webb-form)
2. Registrera i systemet "Fastighetskostnader"
   ⚠️ Skriv personnummer utan bindestreck
3. Fotograf dokumenterar skadan
4. ...
```

Input:
[klistra in här]$prompt_rutin$, $schema_rutin${"version":1,"legacy_fallback_field":"input","fields":[{"key":"kontext","type":"enum","source":"global","required":true},{"key":"roll","type":"enum","source":"global","required":true},{"key":"malgrupp","type":"enum","source":"global","required":true}]}$schema_rutin$::jsonb, $defaults_rutin${"roll":"samordnare","malgrupp":"medarbetare"}$defaults_rutin$::jsonb, $overrides_rutin$[{"when":{"kontext":"skola"},"set":{"roll":"administratör"}},{"when":{"kontext":"kommun"},"set":{"roll":"handläggare"}}]$overrides_rutin$::jsonb),
    ('tvaversioner', 'kommunikation', 106, 'message', 'blue', $title_tvaversioner$🔀 Två versioner$title_tvaversioner$, $summary_tvaversioner$Omvandla mellan kommuniceringsmönster – t.ex. från formell till vardaglig.$summary_tvaversioner$, $prompt_tvaversioner$Två versioner – formell och vardaglig
Omvandla mellan kommuniceringsmönster – t.ex. från formell till folklig, eller tvärtom.

Du har rollen {{roll}} i {{kontext}}. Din uppgift är att skapa två versioner av samma budskap för {{malgrupp}} i en {{ton}} grundton.

**Version 1: FORMELL (för officiella sammanhang)**
- Använd: juridiska termer, "avses", "verksamheten", passiv form
- Tonfall: professionell, saklig, auktoritativ
- Längd: normal/längre
- Exempel: "Verksamheten bedrivs i överensstämmelse med gällande lagstiftning"

**Version 2: VARDAGLIG (för {{malgrupp}}/webb)**
- Använd: vanliga ord, aktiv form, "vi/du", korta meningar
- Tonfall: vänlig, öppen, direkt
- Längd: kortare, ofta numrerad
- Exempel: "Vi följer lagen när vi jobbar"

**Struktur för output:**
```
FORMELL VERSION
[text här]

VARDAGLIG VERSION
[text här]

SKILLNADER
- Ord som ändrades: juridisk → vardaglig motsvarighet
- Ton: från [A] till [B]
```

**Före/efter-exempel:**

*Input:*
"Ansökningsprocessen kräver att sökanden bifoga relevanta dokument vilka attesteras av behörig myndighet."

*FORMELL:*
"Ansökaren måste bifoga dokument som attesterats av relevant myndighet."

*VARDAGLIG:*
"Du skickar in några dokument som visar att det stämmer. En myndighet måste skriva under på dem."

Input:
[klistra in här]$prompt_tvaversioner$, $schema_tvaversioner${"version":1,"legacy_fallback_field":"input","fields":[{"key":"kontext","type":"enum","source":"global","required":true},{"key":"roll","type":"enum","source":"global","required":true},{"key":"malgrupp","type":"enum","source":"global","required":true},{"key":"ton","type":"enum","source":"global","required":true,"options":["neutral","tydlig och vänlig","formell"]}]}$schema_tvaversioner$::jsonb, $defaults_tvaversioner${"roll":"kommunikatör","malgrupp":"invånare","ton":"tydlig och vänlig"}$defaults_tvaversioner$::jsonb, $overrides_tvaversioner$[{"when":{"kontext":"skola"},"set":{"malgrupp":"vårdnadshavare"}}]$overrides_tvaversioner$::jsonb),
    ('informationsutskick', 'kommunikation', 107, 'message', 'blue', $title_informationsutskick$📣 Skapa informationsutskick$title_informationsutskick$, $summary_informationsutskick$Skriv ett tydligt informationsmeddelande med rubrik, sammanfattning och nästa steg.$summary_informationsutskick$, $prompt_informationsutskick$Skapa informationsutskick

Skriv ett tydligt informationsmeddelande med rubrik, sammanfattning och nästa steg. Passar för störningar, förändringar, nya rutiner, påminnelser och lätt krisinfo.

Du är kommunikatör i en svensk kommun. Skriv ett informationsutskick som är tydligt, vänligt och korrekt.

Målgrupp: [invånare / vårdnadshavare / personal]
Kanal: [e-post / webb / SMS / sociala medier]
Ton: [neutral / lugnande / extra tydlig]
Längd: [kort / normal]

Underlag (klistra in texten eller inkludera snabbinmatningstexten):
[TEXT]

Krav på format:

1. Rubrik (max 8 ord)
2. Kort sammanfattning (1–2 meningar)
3. Vad som händer (punktlista)
4. Vad mottagaren behöver göra (punktlista)$prompt_informationsutskick$, $schema_informationsutskick${"version":1,"legacy_fallback_field":"input","fields":[{"key":"kontext","type":"enum","source":"global","required":true},{"key":"roll","type":"enum","source":"global","required":true},{"key":"malgrupp","type":"enum","source":"global","required":true},{"key":"ton","type":"enum","source":"global","required":true,"options":["neutral","tydlig och vänlig","formell"]}]}$schema_informationsutskick$::jsonb, $defaults_informationsutskick${"roll":"kommunikatör","ton":"tydlig och vänlig"}$defaults_informationsutskick$::jsonb, $overrides_informationsutskick$[{"when":{"kontext":"skola"},"set":{"malgrupp":"vårdnadshavare"}}]$overrides_informationsutskick$::jsonb),
    ('enkel_infografik', 'visuellt', 108, 'image', 'orange', $title_enkel_infografik$Enkel infografik$title_enkel_infografik$, $summary_enkel_infografik$Skapa en enkel visuell struktur för information, siffror eller viktiga punkter.$summary_enkel_infografik$, $prompt_enkel_infografik$Du hjälper användaren att skapa en enkel och tydlig infografik för {{kontext}} information riktad till {{malgrupp}}.

Skapa ett bild- och layoutunderlag utifrån användarens ämne.

Ämne/underlag:
[klistra in här]

Infografiken ska ha en {{ton}} stil. Den ska vara lätt att förstå för {{malgrupp}}, luftig och visuellt balanserad.

Strukturera svaret med följande rubriker:

1. Bildprompt
Skriv en tydlig prompt som kan användas i en bildgenerator. Prompten ska beskriva stil, motiv, layout och känsla.

2. Layoutförslag
Beskriv hur infografiken kan byggas upp, till exempel rubrik, 3–5 punkter, ikoner och eventuell källrad.

3. Text att lägga in manuellt
Föreslå korta texter som användaren själv kan lägga in i Canva, PowerPoint eller liknande verktyg. Hitta inte på siffror.

4. Alt-text
Skriv en kort alt-text som beskriver infografikens syfte och innehåll.

5. Kontroll innan användning
Lista kort vad användaren behöver kontrollera: siffror, källa, personuppgifter, tillgänglighet och att visualiseringen inte är missvisande.

Viktiga begränsningar:
- Hitta inte på siffror.
- Lägg inte in personuppgifter.
- Undvik verkliga logotyper.
- Undvik för mycket text i själva bilden.
- Rekommendera att text och siffror läggs in manuellt om korrekthet är viktig.
- Använd en {{ton}} och tillgänglig ton som passar {{malgrupp}} i {{kontext}}.$prompt_enkel_infografik$, $schema_enkel_infografik${"version":1,"legacy_fallback_field":"input","fields":[{"key":"kontext","type":"enum","source":"global","required":true},{"key":"malgrupp","type":"enum","source":"global","required":true},{"key":"ton","type":"enum","source":"global","required":true,"options":["neutral","tydlig och vänlig","formell","pedagogisk"]}]}$schema_enkel_infografik$::jsonb, $defaults_enkel_infografik${"malgrupp":"invånare","ton":"tydlig och vänlig"}$defaults_enkel_infografik$::jsonb, $overrides_enkel_infografik$[{"when":{"kontext":"skola"},"set":{"malgrupp":"elever","ton":"pedagogisk"}}]$overrides_enkel_infografik$::jsonb),
    ('illustration_informationsutskick', 'visuellt', 109, 'image', 'orange', $title_illustration_informationsutskick$Illustration till informationsutskick$title_illustration_informationsutskick$, $summary_illustration_informationsutskick$Skapa en trygg och neutral bildidé till kommunalt informationsutskick.$summary_illustration_informationsutskick$, $prompt_illustration_informationsutskick$Du hjälper användaren att skapa en illustration till ett informationsutskick i {{kontext}} riktad till {{malgrupp}}.

Skapa ett bildunderlag som passar ämne, målgrupp, kanal och en {{ton}} känsla.

Ämne/underlag:
[klistra in här]

Strukturera svaret med följande rubriker:

1. Bildprompt
Skriv en färdig prompt för en bildgenerator. Prompten ska beskriva motiv, stil, känsla, komposition och vad som ska undvikas.

2. Motivförslag
Ge 2–3 alternativa motiv som passar budskapet.

3. Stil och känsla
Beskriv lämplig visuell stil, till exempel modern illustration, lugna färger, skandinavisk känsla och tydlig komposition.

4. Alt-text
Skriv en kort och saklig alt-text till den föreslagna bilden.

5. Riskkontroll
Lista vad användaren behöver kontrollera innan bilden används.

Viktiga begränsningar:
- Undvik igenkännbara personer.
- Undvik barnansikten i närbild.
- Undvik verkliga logotyper.
- Undvik text i bilden om den inte är absolut nödvändig.
- Undvik känsliga situationer.
- Bilden ska inte se ut som ett verkligt dokumentärt foto.
- Bilden ska stödja informationen, inte bära hela budskapet.$prompt_illustration_informationsutskick$, $schema_illustration_informationsutskick${"version":1,"legacy_fallback_field":"input","fields":[{"key":"kontext","type":"enum","source":"global","required":true},{"key":"malgrupp","type":"enum","source":"global","required":true},{"key":"ton","type":"enum","source":"global","required":true,"options":["neutral","tydlig och vänlig","varm och trygg","formell"]}]}$schema_illustration_informationsutskick$::jsonb, $defaults_illustration_informationsutskick${"malgrupp":"invånare","ton":"varm och trygg"}$defaults_illustration_informationsutskick$::jsonb, $overrides_illustration_informationsutskick$[{"when":{"kontext":"skola"},"set":{"malgrupp":"vårdnadshavare"}},{"when":{"kontext":"företag"},"set":{"ton":"neutral"}}]$overrides_illustration_informationsutskick$::jsonb);

do $$
declare
    missing_packages text;
begin
    select string_agg(missing.package_slug, ', ' order by missing.package_slug)
    into missing_packages
    from (
        select distinct seed.package_slug
        from parameterized_catalog_prompt_seed seed
        left join public.catalog_packages package on package.slug = seed.package_slug
        where package.id is null
    ) missing;

    if missing_packages is not null then
        raise exception 'Katalogpaket saknas: %', missing_packages;
    end if;
end
$$;

insert into public.catalog_prompts (
    slug,
    status,
    prompt_kind,
    icon_key,
    color_theme
)
select
    slug,
    'published',
    'prompt',
    icon_key,
    color_theme
from parameterized_catalog_prompt_seed
on conflict (slug) do update set
    status = excluded.status,
    prompt_kind = excluded.prompt_kind,
    icon_key = excluded.icon_key,
    color_theme = excluded.color_theme;

insert into public.catalog_prompt_variants (
    prompt_id,
    context_key,
    title,
    summary,
    prompt_text,
    audience_label,
    tone_hint,
    parameter_schema,
    default_bindings,
    binding_overrides
)
select
    prompt.id,
    'generell',
    seed.title,
    seed.summary,
    seed.prompt_text,
    seed.default_bindings ->> 'malgrupp',
    seed.default_bindings ->> 'ton',
    seed.parameter_schema,
    seed.default_bindings,
    seed.binding_overrides
from parameterized_catalog_prompt_seed seed
join public.catalog_prompts prompt on prompt.slug = seed.slug
on conflict (prompt_id, context_key) do update set
    prompt_text = excluded.prompt_text,
    title = excluded.title,
    summary = excluded.summary,
    audience_label = excluded.audience_label,
    tone_hint = excluded.tone_hint,
    parameter_schema = excluded.parameter_schema,
    default_bindings = excluded.default_bindings,
    binding_overrides = excluded.binding_overrides;

insert into public.catalog_package_items (
    package_id,
    prompt_id,
    sort_order,
    step_title,
    step_intro,
    is_required
)
select
    package.id,
    prompt.id,
    seed.sort_order,
    seed.title,
    seed.summary,
    true
from parameterized_catalog_prompt_seed seed
join public.catalog_packages package on package.slug = seed.package_slug
join public.catalog_prompts prompt on prompt.slug = seed.slug
on conflict (package_id, prompt_id) do update set
    sort_order = excluded.sort_order,
    step_title = excluded.step_title,
    step_intro = excluded.step_intro,
    is_required = excluded.is_required;

drop table parameterized_catalog_prompt_seed;
