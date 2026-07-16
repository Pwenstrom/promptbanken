# Valvet — Schema och RPC:er (Plan A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ge `content_items` en `module`-tagg och ett eget, från kommun-taket helt separerat, gränssystem för Valvet, samt sex nyckelhash-baserade RPC:er (`list_my_items_for_key`, `search_my_items_for_key`, `get_my_item_for_key`, `save_my_item_for_key`, `update_my_item_for_key`, `archive_my_item_for_key`) som den hostade MCP-servern (`mcp_promptbanken`-repot, Plan B) och webbappen (`valvet_promptbanken`-repot, Plan C) bygger vidare på.

**Architecture:** Sex nya, daterade migrationsfiler i `supabase/migrations/`, ren tilläggslogik (`create or replace function`, `add column if not exists`) — inga befintliga migrationsfiler redigeras. En dedikerad, alltid-på trigger låser `module`-kolumnen. En separat trigger (`enforce_vault_item_limit`) hanterar Valvets tak/synlighet, helt skild från den befintliga `enforce_content_access_model` (som får en enda ny rad: hoppa över `module='valvet'`-rader). Skrivande RPC:er återanvänder exakt samma förtroendemönster som `save_prompt_for_key` (se `docs/superpowers/specs/2026-07-12-mcp-save-as-template-write-design.md`): `SECURITY DEFINER`, `set search_path = ''`, nyckelhash-uppslag via `api_keys`, `set_config('request.jwt.claim.sub', ...)` för att låta befintliga trigger-checks se ett giltigt `auth.uid()`.

**Tech Stack:** PostgreSQL/PL-pgSQL (Supabase), inga ORM:er. Ingen lokal Postgres/pgTAP i detta repo — verifiering sker manuellt mot en Supabase **staging**-databas (samma konvention som `supabase/tests/*.sql`, se `supabase/README.md`).

## Global Constraints

- Alla nya databasobjekt använder `create or replace` / `add column if not exists` / `do $$ ... exception when duplicate_object ...` — säkert att köra om, matchar befintlig stil i `supabase/migrations/`.
- Alla nya `SECURITY DEFINER`-funktioner **måste** ha `set search_path = ''` (eller en pinnad, explicit path) — se varningen i `2026-07-12-mcp-save-as-template-write-design.md` om att en opinnad `search_path` gör en SECURITY DEFINER-funktion sårbar för schema-hijacking.
- Inga down-migrations i detta repo (bekräftad konvention, se samma spec). Varje task har istället en manuell rollback-kommentar.
- Valvet-poster har alltid `visibility = 'private'` i Fas 1 (ingen delning) — detta är en hård regel i `enforce_vault_item_limit`, inte bara ett UI-antagande.
- `content_items` saknar en `created_at`-kolumn — bara `updated_at` (default `now()`, uppdateras av befintlig trigger `set_content_items_updated_at`). Använd `updated_at` överallt, hitta inte på en `created_at`.
- Migrationer som lägger till ett nytt enum-värde (`ALTER TYPE ... ADD VALUE`) måste ligga i en **egen** migrationsfil, aldrig i samma fil som en sats som använder det nya värdet — Postgres tillåter inte användning av ett nytt enum-värde i samma transaktion som det skapades i.
- Svenska felmeddelanden i alla `raise exception` som kan nå en användare (matchar befintlig kod-konvention).

---

## Filstruktur

- `supabase/migrations/20260716100000_valvet_module_and_write_log.sql` — enum-värde, `module`-kolumn + låsning, `mcp_write_attempts`-tabell.
- `supabase/migrations/20260716100500_valvet_bypass_kommun_trigger.sql` — en rad tillagd i `enforce_content_access_model`.
- `supabase/migrations/20260716101000_valvet_item_limit_trigger.sql` — `enforce_vault_item_limit`.
- `supabase/migrations/20260716101500_valvet_read_rpcs.sql` — `list_my_items_for_key`, `search_my_items_for_key`, `get_my_item_for_key`.
- `supabase/migrations/20260716102000_valvet_save_rpc.sql` — `save_my_item_for_key`, `log_vault_write_attempt`.
- `supabase/migrations/20260716102500_valvet_update_archive_rpc.sql` — `update_my_item_for_key`, `archive_my_item_for_key`.
- `supabase/tests/verify_valvet_limits_and_locking.sql` — manuellt körbart verifieringsskript för Task 1–3.
- `supabase/tests/verify_valvet_rpcs.sql` — manuellt körbart verifieringsskript för Task 4–6.

---

### Task 1: Modul-tagg, låsning, skriv-loggtabell

**⚠️ Reviderad 2026-07-16 efter merge med `origin/main`:** en tidigare, aldrig lokalt pullad session hade redan byggt och applicerat `content_items.idempotency_key`/`content_items.source` och `app_private.mcp_write_attempts` (migrationerna `20260712100000`–`20260712120000`, del av `save_workspace_prompt`-funktionen). Se `docs/superpowers/specs/2026-07-12-mcp-save-as-template-write-design.md` för den fulla bakgrunden. Denna task **ALTER:ar det befintliga**, skapar INTE om det.

**Files:**
- Create: `supabase/migrations/20260716100000_valvet_module_and_write_log.sql`

**Interfaces:**
- Consumes: befintlig tabell `app_private.mcp_write_attempts(id, key_hash, workspace_id, outcome, risk_check_passed, created_at)`, befintlig kolumn `content_items.idempotency_key uuid` + befintligt unikt index `content_items_idempotency_key_per_workspace` (alla från `20260712100000_save_prompt_for_key.sql`, redan i produktion).
- Produces: kolumn `content_items.module text not null default 'kommun' check (module in ('kommun','valvet'))`, enum-värdet `'assistant'` i `content_item_type`, **ny kolumn** `app_private.mcp_write_attempts.tool text not null default 'save_workspace_prompt'` (backfyllar befintliga loggrader från `save_prompt_for_key` korrekt — det var det enda write-verktyget som fanns innan denna task), trigger `lock_content_item_module` (alltid på, används av Task 3 och Plan C/B indirekt).

- [ ] **Step 1: Skriv migrationen**

