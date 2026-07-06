# Pro + Delad arbetsyta (addon) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fasa ut `start` som org-licens och införa "Pro + Delad arbetsyta" som ett Pro-addon i den personliga världen, skilt från Förvaltning/Kommun (org-världen).

**Architecture:** Delad yta är en `workspaces`-rad (`type='organization'`, `plan='start'`, `license_id=null`) diskriminerad av en ny `shared_workspace_addons`-rad — aldrig en `pro_licenses`-rad. Åtkomst styrs av Pro-rättighet (`has_active_pro_entitlement`) och en kontextstyrd MCP-nyckelfunktion. `plus`/`enterprise` behåller org-licensmodellen oförändrad.

**Tech Stack:** Supabase Postgres (plpgsql, RLS), vanilla JS-frontend (Vite), Python stdio MCP-server (stdlib urllib).

**Spec:** `docs/superpowers/specs/2026-07-06-delad-arbetsyta-addon-design.md`

## Global Constraints

- **Ingen automatisk testrigg finns.** DB-tasks verifieras med SQL-skript i `supabase/tests/` som körs manuellt mot ett Supabase **staging**-projekt av användaren. "Kör testet" nedan = användaren kör SQL:en och bekräftar utfallet. Applicera aldrig en migration mot produktion förrän staging-verifieringen är grön.
- **Migrationer körs manuellt av användaren** mot Supabase. Migrationsfiler namnges `supabase/migrations/YYYYMMDDHHMMSS_<namn>.sql` med tidsstämpel senare än `20260704150000`.
- **Redigera aldrig redan körda migrationer.** Alla ändringar av befintliga funktioner sker via `create or replace` i en **ny** migrationsfil.
- **Publikt namn:** `start` får aldrig visas för användaren. Publikt heter det alltid **"Delad arbetsyta"**.
- **Delad yta skapar aldrig en `pro_licenses`-rad.**
- **Hård MCP-säkerhetsgräns:** en personlig Pro-nyckel når aldrig `plus`/`enterprise`-ytor, oavsett parametrar.
- **`script.js` importeras aldrig** (self-contained). All admin/auth-JS ligger i `src/*.js` (buntas av Vite).
- **MCP-nyckel = 256-bitars slumpvärde, SHA-256-hashat.** Klienten skickar hashen som `p_key_hash`.
- **Task 0 (säker förkontroll) måste vara grön innan någon annan migration appliceras.**

---

### Task 0: Säker förkontroll av befintlig `start`-org-data

**Files:**
- Create: `supabase/tests/precheck_start_licenses.sql`

**Interfaces:**
- Produces: en manuell go/no-go-grind. Om skriptet returnerar rader → STOPP.

- [ ] **Step 1: Skriv förkontroll-skriptet**

```sql
-- supabase/tests/precheck_start_licenses.sql
-- Kör mot staging OCH prod innan addon-migrationen appliceras.
-- Förväntat resultat: 0 rader från båda queries. Rader = oväntad
-- start-org-licensdata som måste hanteras medvetet först -> STOPP.

-- 1. Org-licenser på den gamla start-nivån.
select 'pro_licenses.start' as source, id, owner_user_id, created_at
  from public.pro_licenses
 where plan = 'start';

-- 2. Workspaces som är start OCH kopplade till en licens (gammal org-modell).
select 'workspace.start+license' as source, id, name, owner_user_id, license_id
  from public.workspaces
 where plan = 'start'
   and license_id is not null;
```

- [ ] **Step 2: Kör mot staging och prod**

Kör båda queries i Supabase SQL Editor mot staging och prod.
Expected: **0 rader** från båda. Om rader returneras: stoppa hela planen och
rapportera till användaren innan någon migration appliceras.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/precheck_start_licenses.sql
git commit -m "test: safe pre-check for legacy start-tier org licenses"
```

---

### Task 1: Tabell `shared_workspace_addons` + RLS

**Files:**
- Create: `supabase/migrations/20260706100000_shared_workspace_addons.sql`
- Create: `supabase/tests/shared_workspace_addons_rls.sql`

**Interfaces:**
- Produces: tabellen `public.shared_workspace_addons` (kolumner enligt spec §3.1), RLS så att ägare/billing-ägare/platform_owner läser.

- [ ] **Step 1: Skriv migrationen**

```sql
-- supabase/migrations/20260706100000_shared_workspace_addons.sql
-- Delad addon-yta: en workspaces-rad (type='organization', plan='start',
-- license_id=null) diskriminerad av en rad här. Helt skilt från pro_licenses.

create table if not exists public.shared_workspace_addons (
    id                     uuid primary key default gen_random_uuid(),
    workspace_id           uuid not null unique references public.workspaces(id) on delete cascade,
    owner_user_id          uuid not null references auth.users(id) on delete restrict,
    billing_owner_user_id  uuid not null references auth.users(id) on delete restrict,
    max_members            integer not null default 4  check (max_members >= 1),
    max_prompts            integer not null default 200 check (max_prompts >= 0),
    price_per_month        integer not null default 199 check (price_per_month >= 0),
    plan_source            text,
    plan_expires_at        timestamptz,
    status                 text not null default 'active' check (status in ('active', 'cancelled')),
    created_at             timestamptz not null default now()
);

alter table public.shared_workspace_addons enable row level security;

drop policy if exists "swa_owner_read" on public.shared_workspace_addons;
create policy "swa_owner_read"
on public.shared_workspace_addons
for select
to authenticated
using (
    owner_user_id = (select auth.uid())
    or billing_owner_user_id = (select auth.uid())
    or (select app_private.current_user_is_platform_owner())
);

