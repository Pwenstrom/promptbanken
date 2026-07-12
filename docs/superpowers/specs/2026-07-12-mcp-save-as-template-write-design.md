# MCP write: "Spara detta som mall" (save_workspace_prompt)

## Syfte

Låta en användare i en pågående AI-chatt (Claude, ChatGPT, Copilot eller annan MCP-klient) be modellen "spara det här som en mall" och få en generaliserad, GDPR-kontrollerad prompt sparad i sin egen personliga Pro-arbetsyta i Promptbanken — utan att lämna chatten. Detta är den lokala MCP-serverns (`promptbanken/mcp-server/server/`) första write-funktion; servern har hittills bara varit läsning.

Gated till nycklar med `plan = 'pro'`. Free-nycklar kan inte skriva via MCP i denna version.

## Bakgrund

All skrivning till `content_items` sker idag via den inloggade webb-frontend (`admin.js`), skyddad av RLS-policyer och triggern `app_private.enforce_content_access_model()` som är hårt knuten till `auth.uid()` (kräver en riktig inloggad Supabase-session). MCP-anrop har ingen sådan session — bara en `X-MCP-Key`/nyckelhash, verifierad via `app_private.verify_mcp_key(p_key_hash)`. Läs-sidans RPC:er (`get_pro_templates_for_mcp_key`, `get_workspace_prompts_for_key`) löser detta genom att vara egna SECURITY DEFINER-funktioner som litar på nyckelhashen istället för `auth.uid()`. Write-funktionen behöver samma förtroendeväxling, men måste dessutom passera den befintliga INSERT-triggern på `content_items` utan att försvaga den för webbflödet.

Servern kör aldrig någon egen AI-modell (uttalad avgränsning i `mcp_promptbanken/PROJECT.md`, gäller samma princip här). Generalisering av innehåll (ta bort namn/personnummer/org-specifika detaljer, ersätta med platshållare, föreslå titel/kategori) och godkännande-steget sker alltså helt på klientmodellens sida (Claude/ChatGPT/Copilot) innan den anropar write-verktyget — servern kan inte tekniskt verifiera att en människa faktiskt godkänt något i en annan klients gränssnitt. Detta är en medveten designbegränsning, inte ett hål: samma modell som redan litar på klienten för `compile_skill_prompt`/`check_input_risk`-flödet.

## Flöde

1. Användaren ber klientmodellen spara chatten/instruktionen som mall.
2. Klientmodellen (inte servern) generaliserar innehållet: tar bort namn/personnummer/org-specifika detaljer, ersätter med platshållare, föreslår titel + kategori (se Kategorisering för förslagslistan).
3. Klientmodellen visar förslaget för användaren och väntar på godkännande — detta styrs av verktygets beskrivningstext, inte av server-logik.
4. Klientmodellen anropar det befintliga verktyget `check_input_risk` på den genererade mallen (inte råchatten).
5. Om `check_input_risk` flaggar risk: klientmodellen visar vad som flaggades, användaren redigerar eller avbryter. Ingen serverspärr — `RiskChecker` varnar redan idag, blockerar aldrig (oförändrat beteende).
6. Vid godkännande anropar klientmodellen det nya verktyget `save_workspace_prompt(title, content, category, source, risk_check_passed, idempotency_key)` med samma `X-MCP-Key`/env-nyckel som redan används för läsning. `risk_check_passed` sätts till `true` av klientmodellen efter steg 4–5.
7. Servern validerar nyckel, plan, innehåll och risk-flaggan, skriver posten (eller returnerar en redan existerande post vid idempotent retry), returnerar resultat till klientmodellen som visar det för användaren.

Inget mellanlagrat "förslag" hålls kvar på servern mellan steg 3 och 6 — ett enda write-anrop, ingen sessionstate.

## RPC-design

Ny SECURITY DEFINER-funktion i `promptbanken`-repots Supabase-schema:

```sql
create or replace function app_private.save_prompt_for_key(
    p_key_hash text,
    p_title text,
    p_content text,
    p_category text,
    p_source text default 'manual',
    p_risk_check_passed boolean default false,
    p_idempotency_key uuid default null
) returns public.content_items
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
...
$$;
```

`set search_path = public, app_private, pg_temp` är obligatoriskt på funktionen (saknades i första utkastet). Utan pinnad `search_path` kan en SECURITY DEFINER-funktion luras att köra ett skadligt objekt om någon skapar ett schema/funktion/tabell med samma namn tidigare i en ohärdad sökväg — standardriskerna för SECURITY DEFINER i Postgres. Samma mönster bör även efterhandsverifieras på de befintliga läs-RPC:erna (`get_pro_templates_for_mcp_key`, `get_workspace_prompts_for_key`, `list_shared_workspaces_for_key`) som en separat, liten uppstädning — utanför scope för denna spec men värt en egen TODO-rad.