```sql
-- 20260716100000_valvet_module_and_write_log.sql
-- Valvet: modul-tagg på content_items, ny typ 'assistant', och en delad
-- skriv-loggtabell för rate limiting/kvot (mönster från
-- docs/superpowers/specs/2026-07-12-mcp-save-as-template-write-design.md,
-- aldrig applicerad som migration — bygger den nu, generaliserad med en
-- 'tool'-kolumn eftersom flera verktyg (framtida save_workspace_prompt och
-- Valvets save_my_item) delar samma logg).

do $$
begin
    alter type public.content_item_type add value if not exists 'assistant';
exception
    when duplicate_object then null;
end $$;

alter table public.content_items
    add column if not exists module text not null default 'kommun';

do $$
begin
    alter table public.content_items
        add constraint content_items_module_check check (module in ('kommun', 'valvet'));
exception
    when duplicate_object then null;
end $$;

-- content_items.idempotency_key och dess unika index
-- (content_items_idempotency_key_per_workspace) finns redan sedan
-- 20260712100000_save_prompt_for_key.sql -- inget att göra här.

-- Modul-låsning: gäller ALLA UPDATE på content_items, oavsett riktning
-- (kommun->valvet och valvet->kommun), så en post inte kan omklassas för
-- att kringgå ettdera systemets gräns.
create or replace function app_private.lock_content_item_module()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'UPDATE' and old.module is distinct from new.module then
        raise exception 'module kan inte ändras efter att en post skapats.';
    end if;
    return new;
end;
$$;

revoke all on function app_private.lock_content_item_module() from public;

drop trigger if exists lock_content_item_module on public.content_items;
create trigger lock_content_item_module
before update on public.content_items
for each row execute function app_private.lock_content_item_module();

-- app_private.mcp_write_attempts(id, key_hash, workspace_id, outcome,
-- risk_check_passed, created_at) finns redan (20260712100000). Lägger bara
-- till en tool-kolumn så flera write-verktyg kan dela loggen utan att
-- blanda ihop sina kvoter/rate limits. Default matchar det enda
-- write-verktyg som fanns innan denna migration.
alter table app_private.mcp_write_attempts
    add column if not exists tool text not null default 'save_workspace_prompt';

create index if not exists mcp_write_attempts_workspace_tool_created_at_idx
    on app_private.mcp_write_attempts (workspace_id, tool, created_at desc);
```

- [ ] **Step 2: Applicera mot staging**

Öppna Supabase Dashboard → staging-projektet → SQL Editor, klistra in filens
innehåll, kör. Förväntat: `Success. No rows returned` (eller motsvarande),
inga fel. Om `SUPABASE MCP` är auktoriserad i din session kan du istället
köra migrationen via dess `execute_sql`-verktyg.

- [ ] **Step 3: Snabb koll i staging**

```sql
select column_name, data_type, column_default
  from information_schema.columns
 where table_name = 'content_items' and column_name = 'module';

select column_name, data_type, column_default
  from information_schema.columns
 where table_schema = 'app_private' and table_name = 'mcp_write_attempts' and column_name = 'tool';

select enumlabel from pg_enum e
  join pg_type t on t.oid = e.enumtypid
 where t.typname = 'content_item_type' order by e.enumsortorder;
```

Förväntat: `module` finns (`text`, default `'kommun'::text`), `tool` finns på
`app_private.mcp_write_attempts` (`text`, default `'save_workspace_prompt'::text`),
och enum-listan innehåller `assistant`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260716100000_valvet_module_and_write_log.sql
git commit -m "feat(db): add content_items.module tag, assistant type, mcp_write_attempts log"
```

**Rollback (manuell, om något går fel i staging):**
```sql
drop trigger if exists lock_content_item_module on public.content_items;
drop function if exists app_private.lock_content_item_module();
alter table app_private.mcp_write_attempts drop column if exists tool;
alter table public.content_items drop constraint if exists content_items_module_check;
alter table public.content_items drop column if exists module;
-- content_items.idempotency_key och app_private.mcp_write_attempts fanns
-- innan denna migration (save_workspace_prompt) -- rör dem INTE vid rollback.
-- Enum-värden kan inte tas bort i Postgres utan att återskapa typen — lämna 'assistant' kvar, oskadligt om oanvänt.
```

---

### Task 2: Kommun-triggern ska ignorera Valvet-rader

**Files:**
- Create: `supabase/migrations/20260716100500_valvet_bypass_kommun_trigger.sql`

**Interfaces:**
- Consumes: `content_items.module` (Task 1).
- Produces: `app_private.enforce_content_access_model()` (samma namn, `create or replace`) hoppar nu helt över `module='valvet'`-rader — kommunens 3/100-tak räknar aldrig Valvet-poster, och kommunens visibility-regler appliceras aldrig på dem.

**Varför en egen task:** utan detta skulle en `type='prompt'`-rad med `module='valvet'` (vilket `save_my_item_for_key` i Task 5 skapar) råka räknas mot kommunens Free-tak på 3 also, eftersom den befintliga triggerns `prompt_count`-fråga inte filtrerar på `module`. `type='assistant'`-rader påverkas inte (triggern har redan en tidig `if new.type <> 'prompt' then return new`), men `type='prompt'`-rader i Valvet måste explicit undantas.

- [ ] **Step 1: Läs den nuvarande definitionen**

Kör i staging SQL Editor för att se exakt vilken version som ligger live just nu (kan skilja sig något mellan de historiska migrationsfilerna beroende på vilka som faktiskt applicerats):

```sql
select prosrc from pg_proc where proname = 'enforce_content_access_model';
```

- [ ] **Step 2: Skriv migrationen**

Detta är en `create or replace` av **samma funktion** som redan finns (senast definierad av `20260706102000_addon_prompt_limit.sql`). Kopiera den funktionen rakt av och lägg bara till modul-bypassen som första kontroll efter typ-kontrollen:

```sql
-- 20260716100500_valvet_bypass_kommun_trigger.sql
create or replace function app_private.enforce_content_access_model()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record   public.workspaces%rowtype;
    license_record      public.pro_licenses%rowtype;
    addon_record         public.shared_workspace_addons%rowtype;
    is_platform_owner   boolean;
    prompt_count         integer;
    prompt_limit         integer;