drop policy if exists "swa_platform_owner_write" on public.shared_workspace_addons;
create policy "swa_platform_owner_write"
on public.shared_workspace_addons
for all
to authenticated
using ((select app_private.current_user_is_platform_owner()))
with check ((select app_private.current_user_is_platform_owner()));
```

- [ ] **Step 2: Skriv verifieringsskriptet**

```sql
-- supabase/tests/shared_workspace_addons_rls.sql
-- Kör efter migrationen. Förväntat: tabellen finns, RLS på.
select relrowsecurity from pg_class where relname = 'shared_workspace_addons';
-- Expected: t

select count(*) as policy_count from pg_policies
 where tablename = 'shared_workspace_addons';
-- Expected: 2
```

- [ ] **Step 3: Applicera migrationen mot staging**

Användaren kör migrationsfilen i Supabase SQL Editor mot staging.

- [ ] **Step 4: Kör verifieringen**

Kör `shared_workspace_addons_rls.sql`. Expected: `relrowsecurity = t`, `policy_count = 2`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260706100000_shared_workspace_addons.sql supabase/tests/shared_workspace_addons_rls.sql
git commit -m "feat(db): add shared_workspace_addons table with RLS"
```

---

### Task 2: `has_active_pro_entitlement(user_id)`

**Files:**
- Create: `supabase/migrations/20260706100500_has_active_pro_entitlement.sql`
- Create: `supabase/tests/has_active_pro_entitlement.sql`

**Interfaces:**
- Produces: `app_private.has_active_pro_entitlement(p_user_id uuid) returns boolean`. Konsumeras av Task 3 (create_shared_workspace) och Task 4 (join-trigger).

- [ ] **Step 1: Skriv migrationen**

```sql
-- supabase/migrations/20260706100500_has_active_pro_entitlement.sql
-- Abstraktion: "har användaren en aktiv Pro-rättighet?". MVP-källa =
-- egen aktiv personlig Pro-yta. Framtida källor (ägar-/org-/avtalstilldelad
-- Pro) utökar BARA denna funktion; anropande kod ändras inte.

create or replace function app_private.has_active_pro_entitlement(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
          from public.workspaces w
         where w.owner_user_id = p_user_id
           and w.type = 'personal'
           and w.plan = 'pro'
           and w.status = 'active'
           and (w.plan_expires_at is null or w.plan_expires_at > now())
    );
$$;

revoke all on function app_private.has_active_pro_entitlement(uuid) from public;
grant execute on function app_private.has_active_pro_entitlement(uuid) to authenticated;
```

- [ ] **Step 2: Skriv verifieringsskriptet**

```sql
-- supabase/tests/has_active_pro_entitlement.sql
-- Kräver en känd Pro-användare och en känd Free-användare i staging.
-- Ersätt UUID:erna nedan med riktiga staging-user_id.
select app_private.has_active_pro_entitlement('<PRO_USER_UUID>');   -- Expected: t
select app_private.has_active_pro_entitlement('<FREE_USER_UUID>');  -- Expected: f
```

- [ ] **Step 3: Applicera + kör verifiering mot staging**

Expected: `t` för Pro-användaren, `f` för Free-användaren.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260706100500_has_active_pro_entitlement.sql supabase/tests/has_active_pro_entitlement.sql
git commit -m "feat(db): add has_active_pro_entitlement entitlement abstraction"
```

---

### Task 3: `create_shared_workspace(p_name)` RPC

**Files:**
- Create: `supabase/migrations/20260706101000_create_shared_workspace.sql`
- Create: `supabase/tests/create_shared_workspace.sql`

**Interfaces:**
- Consumes: `app_private.has_active_pro_entitlement(uuid)` (Task 2), `app_private.slugify_candidate(text, text)` (befintlig), `shared_workspace_addons` (Task 1).
- Produces: `public.create_shared_workspace(p_name text) returns table(workspace_id uuid, addon_id uuid)`. Konsumeras av Task 10 (admin.js).

- [ ] **Step 1: Skriv migrationen**

```sql
-- supabase/migrations/20260706101000_create_shared_workspace.sql
-- Enda vägen till en ny delad addon-yta. Kräver att anroparen själv har
-- en aktiv Pro-rättighet. Skapar ALDRIG en pro_licenses-rad.