**Förtroendeväxling utan att ändra befintlig trigger:** funktionen slår upp `workspace_id`/`owner_user_id`/`plan` via samma väg som `verify_mcp_key` redan använder, avvisar om `plan <> 'pro'` eller nyckeln är ogiltig/återkallad. Innan INSERT sätts en transaktionslokal session-inställning:

```sql
perform set_config('request.jwt.claim.sub', owner_user_id::text, true);
```

`auth.uid()` läser just denna inställning (Supabase/PostgREST-konvention). Eftersom `set_config(..., true)` bara gäller den aktuella transaktionen, och funktionen är SECURITY DEFINER (bara exekverbar av `anon` som en hel, redan validerad enhet — ingen klient kan sätta detta värde själv utan att gå via funktionen), ser den redan existerande triggern `enforce_content_access_model()` ett giltigt `auth.uid()` som matchar `created_by`/`owner_user_id`. Alla befintliga regler (max_prompts-gräns, visibility-regler för personal/pro-workspace, publik-spärr) återanvänds **oförändrade** — ingen duplicerad valideringslogik i den nya funktionen.

Insert-värden: `workspace_id` (från nyckeln), `type='prompt'`, `title`, `content`, `category`, `visibility='private'` (låst — write-verktyget skriver aldrig `workspace`/`public`, se Skopning), `status='draft'`, `created_by`/`owner_user_id` = `owner_user_id`, `source`, `idempotency_key`.

**Ny kolumn:** `content_items.source text not null default 'manual' check (source in ('manual', 'chat_extraction'))`. Ren metadata, påverkar ingen befintlig rad (default `'manual'`).

Grant: `execute on function app_private.save_prompt_for_key to anon` — samma förtroendemodell som `get_pro_templates_for_mcp_key`/`get_workspace_prompts_for_key` (nyckelhashen är beviset på behörighet, ingen ytterligare Postgres-roll behövs).

### Valideringsordning i funktionen (varje steg loggar ett försök, se Loggning)

1. Nyckel giltig? Nej → logga `invalid_key`, avvisa.
2. `plan = 'pro'`? Nej → logga `not_pro`, avvisa.
3. Rate limit inte nådd (se Rate limiting)? Nej → logga `rate_limited`, avvisa.
4. `p_title`/`p_content` giltiga (se Innehållsvalidering)? Nej → logga `invalid_input`, avvisa.
5. `p_idempotency_key` angiven och matchar en befintlig rad i samma workspace? Ja → logga `idempotent_hit`, returnera den befintliga raden utan ny INSERT.
6. `p_risk_check_passed = false`? Ja → logga `risk_check_not_passed`, avvisa med tydligt fel ("kör check_input_risk och sätt risk_check_passed=true efter godkännande").
7. INSERT (triggern `enforce_content_access_model` körs, kan fortfarande avvisa på `max_prompts`-gräns — logga `limit_reached` i det fallet).
8. Lyckad INSERT → logga `success`.

## Säkerhet

### search_path

Se RPC-design ovan — `set search_path = public, app_private, pg_temp` pinnat explicit på funktionen.

### Rate limiting

Ingen generell rate limit finns idag på `verify_mcp_key`-vägen (verifierat: inget i migrationerna). Write är dyrare att missbruka än läsning (skriver till disk, kan fylla `max_prompts` snabbt), så en egen, enkel gräns läggs direkt på skrivfunktionen snarare än att vänta på en generell lösning:

- Gräns: max 10 write-försök per nyckel per 60 sekunder (konstant i funktionen, lätt att justera senare).
- Implementeras genom att räkna rader i den nya `mcp_write_attempts`-tabellen (se Loggning) för samma `key_hash` de senaste 60 sekunderna, innan något annat görs.
- Vid överskriden gräns: avvisa med tydligt fel, logga själva rate-limit-träffen också (annars syns inte missbruksmönstret).

### Innehållsvalidering

Servern litar inte på att klientmodellen skickar rimligt innehåll:

- `p_title`: `trim(p_title) <> ''` och längd ≤ 200 tecken.
- `p_content`: `trim(p_content) <> ''` och längd ≤ 20 000 tecken (gott om utrymme för en genererad mall, stoppar grovt felaktiga/oändliga payloads).
- `p_category`: `trim(p_category) <> ''` (ingen längdgräns utöver rimlig, t.ex. ≤ 100 tecken).