begin
    select * into workspace_record from public.workspaces where id = new.workspace_id;
    if not found then
        raise exception 'Workspace saknas.';
    end if;

    select app_private.current_user_is_platform_owner() into is_platform_owner;

    if new.type <> 'prompt' then
        return new;
    end if;

    -- Valvet har ett eget, helt separat gränssystem (se enforce_vault_item_limit) --
    -- kommunens tak/synlighetsregler ska aldrig se eller räkna dessa rader.
    if new.module = 'valvet' then
        return new;
    end if;

    if tg_op = 'INSERT' and new.created_by is distinct from auth.uid() then
        raise exception 'Prompts måste skapas av inloggad användare.';
    end if;

    if tg_op = 'INSERT' and new.owner_user_id is null then
        new.owner_user_id := auth.uid();
    end if;

    if new.visibility = 'public' and not is_platform_owner then
        raise exception 'Endast plattformsadmin kan skapa publika prompts.';
    end if;

    if workspace_record.type = 'personal' then
        if workspace_record.plan = 'free' and new.visibility <> 'private' then
            raise exception 'Free-läge tillåter bara privata prompts.';
        end if;
        if workspace_record.plan = 'pro' and new.visibility not in ('private', 'workspace') then
            raise exception 'Pro-läge tillåter privata eller workspace-synliga prompts.';
        end if;
        if tg_op = 'INSERT' and new.owner_user_id is distinct from auth.uid() then
            raise exception 'Privata prompts måste ägas av användaren.';
        end if;

        select count(*) into prompt_count
          from public.content_items ci
         where ci.workspace_id = new.workspace_id
           and ci.type = 'prompt'
           and ci.module = 'kommun'
           and ci.owner_user_id = auth.uid()
           and ci.status <> 'archived'
           and (tg_op = 'INSERT' or ci.id <> new.id);

        if prompt_count >= workspace_record.max_prompts then
            raise exception 'Du har nått gränsen på % prompts för %-planen.', workspace_record.max_prompts, workspace_record.plan;
        end if;

    elsif workspace_record.type = 'organization' and not is_platform_owner then
        if new.visibility <> 'workspace' then
            raise exception 'Organisationsprompts måste vara synliga inom organisationen.';
        end if;

        if workspace_record.license_id is not null then
            select * into license_record from public.pro_licenses where id = workspace_record.license_id;

            select count(*) into prompt_count
              from public.content_items ci
             where ci.workspace_id in (select app_private.license_group_workspace_ids(new.workspace_id))
               and ci.type = 'prompt'
               and ci.status <> 'archived'
               and (tg_op = 'INSERT' or ci.id <> new.id);

            prompt_limit := coalesce(license_record.max_prompts_total, workspace_record.max_prompts);

            if prompt_count >= prompt_limit then
                raise exception 'Licensen har nått gränsen på % mallar totalt.', prompt_limit;
            end if;
        else
            select * into addon_record from public.shared_workspace_addons where workspace_id = workspace_record.id;
            if not found then
                raise exception 'Organisationsytan saknar addon-konfiguration.';
            end if;

            select count(*) into prompt_count
              from public.content_items ci
             where ci.workspace_id = workspace_record.id
               and ci.type = 'prompt'
               and ci.status <> 'archived'
               and (tg_op = 'INSERT' or ci.id <> new.id);

            prompt_limit := coalesce(addon_record.max_prompts, 200);

            if prompt_count >= prompt_limit then
                raise exception 'Den delade arbetsytan har nått gränsen på % mallar.', prompt_limit;
            end if;
        end if;
    end if;

    return new;
end;
$$;

revoke all on function app_private.enforce_content_access_model() from public;
```

**Note:** om Step 1 visar att den live-liggande definitionen skiljer sig
från detta (t.ex. om en senare, inte lokalt hittad migration redan ändrat
den), stanna och reconcilera innan du kör Step 3 — `create or replace`
skriver över helt, så en avvikande live-version måste förstås först, inte
bara skrivas över blint.

- [ ] **Step 3: Applicera mot staging, verifiera**

```sql
-- I ett Free-personligt test-workspace, försök skapa en type='prompt'-rad
-- med module='valvet' fyra gånger i rad (efter att ha skapat 3 stycken
-- module='kommun'-prompts som redan fyller kommun-taket) -- ska INTE
-- blockeras av kommun-triggern (den kan fortfarande blockeras av
-- enforce_vault_item_limit från Task 3, som inte finns än -- det är OK,
-- verifiera bara att INTE "Du har nått gränsen på 3 prompts"-felet dyker
-- upp för en module='valvet'-rad).
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260716100500_valvet_bypass_kommun_trigger.sql
git commit -m "fix(db): stop kommun free/pro prompt cap from counting valvet items"
```

**Rollback:** kör om `create or replace` med den ursprungliga (Step 1) definitionen.

---

### Task 3: Valvets eget tak + synlighetslås

**Files:**
- Create: `supabase/migrations/20260716101000_valvet_item_limit_trigger.sql`
- Create: `supabase/tests/verify_valvet_limits_and_locking.sql`

**Interfaces:**
- Consumes: `content_items.module` (Task 1), `lock_content_item_module`-trigger (Task 1, redan hanterar modul-låsning — denna task lägger INTE till en egen modul-check).
- Produces: trigger `enforce_vault_item_limit` på `content_items`. Taket är **beräknat**, inte lagrat: 50 om `workspace.plan = 'free'`, annars 1000 (se Global Constraints/spec: undviker en ny kolumn som måste synkas av alla upp-/nedgraderings-RPC:er).

- [ ] **Step 1: Skriv migrationen**

```sql
-- 20260716101000_valvet_item_limit_trigger.sql
create or replace function app_private.enforce_vault_item_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record public.workspaces%rowtype;
    item_count        integer;
    item_limit         integer;
    becomes_active     boolean;
begin
    if new.module <> 'valvet' then
        return new;
    end if;

    if new.visibility <> 'private' then
        raise exception 'Valvet stödjer bara privata insättningar i denna version.';
    end if;

    if tg_op = 'INSERT' and new.created_by is distinct from auth.uid() then
        raise exception 'Insättningar måste skapas av inloggad användare.';
    end if;

    if tg_op = 'INSERT' and new.owner_user_id is null then
        new.owner_user_id := auth.uid();
    end if;

    if tg_op = 'INSERT' and new.owner_user_id is distinct from auth.uid() then
        raise exception 'Insättningar måste ägas av användaren som skapar dem.';
    end if;

    becomes_active := (tg_op = 'INSERT' and new.status <> 'archived')
        or (tg_op = 'UPDATE' and old.status = 'archived' and new.status <> 'archived');

    if becomes_active then
        select * into workspace_record from public.workspaces where id = new.workspace_id;
        if not found then
            raise exception 'Workspace saknas.';
        end if;

        item_limit := case when workspace_record.plan = 'free' then 50 else 1000 end;

        select count(*) into item_count
          from public.content_items ci
         where ci.workspace_id = new.workspace_id
           and ci.module = 'valvet'
           and ci.owner_user_id = new.owner_user_id
           and ci.status <> 'archived'
           and (tg_op = 'INSERT' or ci.id <> new.id);

        if item_count >= item_limit then
            raise exception 'Du har nått gränsen på % insättningar i Valvet.', item_limit;
        end if;
    end if;

    return new;