create or replace function public.create_shared_workspace(p_name text)
returns table(workspace_id uuid, addon_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id  uuid := auth.uid();
    new_workspace_id uuid;
    new_addon_id     uuid;
    resolved_name    text;
    candidate_slug   text;
    suffix           integer := 0;
begin
    if current_user_id is null then
        raise exception 'Inloggning krävs.';
    end if;

    if not app_private.has_active_pro_entitlement(current_user_id) then
        raise exception 'Du behöver en aktiv Pro-plan för att skapa en delad arbetsyta.';
    end if;

    resolved_name := coalesce(nullif(trim(p_name), ''), 'Delad arbetsyta');

    candidate_slug := app_private.slugify_candidate(resolved_name, 'arbetsyta');
    while exists (select 1 from public.workspaces where slug = candidate_slug) loop
        suffix := suffix + 1;
        candidate_slug := substr(app_private.slugify_candidate(resolved_name, 'arbetsyta'), 1, 44) || '-' || suffix::text;
    end loop;

    insert into public.workspaces (
        name, slug, type, plan, owner_user_id, license_id,
        max_prompts, api_enabled, mcp_enabled
    ) values (
        resolved_name, candidate_slug, 'organization', 'start', current_user_id, null,
        200, false, true
    )
    returning id into new_workspace_id;

    insert into public.shared_workspace_addons (
        workspace_id, owner_user_id, billing_owner_user_id,
        max_members, max_prompts, price_per_month, plan_source
    ) values (
        new_workspace_id, current_user_id, current_user_id,
        4, 200, 199, 'invoice'
    )
    returning id into new_addon_id;

    insert into public.profiles (user_id, workspace_id, role)
    values (current_user_id, new_workspace_id, 'workspace_owner');

    return query select new_workspace_id, new_addon_id;
end;
$$;

revoke all on function public.create_shared_workspace(text) from public;
grant execute on function public.create_shared_workspace(text) to authenticated;
```

Notera: `profiles`-inserten triggar join-triggern (Task 4). Task 4 måste vara
applicerad **före** att create_shared_workspace testas, annars saknas Pro-/max-4-kontrollen (ägaren har dock Pro, så inserten lyckas oavsett ordning). Applicera Task 4 före Task 3-testet.

- [ ] **Step 2: Skriv verifieringsskriptet**

```sql
-- supabase/tests/create_shared_workspace.sql
-- Kör som en inloggad Pro-användare (sätt request.jwt via Supabase-klient,
-- eller testa via frontend). Manuell kontroll efter anrop:
--   select * from public.workspaces where plan='start' and license_id is null;
--   -> 1 ny rad, type='organization', api_enabled=false, mcp_enabled=true
--   select * from public.shared_workspace_addons order by created_at desc limit 1;
--   -> max_members=4, max_prompts=200, price_per_month=199
--   select role from public.profiles where workspace_id=<ny yta> and user_id=<anropare>;
--   -> workspace_owner
-- Negativt: en Free-användare som anropar create_shared_workspace ska få
-- 'Du behöver en aktiv Pro-plan...'.
select 'se kommentarer' as note;
```

- [ ] **Step 3: Applicera (efter Task 4) + verifiera mot staging**

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260706101000_create_shared_workspace.sql supabase/tests/create_shared_workspace.sql
git commit -m "feat(db): add create_shared_workspace RPC (Pro-gated, no license)"
```

---

### Task 4: Join-trigger — Pro-krav + max 4 för addon-ytor

**Files:**
- Create: `supabase/migrations/20260706101500_addon_member_limit.sql`
- Create: `supabase/tests/addon_member_limit.sql`

**Interfaces:**
- Consumes: `app_private.has_active_pro_entitlement(uuid)` (Task 2), `shared_workspace_addons` (Task 1), `app_private.license_group_workspace_ids(uuid)` (befintlig).
- Produces: uppdaterad `app_private.enforce_org_member_limit()` som förgrenar på yttyp. Trigger `enforce_org_member_limit` på `profiles` finns redan (från `20260703110000`); vi ersätter bara funktionskroppen.

- [ ] **Step 1: Skriv migrationen**

```sql
-- supabase/migrations/20260706101500_addon_member_limit.sql
-- Förgrena medlemsgränsen: addon-ytor (license_id null + addon-rad) styrs av
-- shared_workspace_addons (Pro-krav + max_members). Org-licensytor (license_id
-- finns) styrs av pro_licenses som tidigare. Personliga ytor: ingen gräns.

create or replace function app_private.enforce_org_member_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record public.workspaces%rowtype;
    license_record   public.pro_licenses%rowtype;
    addon_record     public.shared_workspace_addons%rowtype;
    existing_count   integer;
begin
    select * into workspace_record
      from public.workspaces
     where id = new.workspace_id;

    if workspace_record.type <> 'organization' then
        return new;
    end if;

    -- Delad addon-yta: license_id null OCH en addon-rad finns.
    if workspace_record.license_id is null then
        select * into addon_record
          from public.shared_workspace_addons
         where workspace_id = workspace_record.id;

        if not found then
            -- Org-yta utan licens och utan addon-rad: ovanligt; blockera för säkerhets skull.
            raise exception 'Organisationsytan saknar både licens och addon-konfiguration.';
        end if;

        -- Hård Pro-spärr per medlem.
        if not app_private.has_active_pro_entitlement(new.user_id) then
            raise exception 'Alla medlemmar i en delad arbetsyta måste ha en aktiv Pro-plan.';
        end if;

        select count(*) into existing_count
          from public.profiles p
         where p.workspace_id = workspace_record.id;

        if existing_count >= coalesce(addon_record.max_members, 4) then
            raise exception 'Den delade arbetsytan har nått gränsen på % medlemmar.', addon_record.max_members;
        end if;

        return new;
    end if;

    -- Org-licensyta: befintlig licensgräns, summerad över syskonytor.
    select * into license_record
      from public.pro_licenses
     where id = workspace_record.license_id;

    select count(*) into existing_count
      from public.profiles p
     where p.workspace_id in (select app_private.license_group_workspace_ids(new.workspace_id));

    if existing_count >= coalesce(license_record.max_members_total, 1) then
        raise exception 'Licensen har nått gränsen på % medlemmar totalt.', license_record.max_members_total;
    end if;

    return new;
end;
$$;

revoke all on function app_private.enforce_org_member_limit() from public;
```

- [ ] **Step 2: Skriv verifieringsskriptet**

```sql
-- supabase/tests/addon_member_limit.sql
-- Efter att en addon-yta finns (Task 3) med ägaren som enda medlem:
-- 1. Lägg till en Pro-medlem via invite_org_member/redeem_org_join_code -> OK.
-- 2. Försök lägga till en Free-medlem -> ska faila:
--    'Alla medlemmar i en delad arbetsyta måste ha en aktiv Pro-plan.'
-- 3. Fyll ytan till 4 medlemmar, försök en femte Pro-medlem -> ska faila:
--    'Den delade arbetsytan har nått gränsen på 4 medlemmar.'
select 'manuell scenariokörning enligt kommentarer' as note;
```

- [ ] **Step 3: Applicera + verifiera mot staging**

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260706101500_addon_member_limit.sql supabase/tests/addon_member_limit.sql
git commit -m "feat(db): branch member limit for addon vs licensed org workspaces"
```

---

### Task 5: Mallgräns för addon-ytor i `enforce_content_access_model`

**Files:**
- Create: `supabase/migrations/20260706102000_addon_prompt_limit.sql`
- Create: `supabase/tests/addon_prompt_limit.sql`

**Interfaces:**
- Consumes: `shared_workspace_addons` (Task 1), `app_private.license_group_workspace_ids(uuid)` (befintlig).
- Produces: uppdaterad `app_private.enforce_content_access_model()` med en gren för org-ytor med `license_id IS NULL` som läser mallgränsen från `shared_workspace_addons`.

- [ ] **Step 1: Skriv migrationen**

Kopiera hela `enforce_content_access_model()` från `20260703110000_pro_licenses_and_orders.sql` och ersätt org-grenen (`elsif workspace_record.type = 'organization' and not is_platform_owner then ...`) så att den hanterar båda fallen:

```sql
-- supabase/migrations/20260706102000_addon_prompt_limit.sql
create or replace function app_private.enforce_content_access_model()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record   public.workspaces%rowtype;
    license_record     public.pro_licenses%rowtype;
    addon_record       public.shared_workspace_addons%rowtype;
    is_platform_owner  boolean;
    prompt_count       integer;
    prompt_limit       integer;
begin
    select * into workspace_record from public.workspaces where id = new.workspace_id;
    if not found then
        raise exception 'Workspace saknas.';
    end if;

    select app_private.current_user_is_platform_owner() into is_platform_owner;

    if new.type <> 'prompt' then
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
            -- Org-licensyta: summerad gräns över syskonytor.
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
            -- Delad addon-yta: gräns från shared_workspace_addons.
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

- [ ] **Step 2: Skriv verifieringsskriptet**

```sql
-- supabase/tests/addon_prompt_limit.sql
-- På en addon-yta: skapa mallar tills 200 finns, den 201:a ska faila:
--   'Den delade arbetsytan har nått gränsen på 200 mallar.'
-- Snabbtest: sänk tillfälligt max_prompts på addon-raden till 1 i staging,
-- skapa 1 mall (OK), försök en andra (faila), återställ sedan.
select 'manuell scenariokörning enligt kommentarer' as note;
```

- [ ] **Step 3: Applicera + verifiera mot staging**

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260706102000_addon_prompt_limit.sql supabase/tests/addon_prompt_limit.sql
git commit -m "feat(db): enforce addon prompt limit from shared_workspace_addons"
```

---

### Task 6: Blockera egna MCP-nycklar på addon-ytor i `enforce_mcp_key_limit`

**Files:**
- Create: `supabase/migrations/20260706102500_addon_no_own_keys.sql`
- Create: `supabase/tests/addon_no_own_keys.sql`

**Interfaces:**
- Consumes: `shared_workspace_addons` (Task 1), `app_private.license_group_workspace_ids(uuid)` (befintlig).
- Produces: uppdaterad `app_private.enforce_mcp_key_limit()` som blockerar mcp-nyckelskapande på org-ytor med `license_id IS NULL`.

- [ ] **Step 1: Skriv migrationen**

Kopiera `enforce_mcp_key_limit()` från `20260703110000` och lägg till addon-grenen:

```sql
-- supabase/migrations/20260706102500_addon_no_own_keys.sql
create or replace function app_private.enforce_mcp_key_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record public.workspaces%rowtype;
    license_record   public.pro_licenses%rowtype;
    existing_count   integer;
    key_limit        integer;
begin
    if not (new.scopes @> array['mcp']::text[]) then
        return new;
    end if;

    select * into workspace_record from public.workspaces where id = new.workspace_id;

    if workspace_record.type = 'personal' then
        key_limit := case when workspace_record.plan = 'pro' then 3 else 1 end;

        select count(*) into existing_count
          from public.api_keys
         where workspace_id = new.workspace_id
           and scopes @> array['mcp']::text[]
           and revoked_at is null;

        if existing_count >= key_limit then
            raise exception 'Personliga konton på %-planen kan ha max % aktiva MCP-nycklar.', workspace_record.plan, key_limit;
        end if;

    elsif workspace_record.type = 'organization' and workspace_record.license_id is null then
        -- Delad addon-yta: inga egna MCP-nycklar. Nås via medlemmarnas
        -- personliga Pro-nycklar.
        raise exception 'Delade arbetsytor har inga egna MCP-nycklar. Använd medlemmarnas personliga Pro-nycklar.';

    elsif workspace_record.type = 'organization' and workspace_record.license_id is not null then
        select * into license_record from public.pro_licenses where id = workspace_record.license_id;

        select count(*) into existing_count
          from public.api_keys k
         where k.workspace_id in (select app_private.license_group_workspace_ids(new.workspace_id))
           and k.scopes @> array['mcp']::text[]
           and k.revoked_at is null;

        key_limit := coalesce(license_record.max_mcp_keys_total, 1);

        if existing_count >= key_limit then
            raise exception 'Licensen har nått gränsen på % MCP-nycklar totalt.', key_limit;
        end if;
    end if;

    return new;
end;
$$;

revoke all on function app_private.enforce_mcp_key_limit() from public;
```

**Obs — Pro MCP-tak sänks 5→3** i den personliga grenen ovan (spec + planmatris). Detta är den enda platsen `enforce_mcp_key_limit` sätter Pro-taket.

- [ ] **Step 2: Uppdatera plan_limits pro-mcp-tak till 3**

Lägg i **samma** migrationsfil (samma logiska ändring):

```sql
-- Håll plan_limits konsekvent med enforce_mcp_key_limit: Pro = 3 MCP-nycklar.
create or replace function app_private.plan_limits(p_plan public.workspace_plan)
returns table(max_prompts integer, max_mcp_keys integer, max_members integer, max_workspaces integer)
language sql
immutable
set search_path = ''
as $$
    select
        case p_plan when 'free' then 3 when 'pro' then 100 when 'start' then 200 when 'plus' then 500 when 'enterprise' then 1000 else 3 end,
        case p_plan when 'free' then 1 when 'pro' then 3 when 'start' then 2 when 'plus' then 5 when 'enterprise' then 10 else 1 end,
        case p_plan when 'free' then 1 when 'pro' then 1 when 'start' then 10 when 'plus' then 50 when 'enterprise' then 250 else 1 end,
        case p_plan when 'free' then 1 when 'pro' then 1 when 'start' then 1 when 'plus' then 5 when 'enterprise' then 999999 else 1 end;
$$;
```

- [ ] **Step 3: Skriv verifieringsskriptet**

```sql
-- supabase/tests/addon_no_own_keys.sql
-- 1. Försök skapa mcp-nyckel på en addon-yta -> ska faila:
--    'Delade arbetsytor har inga egna MCP-nycklar...'
-- 2. Pro-personlig yta: 3 mcp-nycklar OK, den 4:e ska faila.
select (max_mcp_keys) from app_private.plan_limits('pro');  -- Expected: 3
```

- [ ] **Step 4: Applicera + verifiera mot staging**

Expected: `plan_limits('pro').max_mcp_keys = 3`; nyckelskapande på addon-yta failar.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260706102500_addon_no_own_keys.sql supabase/tests/addon_no_own_keys.sql
git commit -m "feat(db): block own MCP keys on addon workspaces; Pro key cap 5->3"
```

---

### Task 7: Kontextstyrd `get_workspace_prompts_for_key` + `list_shared_workspaces_for_key`

**Files:**
- Create: `supabase/migrations/20260706103000_context_mcp_scope.sql`
- Create: `supabase/tests/context_mcp_scope.sql`

**Interfaces:**
- Consumes: `shared_workspace_addons` (Task 1), `api_keys`, `workspaces`, `profiles`, `content_items`.
- Produces:
  - `app_private.get_workspace_prompts_for_key(p_key_hash text, p_scope text, p_workspace_id uuid)` + `public`-wrapper med samma signatur.
  - `public.list_shared_workspaces_for_key(p_key_hash text) returns table(workspace_id uuid, name text)`.

- [ ] **Step 1: Skriv migrationen**

```sql
-- supabase/migrations/20260706103000_context_mcp_scope.sql
-- Kontextstyrd hämtning. Behörighet != hämtning. Default = bara privat yta.
-- Hård gräns: personlig nyckel når aldrig plus/enterprise.

create or replace function app_private.get_workspace_prompts_for_key(
    p_key_hash     text,
    p_scope        text default null,
    p_workspace_id uuid default null
)
returns table(
    id uuid, title text, summary text, content text,
    visibility text, category text, audience text, status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key       public.api_keys%rowtype;
    v_key_ws    public.workspaces%rowtype;
    v_target_ws public.workspaces%rowtype;
    v_owner_id  uuid;
    v_is_primary_key boolean := false;
begin
    select k.* into v_key
      from public.api_keys k
     where k.key_hash   = p_key_hash
       and k.revoked_at is null
       and k.scopes     @> array['mcp']::text[]
     limit 1;
    if not found then return; end if;

    select w.* into v_key_ws
      from public.workspaces w
     where w.id = v_key.workspace_id
       and w.mcp_enabled = true
       and w.status = 'active';
    if not found then return; end if;

    -- ===== ORG-NYCKLAR (plus/enterprise): oförändrad världsseparation =====
    if v_key_ws.type = 'organization' and v_key_ws.license_id is not null then
        select (v_key.id = (
            select k2.id from public.api_keys k2
             where k2.workspace_id = v_key_ws.id
               and k2.revoked_at is null
               and k2.scopes @> array['mcp']::text[]
             order by k2.created_at asc limit 1
        )) into v_is_primary_key;

        return query
        select ci.id, ci.title, ci.summary, ci.content, ci.visibility::text,
               ci.category, ci.audience, ci.status::text
          from public.content_items ci
         where ci.workspace_id = v_key_ws.id
           and ci.type = 'prompt'
           and ci.status = 'published'
           and (
               ci.visibility = 'workspace'
               or (v_is_primary_key and ci.visibility = 'private' and ci.owner_user_id = v_key_ws.owner_user_id)
           );
        return;
    end if;

    -- ===== PERSONLIGA NYCKLAR (free/pro) =====
    if v_key_ws.type = 'personal' then
        v_owner_id := v_key_ws.owner_user_id;

        -- Kontext: en specifik delad addon-yta.
        if p_workspace_id is not null then
            select w.* into v_target_ws
              from public.workspaces w
             where w.id = p_workspace_id
               and w.type = 'organization'
               and w.license_id is null
               and w.plan = 'start'
               and w.status = 'active'
               and exists (select 1 from public.shared_workspace_addons a where a.workspace_id = w.id);
            if not found then return; end if;  -- inte en addon-yta -> hård gräns

            if not exists (
                select 1 from public.profiles p
                 where p.workspace_id = v_target_ws.id and p.user_id = v_owner_id
            ) then
                return;  -- inte medlem
            end if;

            return query
            select ci.id, ci.title, ci.summary, ci.content, ci.visibility::text,
                   ci.category, ci.audience, ci.status::text
              from public.content_items ci
             where ci.workspace_id = v_target_ws.id
               and ci.type = 'prompt'
               and ci.status = 'published'
               and ci.visibility = 'workspace';
            return;
        end if;

        -- Default / scope='private': bara användarens egna personliga mallar.
        return query
        select ci.id, ci.title, ci.summary, ci.content, ci.visibility::text,
               ci.category, ci.audience, ci.status::text
          from public.content_items ci
         where ci.workspace_id = v_key_ws.id
           and ci.type = 'prompt'
           and ci.status = 'published'
           and ci.owner_user_id = v_owner_id
           and ci.visibility in ('private', 'workspace');
        return;
    end if;

    -- Fallthrough (t.ex. org-yta utan licens = addon; sådana har inga nycklar): inget.
    return;
end;
$$;

revoke all on function app_private.get_workspace_prompts_for_key(text, text, uuid) from public;
grant execute on function app_private.get_workspace_prompts_for_key(text, text, uuid) to mcp_server;

-- Publik wrapper (samma förtroendemodell som tidigare).
create or replace function public.get_workspace_prompts_for_key(
    p_key_hash text, p_scope text default null, p_workspace_id uuid default null
)
returns table(
    id uuid, title text, summary text, content text,
    visibility text, category text, audience text, status text
)
language sql
security definer
set search_path = ''
as $$
    select * from app_private.get_workspace_prompts_for_key(p_key_hash, p_scope, p_workspace_id);
$$;

revoke all on function public.get_workspace_prompts_for_key(text, text, uuid) from public;
grant execute on function public.get_workspace_prompts_for_key(text, text, uuid) to anon, authenticated;

-- Discovery: vilka delade addon-ytor nyckelägaren är medlem i (metadata).
create or replace function public.list_shared_workspaces_for_key(p_key_hash text)
returns table(workspace_id uuid, name text)
language sql
security definer
set search_path = ''
as $$
    select w.id, w.name
      from public.api_keys k
      join public.workspaces kw on kw.id = k.workspace_id and kw.type = 'personal'
      join public.profiles p on p.user_id = kw.owner_user_id
      join public.workspaces w on w.id = p.workspace_id
      join public.shared_workspace_addons a on a.workspace_id = w.id
     where k.key_hash = p_key_hash
       and k.revoked_at is null
       and k.scopes @> array['mcp']::text[]
       and w.type = 'organization'
       and w.license_id is null
       and w.plan = 'start'
       and w.status = 'active';
$$;

revoke all on function public.list_shared_workspaces_for_key(text) from public;
grant execute on function public.list_shared_workspaces_for_key(text) to anon, authenticated;
```

**Obs — signaturändring.** Den gamla `get_workspace_prompts_for_key(text)` (en param) från `20260704110000` finns kvar som en separat överlagring. Droppa den explicit så inga anropare når den gamla obegränsade logiken:

```sql
drop function if exists app_private.get_workspace_prompts_for_key(text);
drop function if exists public.get_workspace_prompts_for_key(text);
```

- [ ] **Step 2: Skriv verifieringsskriptet**

```sql
-- supabase/tests/context_mcp_scope.sql
-- Sätt <PRO_KEY_HASH> = sha256 av en Pro-användares mcp-nyckel,
-- <ADDON_WS> = en addon-yta där användaren är medlem,
-- <ORG_WS> = en plus/enterprise-yta.
-- 1. Default: bara privata mallar.
select count(*) from public.get_workspace_prompts_for_key('<PRO_KEY_HASH>');  -- privata mallar
-- 2. scope=private: samma som default.
select count(*) from public.get_workspace_prompts_for_key('<PRO_KEY_HASH>', 'private', null);
-- 3. workspace_id = addon-yta där medlem: delade mallar därifrån.
select count(*) from public.get_workspace_prompts_for_key('<PRO_KEY_HASH>', null, '<ADDON_WS>');
-- 4. HÅRD GRÄNS: workspace_id = plus/enterprise-yta -> 0 rader.
select count(*) from public.get_workspace_prompts_for_key('<PRO_KEY_HASH>', null, '<ORG_WS>');  -- Expected: 0
-- 5. Discovery listar addon-ytan.
select * from public.list_shared_workspaces_for_key('<PRO_KEY_HASH>');
```

- [ ] **Step 3: Applicera + verifiera mot staging**

Kritiskt: query 4 måste ge **0 rader** (personlig nyckel når aldrig org-ytor).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260706103000_context_mcp_scope.sql supabase/tests/context_mcp_scope.sql
git commit -m "feat(db): context-driven MCP scope + shared-workspace discovery"
```

---

### Task 8: Ta bort `start`-grenen ur `create_pro_order`

**Files:**
- Create: `supabase/migrations/20260706103500_create_pro_order_no_start.sql`
- Create: `supabase/tests/create_pro_order_no_start.sql`

**Interfaces:**
- Produces: uppdaterad `public.create_pro_order(...)` som avvisar `start`.

- [ ] **Step 1: Skriv migrationen**

Kopiera `create_pro_order()` från `20260704150000_org_order_approval.sql` och lägg till en tidig guard direkt efter `if current_user_id is null`-kontrollen:

```sql
-- supabase/migrations/20260706103500_create_pro_order_no_start.sql
-- create_pro_order hanterar bara pro (direkt) och plus/enterprise (förfrågan).
-- start hör nu till create_shared_workspace och avvisas här.
-- (Klistra in HELA create_pro_order-kroppen från 20260704150000 och lägg till
--  guarden nedan; resten oförändrad.)

-- ... samma create or replace function public.create_pro_order(...) as 20260704150000 ...
-- direkt efter:
--     if current_user_id is null then
--         raise exception 'Inloggning krävs.';
--     end if;
-- lägg till:
--     if p_requested_plan = 'start' then
--         raise exception 'Delade arbetsytor skapas via create_shared_workspace(), inte create_pro_order().';
--     end if;
```

Implementeraren måste kopiera hela den befintliga funktionskroppen och infoga
guarden — inte lämna en `...`-platshållare. Se `20260704150000_org_order_approval.sql`
för den kompletta kroppen (rad 23–176).

- [ ] **Step 2: Skriv verifieringsskriptet**

```sql
-- supabase/tests/create_pro_order_no_start.sql
-- Anropa create_pro_order med p_requested_plan='start' -> ska faila med
-- 'Delade arbetsytor skapas via create_shared_workspace()...'.
select 'manuell kontroll' as note;
```

- [ ] **Step 3: Applicera + verifiera mot staging**

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260706103500_create_pro_order_no_start.sql supabase/tests/create_pro_order_no_start.sql
git commit -m "feat(db): reject start plan in create_pro_order (use create_shared_workspace)"
```

---

### Task 9: MCP-server — kontextparametrar + discovery-verktyg

**Files:**
- Modify: `mcp-server/server/pro_templates.py`
- Modify: `mcp-server/server/mcp_server.py`

**Interfaces:**
- Consumes: `get_workspace_prompts_for_key(p_key_hash, p_scope, p_workspace_id)` och `list_shared_workspaces_for_key(p_key_hash)` (Task 7).
- Produces: MCP-verktygen `list_my_private_prompts`, `list_shared_workspace_prompts(workspace_id)`, `list_my_shared_workspaces`.

- [ ] **Step 1: Utöka klienten med kontext + discovery**

I `mcp-server/server/pro_templates.py`, ersätt `_call_rpc` och `list_workspace_prompts` med parametriserade varianter:

```python
    def _call_rpc(self, function_name: str, extra: dict[str, Any] | None = None) -> list[dict[str, Any]]:
        url = f"{self.supabase_url}/rest/v1/rpc/{function_name}"
        payload: dict[str, Any] = {"p_key_hash": self._key_hash()}
        if extra:
            payload.update(extra)
        body = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=body,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "apikey": self.supabase_anon_key,
                "Authorization": f"Bearer {self.supabase_anon_key}",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"Kunde inte anropa {function_name} ({exc.code}): {detail}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"Kunde inte nå Supabase: {exc.reason}") from exc

    def list_private_prompts(self) -> list[dict[str, Any]]:
        return self._call_rpc("get_workspace_prompts_for_key", {"p_scope": "private", "p_workspace_id": None})

    def list_shared_prompts(self, workspace_id: str) -> list[dict[str, Any]]:
        return self._call_rpc("get_workspace_prompts_for_key", {"p_scope": None, "p_workspace_id": workspace_id})

    def list_shared_workspaces(self) -> list[dict[str, Any]]:
        return self._call_rpc("list_shared_workspaces_for_key")
```

Ta bort den gamla `list_workspace_prompts`-metoden.

- [ ] **Step 2: Ersätt MCP-verktyget `list_my_workspace_prompts`**

I `mcp-server/server/mcp_server.py`, byt ut `list_my_workspace_prompts` mot tre verktyg:

```python
@mcp.tool()
def list_my_private_prompts() -> dict[str, Any]:
    """List the caller's own private Pro prompts (personal workspace).
    Never returns other members' private prompts or organization prompts."""
    try:
        client = ProTemplatesClient.from_env()
    except ProTemplatesNotConfigured as exc:
        return {"error": str(exc), "prompts": []}
    return {"prompts": client.list_private_prompts()}


@mcp.tool()
def list_my_shared_workspaces() -> dict[str, Any]:
    """List the shared workspaces the caller's personal Pro key can access
    (id + name). Use a returned workspace_id with list_shared_workspace_prompts."""
    try:
        client = ProTemplatesClient.from_env()
    except ProTemplatesNotConfigured as exc:
        return {"error": str(exc), "workspaces": []}
    return {"workspaces": client.list_shared_workspaces()}


@mcp.tool()
def list_shared_workspace_prompts(workspace_id: str) -> dict[str, Any]:
    """List shared prompts from ONE shared workspace the caller is a member of.
    Requires an explicit workspace_id (from list_my_shared_workspaces)."""
    try:
        client = ProTemplatesClient.from_env()
    except ProTemplatesNotConfigured as exc:
        return {"error": str(exc), "prompts": []}
    return {"prompts": client.list_shared_prompts(workspace_id)}
```

- [ ] **Step 3: Röktesta MCP-servern lokalt**

Run: `cd mcp-server && npm run dev` och skicka en `tools/list`-förfrågan (eller
starta i en MCP-klient). Expected: de tre nya verktygen listas, inga importfel.

- [ ] **Step 4: Commit**

```bash
git add mcp-server/server/pro_templates.py mcp-server/server/mcp_server.py
git commit -m "feat(mcp): context-driven prompt tools + shared workspace discovery"
```

---

### Task 10: Frontend UI/copy — Delad arbetsyta som Pro-addon

**Files:**
- Modify: `planer.html`
- Modify: `admin.html`
- Modify: `src/admin.js`

**Interfaces:**
- Consumes: `public.create_shared_workspace(p_name)` (Task 3).

- [ ] **Step 1: `planer.html` — Arbetsyta-kort som Pro-tillägg**

Ändra Arbetsyta-kortet: pris `Pro + 199 kr/mån`, målgrupp "Litet team med Pro",
värde "Delad yta för Pro-användare", funktioner: `✓ 200 delade mallar`,
`✓ Upp till 4 Pro-användare`, `✓ Delas via medlemmarnas personliga Pro-nycklar`,
`✗ Egna arbetsyte-nycklar`. Ta bort MCP-nyckelraden. Ändra Pro-kortet:
`✓ 3 MCP-nycklar` (ej 5) och **ta bort** `✓ API-nycklar` (API=Nej i MVP).
Uppdatera "Vad är skillnaden"-avsnittet: Arbetsyta = Pro + delad yta där alla har egen Pro.

- [ ] **Step 2: `admin.html` — uppgraderingsval**

I `<select name="plan">`: byt `<option value="start">`-texten till
`Delad arbetsyta (Pro-tillägg, upp till 4 medlemmar)`. Behåll `value="start"`.

- [ ] **Step 3: `src/admin.js` — dirigera start till create_shared_workspace**

I `planPricing`: `start: { amount: 'Pro + 199 kr/mån', note: 'delad yta, upp till 4 Pro-användare · faktureras i efterskott', selfService: true }`.
I `confirmUpgradeOrder()`: förgrena på plan innan RPC-anropet:

```javascript
  if (order.plan === 'start') {
    const { data, error } = await supabase.rpc('create_shared_workspace', {
      p_name: order.workspaceName || order.companyName
    });
    if (error) {
      setUpgradeStatus(error.message || 'Kunde inte skapa den delade arbetsytan.', true);
      return;
    }
    const created = Array.isArray(data) ? data[0] : data;
    setUpgradeStatus('Delad arbetsyta skapad. Faktura på 199 kr/mån skickas.');
    upgradeForm.reset();
    syncUpgradeWorkspacesField();
    if (created?.workspace_id) {
      await switchToWorkspace(created.workspace_id);
    } else {
      await loadProfile(state.user);
    }
    return;
  }
  // ... befintligt create_pro_order-anrop för pro/plus/enterprise ...
```

- [ ] **Step 4: Bygg och röktesta**

Run: `npm run build`
Expected: bygget lyckas, inga fel. Manuellt: uppgraderingsvyn visar
"Delad arbetsyta" och Pro-kortet visar 3 MCP-nycklar, ingen API-rad.

- [ ] **Step 5: Commit**

```bash
git add planer.html admin.html src/admin.js
git commit -m "feat(ui): Delad arbetsyta as Pro addon; Pro 3 MCP keys, no API"
```

---

### Task 11: Uppdatera seed-scriptet

**Files:**
- Modify: `scripts/seed-test-users.mjs`

**Interfaces:**
- Consumes: den nya modellen (addon-yta via create_shared_workspace eller direkt insert).

- [ ] **Step 1: Ersätt `start`-org-seed med addon-modell**

Ändra seed-datat så att den delade testytan skapas som addon: skapa en
`type='organization'`, `plan='start'`, `license_id=null`-workspace och en
`shared_workspace_addons`-rad, och gör test-medlemmarna till Pro-användare
(egna personliga `plan='pro'`-ytor) så join-triggern släpper in dem. Ta bort
alla `pro_licenses`-rader med `plan='start'` ur seed.

- [ ] **Step 2: Kör seed mot staging**

Run: `npm run seed:test-users` (med `.env.seed.local` mot staging).
Expected: inga fel; testanvändare i den delade ytan har egen Pro.

- [ ] **Step 3: Commit**

```bash
git add scripts/seed-test-users.mjs
git commit -m "chore(seed): create shared workspace via addon model, not start license"
```

---

## Self-Review

**Spec coverage:**
- §3.1 tabell → Task 1 ✓
- §4 entitlement → Task 2 ✓
- §5 create_shared_workspace → Task 3 ✓
- §6 join-spärr → Task 4 ✓
- §8 mallgräns → Task 5; nyckelblock + Pro 3 → Task 6 ✓
- §7 kontext-MCP + discovery → Task 7 ✓
- §9 create_pro_order start bort → Task 8 ✓
- §10 UI-copy → Task 10; MCP-server → Task 9 ✓
- §11 förkontroll → Task 0; seed → Task 11 ✓
- §12 verifieringspunkter → täcks av tests i Task 4/6/7/8 ✓

**Placeholder scan:** Task 8 medvetet instruerar att klistra in befintlig
funktionskropp (för lång att duplicera) med exakt radhänvisning — inte en dold
platshållare. Övriga tasks har komplett SQL/JS.

**Type consistency:** `get_workspace_prompts_for_key(text, text, uuid)` används
konsekvent i Task 7 (DB) och Task 9 (Python skickar `p_scope`/`p_workspace_id`).
`create_shared_workspace(p_name)` → `(workspace_id, addon_id)` konsekvent i Task 3
och Task 10. `has_active_pro_entitlement(uuid)` konsekvent Task 2/3/4.

## Beroendeordning (viktig)

Task 0 → 1 → 2 → (4 före 3-testet) → 3 → 5 → 6 → 7 → 8 → 9 → 10 → 11.
Task 4 måste appliceras före Task 3 testas (join-triggern läser addon-raden).
```