Brott mot något av detta → `raise exception` med tydligt svenskt felmeddelande, loggas som `invalid_input`.

## Idempotens

`p_idempotency_key uuid` (valfri parameter, klientmodellen genererar en gång per godkännande-tillfälle och återanvänder vid ev. retry). Ny kolumn:

```sql
alter table public.content_items
    add column if not exists idempotency_key uuid;

create unique index if not exists content_items_idempotency_key_per_workspace
    on public.content_items (workspace_id, idempotency_key)
    where idempotency_key is not null;
```

Om samma `(workspace_id, idempotency_key)` redan finns: funktionen returnerar den befintliga raden istället för att försöka en ny INSERT (och istället för att krascha på unique-constraint-fel). Löser dubbletter vid timeout/retry helt, utan semantisk innehållsjämförelse. Ingen exakt titel/kategori-varning i v1 (oförändrat beslut, se Dubblettkontroll).

## Risk-check-parameter

`p_risk_check_passed boolean default false` är obligatorisk att sätta till `true` av klientmodellen efter att `check_input_risk` körts och användaren godkänt. Servern kan inte verifiera att detta faktiskt stämmer (klientmodellen kan sätta `true` utan att ha kört checken) — men:

- Standardvärdet är `false`, så ett anrop som "glömmer" parametern avvisas tydligt istället för att tyst lyckas.
- Varje anrop loggas med sitt `risk_check_passed`-värde i `mcp_write_attempts`, så ett mönster av avsiktligt kringgående (alltid `true` utan att modellen rimligen hunnit köra en check, eller ett osedvanligt högt antal `risk_check_not_passed`-avslag) blir synligt i efterhand — även om enskilda lögner inte går att upptäcka.

Detta gör kringgående synligt snarare än omöjligt, vilket är den rimliga nivån givet att servern aldrig kan se vad som faktiskt hände i klientens gränssnitt.

## Loggning / observability

Ny tabell, delad mellan rate limiting och drift-observability (samma skrivning täcker båda behoven):

```sql
create table if not exists app_private.mcp_write_attempts (
    id bigint generated always as identity primary key,
    key_hash text not null,
    workspace_id uuid,
    outcome text not null,
    -- 'success' | 'invalid_key' | 'not_pro' | 'rate_limited' | 'invalid_input'
    -- | 'risk_check_not_passed' | 'limit_reached' | 'idempotent_hit'
    risk_check_passed boolean,
    created_at timestamptz not null default now()
);

create index if not exists mcp_write_attempts_key_hash_created_at
    on app_private.mcp_write_attempts (key_hash, created_at desc);
```

Ingen prompttext lagras i loggtabellen — bara nyckelhash, workspace, utfall, tidsstämpel. Ger underlag för att i efterhand se missbruksmönster (t.ex. många `rate_limited`) och UX-friktion (t.ex. många `not_pro` kan vara ett uppgraderings-signal värt att titta på separat, inget som byggs i v1). Ingen automatisk radering/retention-policy definierad i v1 — TODO för senare om tabellen växer stort.

## Reversibilitet / rollback

Repot har ingen down-migration-konvention idag (verifierat: inga `*_down.sql`-filer finns). Istället för att införa ett nytt mönster ensamt för denna migration dokumenteras manuell rollback-SQL här, att köras för hand om funktionen behöver stängas av snabbt efter lansering (t.ex. om ett säkerhetshål upptäcks):

```sql
revoke execute on function app_private.save_prompt_for_key(text, text, text, text, text, boolean, uuid) from anon;
-- Stänger av write omedelbart utan att röra data. Funktionen/kolumnerna/loggtabellen
-- kan tas bort helt i en separat migration när/om beslutet är permanent:
-- drop function if exists app_private.save_prompt_for_key(text, text, text, text, text, boolean, uuid);
-- drop table if exists app_private.mcp_write_attempts;
-- alter table public.content_items drop column if exists idempotency_key;
-- alter table public.content_items drop column if exists source;
```

`revoke execute ... from anon` är den snabba nödbromsen (en rad, ingen schemaändring). Fullständig borttagning är ett medvetet separat steg, inte automatiskt.

## Skopning / permissions

Låst till egen personlig Pro-arbetsyta i v1. `visibility` hårdkodas till `'private'` i funktionen — klienten kan inte skicka in ett annat värde. Delning till `shared_workspace_addons` är explicit utanför scope denna version; kan läggas till senare (t.ex. ett `p_workspace_id`-parameter som gör samma medlemskaps-/rollkontroll som `get_workspace_prompts_for_key` redan gör) utan att ändra kontraktet för v1-anrop.