end;
$$;

revoke all on function app_private.enforce_vault_item_limit() from public;

drop trigger if exists enforce_vault_item_limit on public.content_items;
create trigger enforce_vault_item_limit
before insert or update on public.content_items
for each row execute function app_private.enforce_vault_item_limit();
```

- [ ] **Step 2: Skriv verifieringsskriptet**

```sql
-- supabase/tests/verify_valvet_limits_and_locking.sql
-- Körs manuellt mot staging efter Task 1-3. Kräver ett Free-personligt
-- test-workspace (slug 'test-free-personal', se seed-scriptet) inloggat
-- via en riktig auth-session (auth.uid() måste matcha workspacets
-- owner_user_id för dessa INSERT/UPDATE-satser -- kör som den användaren,
-- t.ex. via Supabase SQL Editor "Run as user" eller en client-driven
-- session, INTE som service_role).

-- V1 -- 50 valvet-items ska gå bra, den 51:a ska blockeras.
-- (Kör i en loop eller upprepa manuellt -- visar principen för en post:)
insert into public.content_items (workspace_id, owner_user_id, created_by, type, module, title, slug, content, status, visibility)
select w.id, w.owner_user_id, w.owner_user_id, 'prompt', 'valvet', 'V1 test', 'v1-test-' || gen_random_uuid()::text, 'innehåll', 'draft', 'private'
from public.workspaces w where w.slug = 'test-free-personal';
-- Förväntat vid rad 51: ERROR 'Du har nått gränsen på 50 insättningar i Valvet.'

-- V2 -- modul-låsning: försök ändra module på en befintlig valvet-rad.
update public.content_items set module = 'kommun'
where module = 'valvet' and workspace_id = (select id from public.workspaces where slug = 'test-free-personal') limit 1;
-- Förväntat: ERROR 'module kan inte ändras efter att en post skapats.'

-- V3 -- synlighetslås: försök sätta visibility='workspace' på en valvet-rad.
update public.content_items set visibility = 'workspace'
where module = 'valvet' and workspace_id = (select id from public.workspaces where slug = 'test-free-personal') limit 1;
-- Förväntat: ERROR 'Valvet stödjer bara privata insättningar i denna version.'

-- V4 -- arkiverade räknas inte mot taket: arkivera en post, försök skapa en ny (ska gå bra igen).
update public.content_items set status = 'archived'
where module = 'valvet' and workspace_id = (select id from public.workspaces where slug = 'test-free-personal') limit 1;
insert into public.content_items (workspace_id, owner_user_id, created_by, type, module, title, slug, content, status, visibility)
select w.id, w.owner_user_id, w.owner_user_id, 'prompt', 'valvet', 'V4 test', 'v4-test-' || gen_random_uuid()::text, 'innehåll', 'draft', 'private'
from public.workspaces w where w.slug = 'test-free-personal';
-- Förväntat: lyckas (arkiveringen frigjorde en plats under taket).

-- V5 -- återställning räknas mot taket: om workspacet nu har exakt 50 aktiva
-- (efter V4 fyllde platsen igen), försök återställa den arkiverade från V4.
update public.content_items set status = 'draft'
where module = 'valvet' and status = 'archived'
  and workspace_id = (select id from public.workspaces where slug = 'test-free-personal') limit 1;
-- Förväntat: ERROR 'Du har nått gränsen på 50 insättningar i Valvet.'
```

- [ ] **Step 3: Applicera mot staging, kör verifieringsskriptet, bekräfta alla V1–V5 gav förväntat resultat**

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260716101000_valvet_item_limit_trigger.sql supabase/tests/verify_valvet_limits_and_locking.sql
git commit -m "feat(db): add Valvet's own item cap and visibility lock, separate from kommun"
```

**Rollback:**
```sql
drop trigger if exists enforce_vault_item_limit on public.content_items;
drop function if exists app_private.enforce_vault_item_limit();
```

---

### Task 4: Läs-RPC:er — list/search/get

**Files:**
- Create: `supabase/migrations/20260716101500_valvet_read_rpcs.sql`

**Interfaces:**
- Consumes: `api_keys`, `workspaces`, `content_items.module` (Task 1).
- Produces: `public.list_my_items_for_key(p_key_hash text, p_type text default null, p_category text default null, p_status text default null)`, `public.search_my_items_for_key(p_key_hash text, p_query text, p_type text default null, p_category text default null)`, `public.get_my_item_for_key(p_key_hash text, p_id uuid)` — alla `returns table(id uuid, type text, title text, content text, category text, status text, updated_at timestamptz)`, granted till `anon, authenticated` (samma förtroendemodell som `get_workspace_prompts_for_key`: nyckelhashen är beviset på behörighet). Ogiltig/återkallad/inaktiv nyckel → tom resultatmängd, inget fel (matchar befintligt mönster, låter Python-lagret sätta `workspace_status`).

- [ ] **Step 1: Skriv migrationen**

