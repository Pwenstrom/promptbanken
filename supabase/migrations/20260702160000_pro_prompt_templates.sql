-- Promptbanken Pro: 42 premium-mallar i 7 områden.
--
-- Till skillnad från standardmallarna (statiska prompts.json/prompts/*.txt,
-- öppna för alla) är premiuminnehållet åtkomstspärrat. Eftersom RLS är
-- radbaserad och inte kan dölja en enskild kolumn, exponeras innehållet via
-- funktionen list_pro_templates() nedan:
--   Free / ej inloggad → titel, syfte, outputformat, område (teaser),
--                         men prompt_text = null.
--   Pro (även aktiv invite-trial) → allt, inklusive prompt_text.

create table if not exists public.pro_prompt_templates (
    id                uuid primary key default gen_random_uuid(),
    area              text not null,
    area_label        text not null,
    title             text not null,
    syfte             text not null,
    output_format     text not null,
    prompt_text       text not null,
    tags              text[] not null default '{}',
    risk_level        public.content_risk_level not null default 'low',
    security_examples text[] not null default '{}',
    sort_order        integer not null default 0,
    created_at        timestamptz not null default now()
);

alter table public.pro_prompt_templates enable row level security;

-- Direkt tabellåtkomst är endast för plattformsägare (skötsel/underhåll).
-- Vanliga användare läser via list_pro_templates() (SECURITY DEFINER).
drop policy if exists "pro_prompt_templates_platform_owner_all" on public.pro_prompt_templates;
create policy "pro_prompt_templates_platform_owner_all"
on public.pro_prompt_templates
for all
to authenticated
using (app_private.current_user_is_platform_owner())
with check (app_private.current_user_is_platform_owner());

-- Returnerar prompt_text bara om anroparens personliga workspace har en
-- aktiv Pro-plan. Free/ej inloggad får teaser (prompt_text = null).
create or replace function public.list_pro_templates()
returns table(
    id                uuid,
    area              text,
    area_label        text,
    title             text,
    syfte             text,
    output_format     text,
    prompt_text       text,
    tags              text[],
    risk_level        public.content_risk_level,
    security_examples text[],
    sort_order        integer,
    is_unlocked       boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    has_pro         boolean := false;
begin
    if current_user_id is not null then
        select exists (
            select 1
              from public.profiles p
              join public.workspaces w on w.id = p.workspace_id
             where p.user_id = current_user_id
               and w.type = 'personal'
               and w.plan = 'pro'
               and w.status = 'active'
               and (w.plan_expires_at is null or w.plan_expires_at > now())
        ) into has_pro;
    end if;

    return query
    select
        t.id,
        t.area,
        t.area_label,
        t.title,
        t.syfte,
        t.output_format,
        case when has_pro then t.prompt_text else null end,
        t.tags,
        t.risk_level,
        t.security_examples,
        t.sort_order,
        has_pro
    from public.pro_prompt_templates t
    order by t.sort_order;
end;
$$;

revoke all on function public.list_pro_templates() from public;
grant execute on function public.list_pro_templates() to anon, authenticated;

-- Idempotent seed: rensa och fyll på nytt så migrationen kan köras om.
delete from public.pro_prompt_templates;

insert into public.pro_prompt_templates
    (area, area_label, title, syfte, output_format, prompt_text, tags, risk_level, security_examples, sort_order)
values
-- ============================================================
-- Kommunikation och publicering
-- ============================================================
('kommunikation', 'Kommunikation och publicering', 'Kommunikationspaket',
 'Gör ett underlag till flera publicerbara format.',
 'Webbtext, mejl, FAQ, kortversion, rubrikförslag och publiceringscheck.',
 'Du är kommunikationsstöd i en svensk kommun. Gör om underlaget till ett komplett kommunikationspaket för medarbetare, tjänstemän eller invånare.

Skapa:
1. Webbtext i klarspråk
2. Mejl (rubrik + brödtext)
3. FAQ med 5 frågor och svar
4. Kortversion (max 3 meningar)
5. Tre rubrikförslag
6. Publiceringscheck (målgrupp, datum, kontaktväg, ansvarig, personuppgifter, tillgänglighet)

Markera antaganden och kontrollpunkter tydligt. Hitta inte på fakta, datum eller siffror.

Underlag:
[klistra in här]',
 ARRAY['kommunikation','publicering','klarspråk'], 'low',
 ARRAY['Personuppgifter','Ej beslutade uppgifter','Interna systemnamn'], 1),

('kommunikation', 'Kommunikation och publicering', 'Kommunikationsrisk',
 'Granskar en text innan den skickas eller publiceras.',
 'Risker, missförstånd, saknad ansvarslinje, personuppgiftsvarning och förbättrad version.',
 'Granska texten ur ett kommunalt kommunikationsperspektiv. Du hjälper en tjänsteman eller kommunikatör att undvika missförstånd innan publicering.

Leta efter:
- Otydlighet och risk för feltolkning
- Personuppgifter eller sekretessnära information
- Saknad kontaktväg eller ansvarig funktion
- Tonproblem (för byråkratiskt, för löftesrikt, otryggt)
- Formuleringar som lovar mer än vad som är beslutat

Svara med: riskbedömning (låg/medel/hög), konkreta förbättringar och en säkrare omskriven version.

Text:
[klistra in här]',
 ARRAY['kommunikation','granskning','risk'], 'medium',
 ARRAY['Personuppgifter','Sekretessnära uppgifter','Namn på enskilda'], 2),

('kommunikation', 'Kommunikation och publicering', 'Målgruppsväxlare',
 'Skapar samma budskap för olika målgrupper.',
 'Version för invånare, medarbetare, chef/ledning och kort notis.',
 'Gör om budskapet till fyra versioner anpassade för olika kommunala målgrupper: invånare, medarbetare, chef/ledning och kort notis.

Anpassa ton, detaljnivå och ordval för varje målgrupp. Behåll samma sakinnehåll och fakta i alla versioner. Markera tydligt sådant som behöver kontrolleras innan användning.

Budskap:
[klistra in här]',
 ARRAY['kommunikation','målgrupp','anpassning'], 'low',
 ARRAY['Personuppgifter','Ej beslutade uppgifter'], 3),

('kommunikation', 'Kommunikation och publicering', 'Svårt medborgarsvar',
 'Hjälper till att svara sakligt, respektfullt och utan att lova för mycket.',
 'Svarsförslag, risker, vad som bör undvikas och nästa steg.',
 'Skriv ett sakligt och vänligt svar till en invånare i en svensk kommun. Var tydlig, låg-affektiv och respektfull.

Lova inte sådant som inte är beslutat eller som ligger utanför kommunens ansvar. Ange om frågan behöver hänvisas vidare till annan funktion eller myndighet.

Svara med:
1. Förslag till svar
2. Risker i ärendet
3. Lista med vad svaret inte bör säga
4. Nästa steg / eventuell hänvisning

Anonymisera ärendet innan du klistrar in.

Ärende:
[klistra in här]',
 ARRAY['kommunikation','medborgardialog','bemötande'], 'medium',
 ARRAY['Personnummer','Namn och adress','Uppgifter om enskildas hälsa eller ärenden'], 4),

('kommunikation', 'Kommunikation och publicering', 'Driftstörningsinformation',
 'Skapar tydlig information vid störning, avbrott eller ändrad service.',
 'Vad har hänt, påverkan, åtgärd, nästa uppdatering och kortversion.',
 'Skapa driftstörningsinformation för kommunal verksamhet (t.ex. e-tjänst, telefoni, vattenavbrott, ändrade öppettider).

Svara med:
1. Vad har hänt
2. Vilka påverkas
3. Vad görs nu
4. Vad behöver mottagaren göra
5. När kommer nästa uppdatering
6. Kortversion för SMS/sociala medier

Undvik spekulation om orsak och tidpunkt om det inte är bekräftat. Hitta inte på tider.

Underlag:
[klistra in här]',
 ARRAY['kommunikation','driftstörning','kris'], 'low',
 ARRAY['Personuppgifter','Ej bekräftade orsaker','Interna systemnamn'], 5),

('kommunikation', 'Kommunikation och publicering', 'Publiceringscheck',
 'Kontrollerar att text är redo för webb, intranät eller utskick.',
 'Checklista med status och förbättringar.',
 'Gör en publiceringscheck av texten inför publicering på webb, intranät eller i utskick.

Kontrollera: målgrupp, syfte, datum, kontaktväg, ansvarig funktion, personuppgifter, klarspråk, tillgänglighet och risk för feltolkning.

Svara i tabell med kolumnerna: Kontrollpunkt | Status (OK / Kontrollera / Saknas) | Kommentar. Avsluta med de tre viktigaste åtgärderna innan publicering.

Text:
[klistra in här]',
 ARRAY['kommunikation','publicering','kvalitetssäkring'], 'low',
 ARRAY['Personuppgifter','Sekretessnära uppgifter'], 6),

-- ============================================================
-- Förändringsledning och införande
-- ============================================================
('forandringsledning', 'Förändringsledning och införande', 'Införandeplan',
 'Går från beslut eller idé till genomförbar plan.',
 'Syfte, målgrupper, aktiviteter, ansvar, tidplan, kommunikation, utbildning, risker och uppföljning.',
 'Du är stöd för förändringsledning i en svensk kommun. Skapa en införandeplan utifrån beskriven förändring.

Inkludera: syfte, målgrupper, aktiviteter, ansvar (roll, inte namn), tidplan, kommunikation, utbildning, risker, beroenden och uppföljning.

Markera antaganden tydligt och ange vad som behöver beslutas eller förankras lokalt. Fatta inga beslut åt användaren.

Förändring:
[klistra in här]',
 ARRAY['förändringsledning','införande','plan'], 'low',
 ARRAY['Namn på enskilda medarbetare','Ej beslutade uppgifter'], 7),

('forandringsledning', 'Förändringsledning och införande', 'Intressentkarta',
 'Synliggör vilka som påverkas och hur de behöver involveras.',
 'Tabell med intressent, påverkan, behov, oro, kommunikation och ansvar.',
 'Gör en intressentkarta för förändringen i en kommunal kontext.

Lista intressenter (roller/funktioner/grupper) och för varje: hur de påverkas, deras behov, möjlig oro eller motstånd, lämpligt budskap, kommunikationskanal och ansvarig roll.

Svara i tabell. Avsluta med de tre viktigaste förankringsåtgärderna. Använd roller, inte namn på enskilda personer.

Förändring:
[klistra in här]',
 ARRAY['förändringsledning','intressenter','förankring'], 'low',
 ARRAY['Namn på enskilda','Uppgifter om enskildas inställning'], 8),

('forandringsledning', 'Förändringsledning och införande', 'Pilotdesign',
 'Utformar en avgränsad testperiod innan brett införande.',
 'Testfråga, urval, avgränsning, mätning, risker och beslutspunkt.',
 'Skapa en pilotdesign för en kommunal förändring eller ny arbetsmetod.

Beskriv: vad som ska testas, med vilka (roller/enheter), hur länge, vad som inte ingår, hur resultatet ska mätas, risker, supportbehov och beslutspunkt efter piloten.

Markera antaganden. Ge förslag på mätbara framgångskriterier.

Förslag:
[klistra in här]',
 ARRAY['förändringsledning','pilot','test'], 'low',
 ARRAY['Namn på enskilda deltagare','Ej beslutade uppgifter'], 9),

('forandringsledning', 'Förändringsledning och införande', 'Pilot eller skarp drift?',
 'Bedömer om en förändring bör testas eller införas direkt.',
 'Rekommendation, skäl, risker, krav före start och uppföljning.',
 'Bedöm om förändringen bör gå som pilot, begränsad pilot, skarp drift eller vänta.

Motivera utifrån: nytta, risk, påverkan på verksamhet och invånare, osäkerhet, stödbehov och mätbarhet. Ge tydliga krav som måste vara uppfyllda före start.

Fatta inte beslutet åt användaren – ge en motiverad rekommendation.

Förändring:
[klistra in här]',
 ARRAY['förändringsledning','beslut','pilot'], 'low',
 ARRAY['Ej beslutade uppgifter','Namn på enskilda'], 10),

('forandringsledning', 'Förändringsledning och införande', 'Förankringsplan',
 'Planerar hur förändringen ska bli förstådd och accepterad.',
 'Målgrupper, budskap, forum, tidpunkt, risker och ansvar.',
 'Skapa en förankringsplan för en kommunal förändring.

Ange vilka som behöver informeras, involveras eller besluta. Ge per målgrupp: budskap, lämpligt forum, tidpunkt, ansvarig roll och risk om förankring saknas.

Använd roller och funktioner, inte namn på enskilda personer.

Förändring:
[klistra in här]',
 ARRAY['förändringsledning','förankring','kommunikation'], 'low',
 ARRAY['Namn på enskilda','Uppgifter om enskildas inställning'], 11),

('forandringsledning', 'Förändringsledning och införande', 'Risk inför driftsättning',
 'Kontrollerar vad som måste vara klart före start.',
 'Go/no-go-lista, risker, beroenden och åtgärder.',
 'Gör en go/no-go-bedömning inför driftsättning i kommunal verksamhet.

Kontrollera: teknik, rutiner, ansvar, information, utbildning, support, dataskydd, beslut och uppföljning.

Svara med: stopprisker (no-go), bör-åtgärder innan start och en klarsignal om underlaget medger det. Markera vad som saknas för att kunna ge klarsignal.

Underlag:
[klistra in här]',
 ARRAY['förändringsledning','driftsättning','risk'], 'medium',
 ARRAY['Personuppgifter','Uppgifter om IT-säkerhet','Interna systemnamn'], 12),

-- ============================================================
-- Verksamhetsutveckling och processer
-- ============================================================
('processer', 'Verksamhetsutveckling och processer', 'Rutin till processpaket',
 'Gör en rutin användbar som process och förbättringsunderlag.',
 'Sammanfattning, Mermaid-process, ansvarstabell, checklista, risker och förbättringsförslag.',
 'Du är stöd för verksamhetsutveckling i offentlig verksamhet. Gör om rutinen till ett processpaket.

Skapa:
1. Kort sammanfattning
2. Mermaid flowchart TD över processen
3. Ansvars- och rolltabell
4. Checklista
5. Otydligheter och risker
6. Förbättringsförslag

Markera antaganden. Visa beslutspunkter som frågor i flödesschemat.

Rutin:
[klistra in här]',
 ARRAY['process','rutin','verksamhetsutveckling'], 'low',
 ARRAY['Personuppgifter','Namn på enskilda','Sekretessnära steg'], 13),

('processer', 'Verksamhetsutveckling och processer', 'Processkarta i Mermaid',
 'Visualiserar en process i Mermaid.',
 'Mermaid-kod, processbeskrivning och otydliga steg.',
 'Gör om beskrivningen till en tydlig Mermaid-process för kommunal verksamhet.

Använd flowchart TD. Visa beslutspunkter som frågor. Håll processen enkel och begriplig. Markera otydliga steg som antaganden.

Avsluta med en kort processbeskrivning i text och en lista med frågor som behöver besvaras för att processen ska bli korrekt.

Process:
[klistra in här]',
 ARRAY['process','mermaid','visualisering'], 'low',
 ARRAY['Personuppgifter','Sekretessnära steg'], 14),

('processer', 'Verksamhetsutveckling och processer', 'RACI-matris',
 'Tydliggör ansvar i ett uppdrag eller en process.',
 'Aktivitet, Responsible, Accountable, Consulted och Informed.',
 'Skapa en RACI-matris för processen eller uppdraget i en kommunal kontext.

Identifiera aktiviteter och roller. Fyll i R (Responsible), A (Accountable), C (Consulted) och I (Informed) per aktivitet. Använd roller och funktioner, inte namn på personer.

Om ansvar är oklart: markera det tydligt och föreslå vad som behöver beslutas.

Process eller uppdrag:
[klistra in här]',
 ARRAY['process','raci','ansvar'], 'low',
 ARRAY['Namn på enskilda medarbetare'], 15),

('processer', 'Verksamhetsutveckling och processer', 'Nuläge-börläge-gap',
 'Gör en förbättringsanalys av ett arbetssätt.',
 'Nuläge, börläge, gap, orsaker, åtgärder och risk om inget görs.',
 'Analysera nuläge, börläge och gap för ett kommunalt arbetssätt.

Beskriv: vad som fungerar idag, vad som skaver, önskat läge (börläge), gapet mellan dem, tänkbara orsaker, prioriterade åtgärder och risk om inget görs.

Markera antaganden och vad som behöver verifieras i verksamheten.

Underlag:
[klistra in här]',
 ARRAY['process','analys','förbättring'], 'low',
 ARRAY['Personuppgifter','Namn på enskilda'], 16),

('processer', 'Verksamhetsutveckling och processer', 'Årshjul',
 'Skapar struktur för återkommande arbete.',
 'Årshjul/tidslinje med aktiviteter, ansvar och kontrollpunkter.',
 'Skapa ett årshjul för ett återkommande kommunalt arbete (t.ex. budget, systematiskt arbetsmiljöarbete, uppföljning).

Fördela aktiviteter över året. Ange per aktivitet: ansvarig roll, syfte, beroenden och uppföljningspunkt. Markera sådant som behöver lokal anpassning.

Arbete:
[klistra in här]',
 ARRAY['process','årshjul','planering'], 'low',
 ARRAY['Namn på enskilda','Ej beslutade uppgifter'], 17),

('processer', 'Verksamhetsutveckling och processer', '5 varför',
 'Gör en enkel rotorsaksanalys.',
 'Problemformulering, varför-kedja, möjliga orsaker och åtgärder.',
 'Gör en 5 varför-analys av ett problem i kommunal verksamhet.

Börja med en tydlig problemformulering. Ställ "varför?" i fem steg, men markera osäkerheter och alternativa orsaker på vägen. Dra inte förhastade slutsatser.

Avsluta med åtgärder som angriper rotorsaker, inte bara symtom. Ange vad som behöver verifieras.

Problem:
[klistra in här]',
 ARRAY['process','rotorsak','analys'], 'low',
 ARRAY['Namn på enskilda','Uppgifter om enskildas agerande'], 18),

-- ============================================================
-- Tjänstemannastöd och beslutsberedning
-- ============================================================
('beslutsberedning', 'Tjänstemannastöd och beslutsberedning', 'Beslutsmognad',
 'Bedömer om ett ärende är redo att gå vidare.',
 'Redo/delvis redo/inte redo, saknade delar, risker och kompletteringar.',
 'Granska underlaget för beslutsmognad inför politiskt eller tjänstemannabeslut i en svensk kommun.

Bedöm: redo, delvis redo eller inte redo. Kontrollera syfte, bakgrund, alternativ, konsekvenser, ekonomi, juridik, risker, ansvar och genomförande.

Ge konkreta kompletteringsfrågor. Fatta inte beslutet – bedöm bara underlagets mognad.

Underlag:
[klistra in här]',
 ARRAY['beslut','beredning','kvalitetssäkring'], 'medium',
 ARRAY['Personuppgifter','Sekretessbelagda uppgifter','Namn på enskilda'], 19),

('beslutsberedning', 'Tjänstemannastöd och beslutsberedning', 'Saknade delar i underlag',
 'Hittar luckor i PM, tjänsteskrivelse eller förslag.',
 'Lista över saknade delar, varför de behövs och förslag på komplettering.',
 'Identifiera vad som saknas i underlaget innan det skickas vidare i en kommunal beslutsprocess.

Kontrollera: bakgrund, problem, mål, målgrupp, lagstöd, ekonomi, konsekvenser, risker, ansvar, tidsplan och uppföljning.

Svara i tabell: Del | Status (Finns / Ofullständig / Saknas) | Varför den behövs | Förslag på komplettering.

Underlag:
[klistra in här]',
 ARRAY['beslut','tjänsteskrivelse','granskning'], 'medium',
 ARRAY['Personuppgifter','Sekretessbelagda uppgifter'], 20),

('beslutsberedning', 'Tjänstemannastöd och beslutsberedning', 'Risk- och konsekvensanalys',
 'Breddar analysen inför beslut eller förändring.',
 'Nyttor, risker, konsekvenser, målgrupper, åtgärder och frågor före beslut.',
 'Gör en risk- och konsekvensanalys av förslaget i en kommunal kontext.

Beakta: verksamhet, ekonomi, personal, invånare/brukare/elever, juridik, dataskydd, arbetsmiljö och genomförbarhet.

Ange per risk: risknivå (låg/medel/hög), föreslagen åtgärd och fråga som behöver besvaras före beslut. Markera antaganden.

Förslag:
[klistra in här]',
 ARRAY['beslut','risk','konsekvens'], 'medium',
 ARRAY['Personuppgifter','Uppgifter om enskildas förhållanden','Sekretessnära uppgifter'], 21),

('beslutsberedning', 'Tjänstemannastöd och beslutsberedning', 'Alternativanalys',
 'Jämför alternativ på ett beslutsbart sätt.',
 'Jämförelsetabell, för- och nackdelar, risker och rekommenderad väg framåt.',
 'Jämför alternativen på ett beslutsbart sätt inför ett kommunalt beslut.

Bedöm per alternativ: nytta, kostnad, risk, genomförbarhet, påverkan, tid och konsekvenser om inget görs. Svara i jämförelsetabell och komplettera med för- och nackdelar.

Markera antaganden och vilka fakta som behöver kontrolleras. Ge en motiverad rekommendation men fatta inte beslutet.

Alternativ:
[klistra in här]',
 ARRAY['beslut','alternativ','analys'], 'low',
 ARRAY['Personuppgifter','Sekretessnära uppgifter'], 22),

('beslutsberedning', 'Tjänstemannastöd och beslutsberedning', 'Förslag till beslut',
 'Formulerar en tydlig beslutsmening utan att överta ansvar.',
 'Beslutsformuleringar, villkor och kontrollfrågor.',
 'Hjälp till att formulera förslag till beslut utifrån underlaget, i en svensk kommunal kontext.

Utgå från underlaget men fatta inte beslutet åt användaren. Ge 2–3 alternativa beslutsformuleringar, ange eventuella villkor och kontrollfrågor som bör besvaras innan formuleringen används.

Använd tydligt och korrekt förvaltningsspråk.

Underlag:
[klistra in här]',
 ARRAY['beslut','formulering','beredning'], 'medium',
 ARRAY['Personuppgifter','Sekretessbelagda uppgifter','Namn på enskilda'], 23),

('beslutsberedning', 'Tjänstemannastöd och beslutsberedning', 'Genomförandeplan efter beslut',
 'Gör beslut till aktiviteter och ansvar.',
 'Aktiviteter, ansvar, tidsplan, kommunikation, risker och uppföljning.',
 'Gör om beslutet till en genomförandeplan i kommunal verksamhet.

Lista: aktiviteter, ansvarig roll, deadline, beroenden, kommunikation, risker och uppföljning. Markera vad som kräver ytterligare beslut eller mandat.

Använd roller och funktioner, inte namn på enskilda personer.

Beslut:
[klistra in här]',
 ARRAY['beslut','genomförande','plan'], 'low',
 ARRAY['Namn på enskilda','Ej beslutade uppgifter'], 24),

-- ============================================================
-- Visuellt stöd och informationsbilder
-- ============================================================
('visuellt', 'Visuellt stöd och informationsbilder', 'Gör detta visuellt',
 'Väljer lämplig visuell form för ett underlag.',
 'Förslag på infografik, processbild, ikonrad, tidslinje eller informationsbild.',
 'Analysera underlaget och föreslå bästa visuella form för kommunal information: infografik, processbild, tidslinje, ikonrad, jämförelse eller informationsbild.

Ge: rekommenderad form med motivering, rubrik, struktur, bildprompt, textförslag och alt-text. Undvik onödiga personer och barn i bilden. Rekommendera att siffror och text läggs in manuellt om korrekthet är viktig.

Underlag:
[klistra in här]',
 ARRAY['visuellt','infografik','val'], 'low',
 ARRAY['Personuppgifter','Igenkännbara personer','Verkliga logotyper'], 25),

('visuellt', 'Visuellt stöd och informationsbilder', 'Infografik-generator',
 'Gör fakta eller process till en enkel informationsgrafik.',
 'Layout, rubriker, ikonidéer, bildprompt och alt-text.',
 'Skapa ett förslag till infografik för kommunal information.

Ge: huvudrubrik, 3–6 steg/punkter, kort text per punkt, ikonidéer, layoutförslag, bildprompt och alt-text.

Undvik onödiga personer och barn. Hitta inte på siffror. Rekommendera att text och siffror läggs in manuellt i Canva/PowerPoint om korrekthet är viktig.

Underlag:
[klistra in här]',
 ARRAY['visuellt','infografik','information'], 'low',
 ARRAY['Personuppgifter','Felaktiga siffror','Verkliga logotyper'], 26),

('visuellt', 'Visuellt stöd och informationsbilder', 'Process till bild',
 'Gör en process mer begriplig visuellt.',
 'Processbildidé, Mermaid, ikonförslag och alt-text.',
 'Gör processen visuell för kommunal användning.

Skapa först en enkel Mermaid flowchart TD. Ge sedan: förslag på processbild eller ikonrad, rubrik, kort förklaring och alt-text. Markera otydliga steg som antaganden.

Undvik onödiga personer i bilden.

Process:
[klistra in här]',
 ARRAY['visuellt','process','mermaid'], 'low',
 ARRAY['Personuppgifter','Sekretessnära steg','Igenkännbara personer'], 27),

('visuellt', 'Visuellt stöd och informationsbilder', 'Ikon- och symbolbild',
 'Skapar neutrala visuella idéer för kommunala ämnen.',
 'Ikonprompt, stil, användningsråd och alt-text.',
 'Skapa en neutral ikon- eller symbolbild för kommunal användning.

Undvik stereotyper, känsliga personuppgifter och onödiga ansikten. Undvik verkliga logotyper och myndighetssymboler som inte är godkända.

Ge: bildprompt, stil, format, användningsråd och alt-text.

Ämne:
[klistra in här]',
 ARRAY['visuellt','ikon','symbol'], 'low',
 ARRAY['Myndighetssymboler','Partipolitiska symboler','Varumärkesliknande symboler'], 28),

('visuellt', 'Visuellt stöd och informationsbilder', 'Bildprompt-granskare',
 'Kvalitetssäkrar bildprompts innan användning.',
 'Tydlighetsbedömning, risker, förbättrad prompt och alt-text.',
 'Granska bildprompten för kommunal användning.

Bedöm: tydlighet, neutralitet, risk för stereotyper, offentlig användbarhet, tillgänglighet och risk kopplad till personer och barn.

Ge: bedömning, identifierade risker, en förbättrad bildprompt och förslag på alt-text.

Bildprompt:
[klistra in här]',
 ARRAY['visuellt','granskning','bildprompt'], 'low',
 ARRAY['Igenkännbara personer','Känsliga situationer','Verkliga logotyper'], 29),

('visuellt', 'Visuellt stöd och informationsbilder', 'Alt-text Pro',
 'Skapar tillgänglig bildbeskrivning och publiceringsråd.',
 'Kort alt-text, lång beskrivning, bildtext och råd.',
 'Skapa tillgänglig beskrivning av bilden eller bildidén enligt tillgänglighetskrav för offentlig sektor (WCAG/DOS-lagen).

Ge: kort alt-text (max ca 140 tecken), längre beskrivning om bilden är informationsbärande, föreslagen bildtext, risker för feltolkning och råd om bilden bör användas.

Gissa inte identitet, känslor eller relationer. Beskriv relevant innehåll, inte allt.

Bild eller bildidé:
[klistra in här]',
 ARRAY['visuellt','tillgänglighet','alt-text'], 'low',
 ARRAY['Personuppgifter i bild','Känslig information','Ogrundade tolkningar'], 30),

-- ============================================================
-- Ledarskap och styrning
-- ============================================================
('ledarskap', 'Ledarskap och styrning', 'Från möte till uppföljning',
 'Gör mötesanteckningar till ansvar och nästa steg.',
 'Beslut, ansvar, öppna frågor, risker, uppföljningsmejl och checklista.',
 'Gör om mötesanteckningarna till en tydlig uppföljning för en kommunal chef eller samordnare.

Ta ut: beslut, ansvariga (roller), deadlines, öppna frågor, risker och beroenden. Skapa även ett kort uppföljningsmejl och en checklista till nästa möte.

Hitta inte på beslut som inte framgår. Anonymisera känsliga personuppgifter.

Anteckningar:
[klistra in här]',
 ARRAY['ledarskap','möte','uppföljning'], 'medium',
 ARRAY['Namn på enskilda','Uppgifter om personalärenden','Sekretessnära uppgifter'], 31),

('ledarskap', 'Ledarskap och styrning', 'Tydlig uppdragsformulering',
 'Hjälper chef eller samordnare formulera tydligt uppdrag.',
 'Uppdrag, syfte, mål, avgränsning, ansvar, leverans och uppföljning.',
 'Formulera ett tydligt uppdrag i en kommunal kontext.

Inkludera: syfte, bakgrund, mål, avgränsning, ansvar, mandat, leverans, deadline, uppföljning och vad som inte ingår.

Använd roller och funktioner. Markera vad som behöver beslutas eller förtydligas av uppdragsgivaren.

Uppdrag eller idé:
[klistra in här]',
 ARRAY['ledarskap','uppdrag','styrning'], 'low',
 ARRAY['Namn på enskilda','Ej beslutade uppgifter'], 32),

('ledarskap', 'Ledarskap och styrning', 'Prioriteringsstöd',
 'Sorterar initiativ utifrån nytta, risk och genomförbarhet.',
 'Prioriteringsmatris, rekommendation och vad som kan pausas.',
 'Prioritera följande initiativ i en kommunal verksamhet.

Bedöm per initiativ: nytta, brådska, risk, resursbehov, genomförbarhet och beroenden. Föreslå vad som bör göras nu, senare, pausas eller kräver beslut.

Svara i prioriteringsmatris och ge en kort motiverad rekommendation. Markera antaganden.

Initiativ:
[klistra in här]',
 ARRAY['ledarskap','prioritering','styrning'], 'low',
 ARRAY['Namn på enskilda','Ej beslutade uppgifter'], 33),

('ledarskap', 'Ledarskap och styrning', 'Svårt samtal-förberedare',
 'Ger struktur inför ett svårt eller känsligt samtal.',
 'Syfte, budskap, frågor, möjliga reaktioner, undvik och uppföljning.',
 'Hjälp mig förbereda ett svårt eller känsligt samtal som chef/samordnare i kommunal verksamhet.

Ge struktur: syfte, sakligt huvudbudskap, frågor att ställa, möjliga reaktioner, formuleringar att undvika och uppföljning.

Ge inte juridiska beslut, medicinska bedömningar eller terapi. Detta är ett förberedelsestöd – ansvaret för samtalet ligger hos chefen. Beskriv situationen anonymiserat.

Situation:
[klistra in här]',
 ARRAY['ledarskap','samtal','medarbetare'], 'high',
 ARRAY['Namn på enskilda','Uppgifter om hälsa','Personalärenden och arbetsrätt'], 34),

('ledarskap', 'Ledarskap och styrning', 'Ledningsgruppsförberedare',
 'Förbereder en fråga inför ledningsgrupp.',
 'Syfte, beslut/dialog, agenda, frågor, risker och saknat underlag.',
 'Förbered denna fråga inför en kommunal ledningsgrupp.

Ange: varför frågan tas upp, om syftet är beslut/dialog/information, vad gruppen ska ta ställning till, förslag på agendapunkt, frågor till gruppen och vilket underlag som saknas.

Håll det sakligt och beslutsinriktat. Markera antaganden.

Fråga:
[klistra in här]',
 ARRAY['ledarskap','ledningsgrupp','beredning'], 'low',
 ARRAY['Personuppgifter','Sekretessnära uppgifter','Namn på enskilda'], 35),

('ledarskap', 'Ledarskap och styrning', 'Lägesbild',
 'Sammanfattar nuläge, risker och nästa steg.',
 'Kort lägesbild, risker, beroenden, beslut och nästa steg.',
 'Skapa en lägesbild för en kommunal chef eller ledningsgrupp.

Sammanfatta: nuläge, vad som fungerar, problem, risker, beroenden, beslut som behövs och nästa steg. Håll det kort och sakligt.

Hitta inte på status eller siffror. Markera vad som är osäkert.

Underlag:
[klistra in här]',
 ARRAY['ledarskap','lägesbild','uppföljning'], 'low',
 ARRAY['Personuppgifter','Sekretessnära uppgifter'], 36),

-- ============================================================
-- Pro-verktyg för egen AI-arbetsbank
-- ============================================================
('arbetsbank', 'Pro-verktyg för egen AI-arbetsbank', 'Skapa egen AI-mall',
 'Gör ett behov till komplett Promptbanken-mall.',
 'Titel, kategori, risknivå, prompt, outputformat, kontrollfrågor och taggar.',
 'Skapa en komplett Promptbanken-mall utifrån behovet, anpassad för svensk kommunal verksamhet.

Inkludera: titel, beskrivning, område, målgrupp, risknivå (låg/medel/hög), anonymiseringsråd, när mallen passar, "använd inte till", själva prompten, outputformat, kontroll före användning, exempelinput och taggar.

Bygg in ansvar, personuppgiftshänsyn och mänsklig granskning i mallen.

Behov:
[klistra in här]',
 ARRAY['arbetsbank','mall','egen'], 'low',
 ARRAY['Personuppgifter','Verksamhetsspecifika sekretessuppgifter'], 37),

('arbetsbank', 'Pro-verktyg för egen AI-arbetsbank', 'Förbättra prompt',
 'Gör en befintlig prompt tydligare och säkrare.',
 'Bedömning, brister, förbättrad prompt, risknivå och outputformat.',
 'Granska och förbättra prompten för användning i svensk kommunal verksamhet.

Bedöm: tydlighet, kontext, målgrupp, outputformat, risk, personuppgifter och kontrollbehov. Peka ut konkreta brister.

Svara med en förbättrad version i Promptbanken-format med angiven risknivå och outputformat.

Prompt:
[klistra in här]',
 ARRAY['arbetsbank','förbättring','prompt'], 'low',
 ARRAY['Personuppgifter i exempeltext'], 38),

('arbetsbank', 'Pro-verktyg för egen AI-arbetsbank', 'Gör prompten kommunal',
 'Anpassar en generell prompt från nätet till offentlig verksamhet.',
 'Kommunal version med ansvar, risk, klarspråk och kontroll.',
 'Gör om prompten till en kommunal, riskmedveten AI-mall för svensk offentlig sektor.

Lägg till: klarspråk, ansvar, personuppgiftsrisk, begränsningar, krav på mänsklig granskning och tydligt outputformat. Ta bort sådant som inte passar offentlig verksamhet eller som riskerar att flytta ansvar från handläggaren.

Prompt:
[klistra in här]',
 ARRAY['arbetsbank','anpassning','kommunal'], 'low',
 ARRAY['Personuppgifter i exempeltext'], 39),

('arbetsbank', 'Pro-verktyg för egen AI-arbetsbank', 'Paketera som mall',
 'Sparar ett lyckat flöde som återanvändbar mall.',
 'Mallnamn, beskrivning, prompt, metadata, outputformat och taggar.',
 'Paketera detta resultat eller arbetssätt som en återanvändbar Promptbanken-mall för kommunal verksamhet.

Identifiera: syfte, input, steg, outputformat, risknivå, anonymiseringsråd, kontrollfrågor och taggar. Ge ett tydligt mallnamn och en kort beskrivning.

Resultat eller flöde:
[klistra in här]',
 ARRAY['arbetsbank','mall','återanvändning'], 'low',
 ARRAY['Personuppgifter i exempeltext','Verksamhetsspecifika uppgifter'], 40),

('arbetsbank', 'Pro-verktyg för egen AI-arbetsbank', 'Kontroll före användning',
 'Sista kvalitetsgranskning innan text, process eller underlag används.',
 'Risker, kontrollpunkter, saknade fakta och förbättringar.',
 'Gör en kontroll före användning av underlaget i kommunal verksamhet.

Kontrollera: personuppgifter, sekretess, fakta, antaganden, ansvar, datum, beslut, målgrupp, ton, risk för feltolkning och behov av mänsklig granskning.

Svara med: identifierade risker, kontrollpunkter, saknade fakta och konkreta förbättringar. Ge en tydlig rekommendation om underlaget kan användas som det är.

Underlag:
[klistra in här]',
 ARRAY['arbetsbank','kvalitetssäkring','kontroll'], 'medium',
 ARRAY['Personuppgifter','Sekretessbelagda uppgifter','Namn på enskilda'], 41),

('arbetsbank', 'Pro-verktyg för egen AI-arbetsbank', 'Bygg arbetsflöde',
 'Sätter ihop flera mallar till ett guidat arbetsflöde.',
 'Steg, mallar, input/output per steg, kontrollpunkter och sparbar struktur.',
 'Bygg ett arbetsflöde av flera AI-mallar för en kommunal arbetsuppgift.

Ange: syfte, steg i ordning, input per steg, output per steg, kontrollpunkter och vad som kan sparas som återanvändbar mall. Bygg in mänsklig granskning mellan stegen där det behövs.

Arbetsuppgift:
[klistra in här]',
 ARRAY['arbetsbank','arbetsflöde','automation'], 'low',
 ARRAY['Personuppgifter','Verksamhetsspecifika sekretessuppgifter'], 42);