## Kategorisering

`category` är fritext i databasen (`content_items.category text`, ingen enum) — klientmodellen kan skicka valfri sträng, ingen servervalidering av kategorival utöver Innehållsvalidering ovan (icke-tom).

Verktygsbeskrivningen för `save_workspace_prompt` innehåller en icke-bindande förslagslista att normalisera mot, återanvänder samma sju områden som redan används för Pro-premiummallarna (`pro_prompt_templates`): kommunikation, förändringsledning, processer, beslutsberedning, visuellt, ledarskap, arbetsbank. Klientmodellen föreslår kategori utifrån denna lista eller egen fritext, användaren kan ändra fritt innan godkännande. Ingen confidence-tröskel eller låst enum i v1 — det fanns aldrig i den faktiska databasen, bara en plan för Free-låsning till en fast standardkategori (separat, obyggd TODO-punkt, orört av denna design).

## Dubblettkontroll

Ingen exakt titel/kategori-varning i v1 (oförändrat beslut). Idempotensnyckeln (se ovan) löser den tekniska dubblett-risken vid timeout/retry, vilket var den mest konkreta delen av det ursprungliga dubblettbehovet. Semantisk likhetsdetektering kvarstår explicit utanför scope.

## Felrapportering vid missad GDPR-risk

Ingen separat rapporteringsväg i v1. Användaren äger raden och kan redigera/radera den direkt i `admin.html` (befintlig funktionalitet) om `check_input_risk` missade något känsligt.

## Telemetri

`source` (`manual` | `chat_extraction`) sparas som vanlig kolumn på raden — ingen extra loggning eller skuggkopia av chattinnehåll. Klientmodellen sätter `source='chat_extraction'` när anropet kommer från "spara som mall"-flödet; `manual` är standard för framtida andra anropsvägar. Se även Loggning ovan för anropsnivå-observability (separat från denna per-rad-metadata).

## Kodändringar

### `promptbanken/supabase/migrations/`

Ny migration (t.ex. `20260712100000_save_prompt_for_key.sql`):
- `alter table public.content_items add column if not exists source text not null default 'manual' check (source in ('manual', 'chat_extraction'));`
- `alter table public.content_items add column if not exists idempotency_key uuid;`
- `create unique index if not exists content_items_idempotency_key_per_workspace on public.content_items (workspace_id, idempotency_key) where idempotency_key is not null;`
- `create table if not exists app_private.mcp_write_attempts (...)` enligt Loggning ovan.
- `create or replace function app_private.save_prompt_for_key(...)` enligt RPC-designen ovan, inklusive pinnad `search_path`, rate limiting, innehållsvalidering, idempotens- och risk-check-hantering.
- `grant execute on function app_private.save_prompt_for_key(text, text, text, text, text, boolean, uuid) to anon;`

Rollback-SQL för denna migration dokumenteras i Reversibilitet-avsnittet ovan (ingen down-migration-fil, matchar repots befintliga mönster).

### `promptbanken/mcp-server/server/pro_templates.py` (eller ny modul, t.ex. `write_tools.py`)

Ny metod på samma klientmönster som `ProTemplatesClient` (stdlib `urllib`, samma `_call_rpc`-hjälpare, samma `p_key_hash`-payload):

```python
def save_prompt(
    self,
    title: str,
    content: str,
    category: str,
    source: str = "manual",
    risk_check_passed: bool = False,
    idempotency_key: str | None = None,
) -> dict[str, Any]:
    return self._call_rpc("save_prompt_for_key", {
        "p_title": title,
        "p_content": content,
        "p_category": category,
        "p_source": source,
        "p_risk_check_passed": risk_check_passed,
        "p_idempotency_key": idempotency_key,
    })
```

RPC-fel (t.ex. "inte Pro", "gräns nådd", "för många försök", "risk-check inte godkänd") kommer som ett `HTTPError` från PostgREST — samma mönster som `_call_rpc` redan hanterar, omvandlas till ett läsbart `RuntimeError`. Verktygsfunktionen i `mcp_server.py` fångar detta och returnerar ett strukturerat felobjekt (`{"status": "error", "message": ...}`) istället för att låta undantaget krascha MCP-anropet, så att klientmodellen kan visa felet för användaren.

### `promptbanken/mcp-server/server/mcp_server.py`

Nytt `@mcp.tool()`:

```python
@mcp.tool()
def save_workspace_prompt(
    title: str,
    content: str,
    category: str,
    source: str = "manual",
    risk_check_passed: bool = False,
    idempotency_key: str | None = None,
) -> dict[str, Any]:
    """Spara en genererad, redan GDPR-granskad mall i användarens Pro-arbetsyta.
    VIKTIGT för anropande modell: generalisera innehållet (ta bort namn/personnummer/
    org-specifika detaljer) och kör check_input_risk på den genererade mallen INNAN
    detta verktyg anropas. Visa förslaget för användaren och invänta uttryckligt
    godkännande före anrop. Sätt risk_check_passed=true först efter godkänd check —
    anrop med risk_check_passed=false avvisas. Generera ett eget idempotency_key (UUID)
    per godkännande-tillfälle för att säkert kunna göra om anropet vid timeout utan att
    skapa en dubblett. Förslag på kategori (valfritt, ingen tvingad lista): kommunikation,
    förändringsledning, processer, beslutsberedning, visuellt, ledarskap, arbetsbank.
    Kräver en Pro-nyckel (PROMPTBANKEN_MCP_KEY); free-nycklar avvisas."""
    ...
```

Verktygsbeskrivningen är den enda platsen där godkännande-kravet uttrycks — bär hela ansvaret för att klientmodeller (Claude/ChatGPT/Copilot) följer flödet, eftersom servern inte kan tvinga fram det tekniskt. `risk_check_passed`-parametern gör avsiktligt kringgående synligt i loggen (se Risk-check-parameter), inte omöjligt.

### Ej berört

- `mcp_promptbanken` (hostade repot) — ingen write där, oförändrad read-only-gräns.
- `check_input_risk`, `RiskChecker` — återanvänds oförändrade.
- `enforce_content_access_model()`-triggern — återanvänds helt oförändrad, bara ett nytt sätt att nå fram till ett giltigt `auth.uid()`.
- `admin.html`/`admin.js` — ingen UI-ändring krävs, raden dyker upp under befintliga "Mina prompts" som vilken annan prompt som helst (status `draft`).

## Testplan

Manuell verifiering (matchar befintligt mönster i repot, inga automatiserade tester):

1. `ast.parse` på ändrade Python-filer.
2. `python -c`-skript: anropa `save_prompt` med en påhittad/ogiltig nyckel → tydligt fel, ingen krasch, en `invalid_key`-rad i `mcp_write_attempts`.
3. Mot staging: skapa en riktig Pro-testnyckel, anropa `save_workspace_prompt` (med `risk_check_passed=true`) via MCP JSON-RPC → verifiera att raden dyker upp i `content_items` med rätt `workspace_id`/`owner_user_id`/`visibility='private'`/`status='draft'`/`source`, och en `success`-rad i loggtabellen.
4. Samma anrop med en Free-nyckel → avvisas med tydligt planfel, ingen rad skapas, `not_pro` loggat.
5. Anrop med `risk_check_passed=false` (eller utelämnad) → avvisas, `risk_check_not_passed` loggat.
6. Anrop med tom `title`/extremt lång `content` → avvisas, `invalid_input` loggat.
7. Samma `idempotency_key` två gånger i rad → första gången skapar raden, andra gången returnerar samma rad utan ny INSERT eller fel, `idempotent_hit` loggat.
8. 11 anrop inom 60 sekunder med samma nyckel → det 11:e avvisas med rate-limit-fel, `rate_limited` loggat.
9. Fyll en test-arbetsyta till `max_prompts`-gränsen, verifiera att nästa `save_workspace_prompt`-anrop får samma gränsfel som webb-UI redan ger, `limit_reached` loggat.
10. Verifiera att `admin.html` "Mina prompts" visar den MCP-skapade raden identiskt med en webb-skapad rad.
11. Verifiera `revoke execute ... from anon` (Reversibilitet) faktiskt stänger av verktyget utan att röra befintlig data, i en engångstest på staging.
12. Rensa testnyckel/testdata efter verifiering (samma rutin som tidigare Pro-testnyckel-arbete, se `LOG.md` i `mcp_promptbanken`).

## Uttryckligen utanför scope v1

- Delning till `shared_workspace_addons` via write-verktyget.
- Semantisk/dubblettdetektering (exakt titel/kategori-varning).
- Versionshistorik på mallar.
- Separat "rapportera missad GDPR-risk"-väg.
- Confidence-tröskel eller låst kategorienum.
- Write-stöd i den hostade `mcp_promptbanken`-servern.
- Retention/radering av `mcp_write_attempts` (växer obegränsat i v1).
- `search_path`-uppstädning på befintliga läs-RPC:er (flaggat som separat TODO ovan).