```sql
-- 20260716101500_valvet_read_rpcs.sql

create or replace function app_private.list_my_items_for_key(
    p_key_hash text,
    p_type     text default null,
    p_category text default null,
    p_status   text default null
)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then return; end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then return; end if;

    return query
    select ci.id, ci.type::text, ci.title, ci.content, ci.category, ci.status::text, ci.updated_at
      from public.content_items ci
     where ci.workspace_id = v_ws.id
       and ci.module = 'valvet'
       and ci.owner_user_id = v_ws.owner_user_id
       and (
           (p_status is not null and ci.status::text = p_status)
           or (p_status is null and ci.status <> 'archived')
       )
       and (p_type is null or ci.type::text = p_type)
       and (p_category is null or ci.category = p_category)
     order by ci.updated_at desc;
end;
$$;

revoke all on function app_private.list_my_items_for_key(text, text, text, text) from public;

create or replace function public.list_my_items_for_key(
    p_key_hash text, p_type text default null, p_category text default null, p_status text default null
)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select * from app_private.list_my_items_for_key(p_key_hash, p_type, p_category, p_status);
$$;

revoke all on function public.list_my_items_for_key(text, text, text, text) from public;
grant execute on function public.list_my_items_for_key(text, text, text, text) to anon, authenticated;


create or replace function app_private.search_my_items_for_key(
    p_key_hash text,
    p_query    text,
    p_type     text default null,
    p_category text default null
)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
begin
    if coalesce(trim(p_query), '') = '' then
        return;
    end if;

    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then return; end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then return; end if;

    return query
    select ci.id, ci.type::text, ci.title, ci.content, ci.category, ci.status::text, ci.updated_at
      from public.content_items ci
     where ci.workspace_id = v_ws.id
       and ci.module = 'valvet'
       and ci.owner_user_id = v_ws.owner_user_id
       and ci.status <> 'archived'
       and (p_type is null or ci.type::text = p_type)
       and (p_category is null or ci.category = p_category)
       and (
           ci.title ilike '%' || p_query || '%'
           or ci.content ilike '%' || p_query || '%'
           or coalesce(ci.category, '') ilike '%' || p_query || '%'
       )
     order by ci.updated_at desc;
end;
$$;

revoke all on function app_private.search_my_items_for_key(text, text, text, text) from public;

create or replace function public.search_my_items_for_key(
    p_key_hash text, p_query text, p_type text default null, p_category text default null
)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select * from app_private.search_my_items_for_key(p_key_hash, p_query, p_type, p_category);
$$;

revoke all on function public.search_my_items_for_key(text, text, text, text) from public;
grant execute on function public.search_my_items_for_key(text, text, text, text) to anon, authenticated;


create or replace function app_private.get_my_item_for_key(
    p_key_hash text,
    p_id       uuid
)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then return; end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then return; end if;

    return query
    select ci.id, ci.type::text, ci.title, ci.content, ci.category, ci.status::text, ci.updated_at
      from public.content_items ci
     where ci.id = p_id
       and ci.workspace_id = v_ws.id
       and ci.module = 'valvet'
       and ci.owner_user_id = v_ws.owner_user_id;
end;
$$;

revoke all on function app_private.get_my_item_for_key(text, uuid) from public;

create or replace function public.get_my_item_for_key(p_key_hash text, p_id uuid)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select * from app_private.get_my_item_for_key(p_key_hash, p_id);
$$;

revoke all on function public.get_my_item_for_key(text, uuid) from public;
grant execute on function public.get_my_item_for_key(text, uuid) to anon, authenticated;
```

- [ ] **Step 2: Applicera mot staging**

- [ ] **Step 3: Manuell verifiering**

```sql
-- Med en riktig test-nyckels rå-värde, hasha den (sha256 hex) och kör:
select * from public.list_my_items_for_key('<hash>');
select * from public.search_my_items_for_key('<hash>', 'V1');
select * from public.get_my_item_for_key('<hash>', '<id från ovan>');
-- Förväntat: rätta rader, inga fel. Med en påhittad hash: tomma resultat, inget fel.
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260716101500_valvet_read_rpcs.sql
git commit -m "feat(db): add list/search/get RPCs for Valvet items"
```

**Rollback:**
```sql
drop function if exists public.get_my_item_for_key(text, uuid);
drop function if exists app_private.get_my_item_for_key(text, uuid);
drop function if exists public.search_my_items_for_key(text, text, text, text);
drop function if exists app_private.search_my_items_for_key(text, text, text, text);
drop function if exists public.list_my_items_for_key(text, text, text, text);
drop function if exists app_private.list_my_items_for_key(text, text, text, text);
```

---

### Task 5: `save_my_item_for_key`

**Files:**
- Create: `supabase/migrations/20260716102000_valvet_save_rpc.sql`

**⚠️ Reviderad 2026-07-16 efter merge med `origin/main`:** `app_private.log_write_attempt(p_key_hash, p_outcome, p_risk_check_passed)` + dess publika wrapper finns redan (byggda för `save_workspace_prompt`, se `20260712110000_log_write_attempt.sql`/`20260712120000_public_wrappers_for_save_prompt.sql`). Denna task **breddar den befintliga funktionen** med en valfri `p_tool`-parameter istället för att skapa en ny, nästan identisk `log_vault_write_attempt`.

**Interfaces:**
- Consumes: `app_private.mcp_write_attempts` (Task 1, nu med `tool`-kolumn), `enforce_vault_item_limit`-triggern (Task 3, körs automatiskt vid INSERT), `app_private.slugify_candidate` (befintlig helper, se `20260703120000_create_pro_order.sql`), befintlig `app_private.log_write_attempt`/`public.log_write_attempt` (breddas, se ovan).
- Produces: `public.save_my_item_for_key(p_key_hash text, p_idempotency_key uuid, p_type text, p_title text, p_content text, p_category text default null) returns public.content_items`. `app_private.log_write_attempt`/`public.log_write_attempt` får en 4:e parameter `p_tool text default 'save_workspace_prompt'` (bakåtkompatibel — PostgREST matchar på namngivna nycklar, så befintliga 3-parameters-anrop från `mcp_promptbanken`-repots `pro_templates.py` fortsätter fungera oförändrat och loggar automatiskt med `tool='save_workspace_prompt'`). Anropas av Python-lagret (Plan B) EFTER ett fångat fel, av exakt samma skäl som funktionen redan är designad för (en `raise exception` rullar tillbaka HELA transaktionen, så ett `insert` av loggraden inuti samma anrop som avvisar skulle aldrig persisteras — se kommentaren i `20260712110000_log_write_attempt.sql`). Loggar alltid `workspace_id = null` — den behövs bara för månadskvoten, som bara räknar `outcome='success'`-rader, och de loggas alltid INIFRÅN `save_my_item_for_key` (där `workspace_id` redan är känt), aldrig via denna separata Python-anropade funktion.

Fel-klassificering (för Plan B:s Python-lager att matcha på textsträng i felmeddelandet, samma mönster som `_classify_write_error`):
| Fellmeddelande innehåller | outcome |
|---|---|
| `Ogiltig nyckel` | `invalid_key` |
| `För många försök` | `rate_limited` |
| `Ogiltig typ` | `invalid_input` |
| `Titel` / `Innehåll` | `invalid_input` |
| `Månadskvoten` | `quota_reached` |
| (INSERT-fel som faller igenom till triggern, t.ex. gräns nådd) | `limit_reached` |

- [ ] **Step 1: Skriv migrationen**

```sql
-- 20260716102000_valvet_save_rpc.sql

-- Bredda den befintliga log_write_attempt (byggd för save_workspace_prompt,
-- 20260712110000) med en valfri p_tool-parameter.
--
-- OBS: en `create or replace` med en ANNAN argumenttyp-lista (3 -> 4
-- parametrar) skapar en NY, samexisterande overload -- den ersätter INTE
-- 3-parametersfunktionen. Med båda kvar blir befintliga 3-parameters-anrop
-- (t.ex. `pro_templates.py`s PostgREST-anrop till `log_write_attempt` med
-- p_key_hash/p_outcome/p_risk_check_passed) tvetydiga: Postgres ser två
-- giltiga kandidater (en exakt, en via default för p_tool) och kastar
-- "function ... is not unique" (PostgREST: PGRST203). Måste därför droppa
-- 3-parametersversionen explicit innan den bredare skapas, så bara EN
-- overload finns kvar och 3-parametersanrop matchar den via default-värdet.
drop function if exists public.log_write_attempt(text, text, boolean);
drop function if exists app_private.log_write_attempt(text, text, boolean);

create or replace function app_private.log_write_attempt(
    p_key_hash           text,
    p_outcome            text,
    p_risk_check_passed  boolean default null,
    p_tool               text default 'save_workspace_prompt'
)
returns void
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    insert into app_private.mcp_write_attempts (key_hash, outcome, risk_check_passed, tool)
    values (p_key_hash, p_outcome, p_risk_check_passed, p_tool);
$$;

revoke all on function app_private.log_write_attempt(text, text, boolean, text) from public;
grant execute on function app_private.log_write_attempt(text, text, boolean, text) to anon;

create or replace function public.log_write_attempt(
    p_key_hash           text,
    p_outcome            text,
    p_risk_check_passed  boolean default null,
    p_tool               text default 'save_workspace_prompt'
)
returns void
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select app_private.log_write_attempt(p_key_hash, p_outcome, p_risk_check_passed, p_tool);
$$;

revoke all on function public.log_write_attempt(text, text, boolean, text) from public;
grant execute on function public.log_write_attempt(text, text, boolean, text) to anon;


create or replace function app_private.save_my_item_for_key(
    p_key_hash         text,
    p_idempotency_key  uuid,
    p_type             text,
    p_title            text,
    p_content          text,
    p_category         text default null
)
returns public.content_items
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key         public.api_keys%rowtype;
    v_ws          public.workspaces%rowtype;
    v_existing    public.content_items%rowtype;
    v_row         public.content_items%rowtype;
    v_recent_attempts integer;
    v_monthly_saves   integer;
    v_slug        text;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    select count(*) into v_recent_attempts
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash and created_at >= now() - interval '60 seconds';
    if v_recent_attempts >= 20 then
        raise exception 'För många försök, vänta en minut och försök igen.';
    end if;

    if p_type not in ('prompt', 'assistant') then
        raise exception 'Ogiltig typ.';
    end if;
    if trim(coalesce(p_title, '')) = '' or length(p_title) > 200 then
        raise exception 'Titel måste vara 1–200 tecken.';
    end if;
    if trim(coalesce(p_content, '')) = '' or length(p_content) > 20000 then
        raise exception 'Innehåll måste vara 1–20000 tecken.';
    end if;

    if p_idempotency_key is not null then
        select * into v_existing
          from public.content_items
         where workspace_id = v_ws.id and module = 'valvet' and idempotency_key = p_idempotency_key;
        if found then
            return v_existing;
        end if;
    end if;

    if v_ws.plan = 'free' then
        select count(*) into v_monthly_saves
          from app_private.mcp_write_attempts
         where workspace_id = v_ws.id
           and tool = 'save_my_item'
           and outcome = 'success'
           and created_at >= date_trunc('month', now());
        if v_monthly_saves >= 5 then
            raise exception 'Månadskvoten på 5 nya insättningar via MCP är förbrukad. Skapa via webbappen, eller uppgradera till Pro.';
        end if;
    end if;

    v_slug := app_private.slugify_candidate(p_title, 'valv');
    while exists (select 1 from public.content_items where workspace_id = v_ws.id and slug = v_slug) loop
        v_slug := app_private.slugify_candidate(p_title, 'valv') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    end loop;

    perform set_config('request.jwt.claim.sub', v_ws.owner_user_id::text, true);

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, module, title, slug,
        content, category, status, visibility, idempotency_key
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id, p_type::public.content_item_type, 'valvet',
        p_title, v_slug, p_content, p_category, 'draft', 'private', p_idempotency_key
    )
    returning * into v_row;

    insert into app_private.mcp_write_attempts (key_hash, workspace_id, tool, outcome)
    values (p_key_hash, v_ws.id, 'save_my_item', 'success');

    return v_row;
end;
$$;

revoke all on function app_private.save_my_item_for_key(text, uuid, text, text, text, text) from public;

create or replace function public.save_my_item_for_key(
    p_key_hash text, p_idempotency_key uuid, p_type text, p_title text, p_content text, p_category text default null
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.save_my_item_for_key(p_key_hash, p_idempotency_key, p_type, p_title, p_content, p_category);
$$;

revoke all on function public.save_my_item_for_key(text, uuid, text, text, text, text) from public;
grant execute on function public.save_my_item_for_key(text, uuid, text, text, text, text) to anon, authenticated;
```

**Not om `set search_path`:** `save_my_item_for_key` (app_private-versionen) sätter
`public, app_private, pg_temp` istället för `''` eftersom den anropar
`app_private.slugify_candidate` och behöver referera `public.content_items`/
`public.api_keys`/`public.workspaces` utan fullt kvalificerade namn på vissa
ställen (`gen_random_uuid()` m.fl. pgcrypto-funktioner) — samma avsteg som
`save_prompt_for_key` redan gör medvetet, se specen. Wrapper-funktionen i
`public`-schemat behåller `set search_path = ''` som alla andra wrappers.

- [ ] **Step 2: Applicera mot staging**

- [ ] **Step 3: Manuell verifiering**

```sql
-- Lyckad save:
select * from public.save_my_item_for_key('<free-hash>', gen_random_uuid(), 'prompt', 'Test', 'Innehåll', 'Kategori A');
-- Kör IGEN med SAMMA idempotency-uuid och samma argument -> ska returnera
-- exakt samma rad (samma id), inte skapa en ny.
-- Kör 5 gånger till med nya idempotency-uuid:n på ett Free-workspace ->
-- den 6:e (totalt) inom samma kalendermånad ska ge
-- ERROR 'Månadskvoten på 5 nya insättningar...'
-- (Free har redan förbrukat kvoten från den första lyckade + 4 nya = 5.)
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260716102000_valvet_save_rpc.sql
git commit -m "feat(db): add save_my_item_for_key with idempotency and monthly quota"
```

**Rollback:**
```sql
drop function if exists public.save_my_item_for_key(text, uuid, text, text, text, text);
drop function if exists app_private.save_my_item_for_key(text, uuid, text, text, text, text);
-- log_write_attempt: INTE säkert att bara droppa -- save_workspace_prompt
-- (befintlig, i produktion) beror på den. Om p_tool-breddningen måste
-- rullas tillbaka, återskapa 3-parameters-versionen explicit istället för
-- att droppa funktionen (se 20260712110000_log_write_attempt.sql för den
-- ursprungliga definitionen).
```

---

### Task 6: `update_my_item_for_key` och `archive_my_item_for_key`

**Files:**
- Create: `supabase/migrations/20260716102500_valvet_update_archive_rpc.sql`

**Interfaces:**
- Consumes: `app_private.has_active_pro_entitlement(uuid)` (befintlig, se `20260706100500_has_active_pro_entitlement.sql`), `enforce_vault_item_limit`-triggern (Task 3, körs automatiskt vid UPDATE som återaktiverar en post).
- Produces: `public.update_my_item_for_key(p_key_hash text, p_id uuid, p_expected_updated_at timestamptz, p_title text default null, p_content text default null, p_category text default null) returns public.content_items`, `public.archive_my_item_for_key(p_key_hash text, p_id uuid, p_confirm boolean, p_restore boolean default false) returns public.content_items`.

Fel-klassificering (samma tabellprincip som Task 5):
| Fellmeddelande innehåller | outcome |
|---|---|
| `Ogiltig nyckel` | `invalid_key` |
| `Uppgradera till Pro` | `not_pro` |
| `För många försök` | `rate_limited` |
| `hittades inte` | `not_found` |
| `ändrats sedan du hämtade` | `conflict` |
| `confirm måste vara true` | `invalid_input` |
| (gräns nådd vid återställning) | `limit_reached` |

- [ ] **Step 1: Skriv migrationen**

```sql
-- 20260716102500_valvet_update_archive_rpc.sql

create or replace function app_private.update_my_item_for_key(
    p_key_hash            text,
    p_id                  uuid,
    p_expected_updated_at timestamptz,
    p_title               text default null,
    p_content             text default null,
    p_category            text default null
)
returns public.content_items
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key     public.api_keys%rowtype;
    v_ws      public.workspaces%rowtype;
    v_current public.content_items%rowtype;
    v_row     public.content_items%rowtype;
    v_recent_attempts integer;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    if not app_private.has_active_pro_entitlement(v_ws.owner_user_id) then
        raise exception 'Uppgradera till Pro för att uppdatera via MCP.';
    end if;

    select count(*) into v_recent_attempts
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash and created_at >= now() - interval '60 seconds';
    if v_recent_attempts >= 20 then
        raise exception 'För många försök, vänta en minut och försök igen.';
    end if;

    if p_title is not null and (trim(p_title) = '' or length(p_title) > 200) then
        raise exception 'Titel måste vara 1–200 tecken.';
    end if;
    if p_content is not null and (trim(p_content) = '' or length(p_content) > 20000) then
        raise exception 'Innehåll måste vara 1–20000 tecken.';
    end if;

    select * into v_current
      from public.content_items
     where id = p_id and workspace_id = v_ws.id and module = 'valvet' and owner_user_id = v_ws.owner_user_id;
    if not found then
        raise exception 'Insättningen hittades inte.';
    end if;

    if v_current.updated_at <> p_expected_updated_at then
        raise exception 'Insättningen har ändrats sedan du hämtade den — hämta på nytt med get_my_item och försök igen.';
    end if;

    update public.content_items
       set title    = coalesce(p_title, title),
           content  = coalesce(p_content, content),
           category = coalesce(p_category, category)
     where id = p_id
    returning * into v_row;

    insert into app_private.mcp_write_attempts (key_hash, workspace_id, tool, outcome)
    values (p_key_hash, v_ws.id, 'update_my_item', 'success');

    return v_row;
end;
$$;

revoke all on function app_private.update_my_item_for_key(text, uuid, timestamptz, text, text, text) from public;

create or replace function public.update_my_item_for_key(
    p_key_hash text, p_id uuid, p_expected_updated_at timestamptz,
    p_title text default null, p_content text default null, p_category text default null
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.update_my_item_for_key(p_key_hash, p_id, p_expected_updated_at, p_title, p_content, p_category);
$$;

revoke all on function public.update_my_item_for_key(text, uuid, timestamptz, text, text, text) from public;
grant execute on function public.update_my_item_for_key(text, uuid, timestamptz, text, text, text) to anon, authenticated;


create or replace function app_private.archive_my_item_for_key(
    p_key_hash text,
    p_id       uuid,
    p_confirm  boolean,
    p_restore  boolean default false
)
returns public.content_items
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key     public.api_keys%rowtype;
    v_ws      public.workspaces%rowtype;
    v_current public.content_items%rowtype;
    v_row     public.content_items%rowtype;
    v_target_status public.content_status;
    v_recent_attempts integer;
    v_tool text;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    if not app_private.has_active_pro_entitlement(v_ws.owner_user_id) then
        raise exception 'Uppgradera till Pro för att arkivera/återställa via MCP.';
    end if;

    if p_confirm is distinct from true then
        raise exception 'confirm måste vara true för att arkivera eller återställa.';
    end if;

    select count(*) into v_recent_attempts
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash and created_at >= now() - interval '60 seconds';
    if v_recent_attempts >= 20 then
        raise exception 'För många försök, vänta en minut och försök igen.';
    end if;

    select * into v_current
      from public.content_items
     where id = p_id and workspace_id = v_ws.id and module = 'valvet' and owner_user_id = v_ws.owner_user_id;
    if not found then
        raise exception 'Insättningen hittades inte.';
    end if;

    v_target_status := case when p_restore then 'draft' else 'archived' end;
    v_tool := case when p_restore then 'archive_my_item_restore' else 'archive_my_item' end;

    if v_current.status = v_target_status then
        return v_current; -- redan i önskat läge, säker no-op
    end if;

    update public.content_items
       set status = v_target_status
     where id = p_id
    returning * into v_row;

    insert into app_private.mcp_write_attempts (key_hash, workspace_id, tool, outcome)
    values (p_key_hash, v_ws.id, v_tool, 'success');

    return v_row;
end;
$$;

revoke all on function app_private.archive_my_item_for_key(text, uuid, boolean, boolean) from public;

create or replace function public.archive_my_item_for_key(
    p_key_hash text, p_id uuid, p_confirm boolean, p_restore boolean default false
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.archive_my_item_for_key(p_key_hash, p_id, p_confirm, p_restore);
$$;

revoke all on function public.archive_my_item_for_key(text, uuid, boolean, boolean) from public;
grant execute on function public.archive_my_item_for_key(text, uuid, boolean, boolean) to anon, authenticated;
```

- [ ] **Step 2: Applicera mot staging**

- [ ] **Step 3: Manuell verifiering**

```sql
-- Med en Pro-nyckels hash och en post-id + dess NUVARANDE updated_at (från get_my_item_for_key):
select * from public.update_my_item_for_key('<pro-hash>', '<id>', '<updated_at>', 'Ny titel');
-- Kör EXAKT samma anrop igen med samma (nu inaktuella) updated_at ->
-- ERROR 'Insättningen har ändrats sedan du hämtade den...'

select * from public.archive_my_item_for_key('<pro-hash>', '<id>', true, false);
-- status ska nu vara 'archived'.
select * from public.archive_my_item_for_key('<pro-hash>', '<id>', true, false);
-- Kör igen -> no-op, returnerar samma rad, inget fel.
select * from public.archive_my_item_for_key('<pro-hash>', '<id>', true, true);
-- status ska nu vara 'draft' igen.

-- Med en Free-nyckels hash:
select * from public.update_my_item_for_key('<free-hash>', '<id>', now());
-- ERROR 'Uppgradera till Pro för att uppdatera via MCP.'
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260716102500_valvet_update_archive_rpc.sql
git commit -m "feat(db): add update_my_item_for_key and archive_my_item_for_key (Pro-gated)"
```

**Rollback:**
```sql
drop function if exists public.archive_my_item_for_key(text, uuid, boolean, boolean);
drop function if exists app_private.archive_my_item_for_key(text, uuid, boolean, boolean);
drop function if exists public.update_my_item_for_key(text, uuid, timestamptz, text, text, text);
drop function if exists app_private.update_my_item_for_key(text, uuid, timestamptz, text, text, text);
```

---

### Task 7: Fullständigt end-to-end-verifieringsskript

**Files:**
- Create: `supabase/tests/verify_valvet_rpcs.sql`

**Interfaces:**
- Consumes: alla RPC:er från Task 4–6.

- [ ] **Step 1: Skriv skriptet**

```sql
-- supabase/tests/verify_valvet_rpcs.sql
-- Manuellt körbart end-to-end-flöde mot staging. Kräver två test-nycklars
-- rå-värden (en Free-, en Pro-workspace) redan skapade via webbflödet
-- eller seed-scriptet, och deras sha256-hex-hashar.

-- 1. Tomt valv.
select * from public.list_my_items_for_key('<free-hash>');
-- Förväntat: 0 rader.

-- 2. Spara en prompt och en assistent (Free, inom kvoten).
select * from public.save_my_item_for_key('<free-hash>', gen_random_uuid(), 'prompt', 'Mitt första test', 'Innehåll här', 'Kategori A');
select * from public.save_my_item_for_key('<free-hash>', gen_random_uuid(), 'assistant', 'Min assistent', 'Du är en hjälpsam...', null);

-- 3. Lista, sök, hämta.
select * from public.list_my_items_for_key('<free-hash>');
-- Förväntat: 2 rader.
select * from public.search_my_items_for_key('<free-hash>', 'första');
-- Förväntat: 1 rad (prompten).
select * from public.get_my_item_for_key('<free-hash>', (select id from public.list_my_items_for_key('<free-hash>') limit 1));
-- Förväntat: 1 rad.

-- 4. Free kan INTE uppdatera/arkivera via MCP.
select * from public.update_my_item_for_key('<free-hash>', (select id from public.list_my_items_for_key('<free-hash>') limit 1), now());
-- Förväntat: ERROR 'Uppgradera till Pro för att uppdatera via MCP.'

-- 5. Pro: fullständig CRUD.
select * from public.save_my_item_for_key('<pro-hash>', gen_random_uuid(), 'prompt', 'Pro-test', 'Innehåll', null);
select * from public.update_my_item_for_key(
    '<pro-hash>',
    (select id from public.list_my_items_for_key('<pro-hash>') where title = 'Pro-test'),
    (select updated_at from public.list_my_items_for_key('<pro-hash>') where title = 'Pro-test'),
    'Pro-test (redigerad)'
);
select * from public.archive_my_item_for_key(
    '<pro-hash>',
    (select id from public.list_my_items_for_key('<pro-hash>', null, null, 'draft') where title = 'Pro-test (redigerad)'),
    true, false
);
-- Förväntat: alla lyckas, ingen ERROR.

-- 6. Sanity: type='assistant'-rader räknas ALDRIG mot kommunens 3-taket
-- (skapa en fjärde/femte assistant-rad på ett Free-workspace som redan har
-- 3 module='kommun'-prompts -- ska gå bra, ingen ERROR om kommun-taket).
```

- [ ] **Step 2: Kör mot staging, bekräfta alla punkter**

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/verify_valvet_rpcs.sql
git commit -m "test: add end-to-end verification script for Valvet RPCs"
```

---

## Klart-kriterier för Plan A

- Alla sex migrationsfiler applicerade och verifierade mot staging (inte bara lokalt granskade).
- `verify_valvet_limits_and_locking.sql` och `verify_valvet_rpcs.sql` båda körda med förväntat resultat.
- Kommunens befintliga 3/100-tak fortfarande verifierat oförändrat för `module='kommun'`-rader (Task 2, Step 3).
- Klart för Plan B (`mcp_promptbanken`-repot) och Plan C (`valvet_promptbanken`-repot) att bygga mot de sex `public.*_for_key`-funktionerna.
