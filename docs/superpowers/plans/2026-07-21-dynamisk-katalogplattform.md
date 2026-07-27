# Dynamisk katalogplattform Implementation Plan

**Status 2026-07-27:** Delvis genomförd. Datamodell, publika läs-RPC:er,
kontextvarianter och publicerad katalog används av webb och MCP. Ett separat
Admin-MCP med gransknings- och publiceringsflöde återstår som en senare fas.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bygg en databasbaserad katalogplattform där redaktionen kan skapa prompts och paket/arbetssätt som utkast, lägga till kontextvarianter, och publicera dem så att samma publicerade innehåll kan läsas av både webb och hostad MCP utan rebuild.

**Architecture:** Lösningen bygger på en ren relationsmodell i Supabase med baskärnor (`catalog_prompts`, `catalog_packages`), kontextvarianter som child-rader och paketrelationer i en separat kopplingstabell. Skrivflödet går via admin-/admin-MCP-orienterade RPC:er som alltid skapar utkast först; läsflödet går via publicerade read-RPC:er med inbyggd fallback från vald kontext till `generell`.

**Tech Stack:** PostgreSQL/Supabase (DDL, plpgsql RPC, RLS/grants), vanilla JS i `src/admin.js` och `admin.html`, Python/FastMCP i `mcp-server/server/`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-21-dynamisk-katalogplattform-design.md` styr hela planen.
- Databasen är master för publicerat kataloginnehåll; repo/MCP-kod ska inte behöva ändras för nya paket eller katalogprompts.
- Arbetssätt modelleras som `package_type='workflow'`, inte som ett separat kärnobjekt.
- Varje prompt och varje paket måste ha en `generell` variant före publicering.
- Kontextvarianter lagras som separata child-rader, inte som huvudsaklig JSON-overridemodell.
- Första versionens statusmodell är exakt `draft` och `published`.
- Publicerat paket får bara innehålla publicerade prompts.
- Frontend och hostad MCP ska läsa samma publicerade katalogdata.
- Auth/auktorisering för admin-MCP och sök/indexering ligger utanför denna plan.
- Följ repo-regeln: migrationsfiler under `supabase/migrations/` med säkra `create or replace`-mönster, verifieringsskript under `supabase/tests/`.

---

### Task 1: DB-schema för katalogkärna och kontextvarianter

**Files:**
- Create: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/migrations/20260721100000_catalog_core.sql`
- Create: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/tests/verify_catalog_core.sql`

**Interfaces:**
- Consumes: befintligt Supabase-schema och migrationskonventioner i `supabase/migrations/`.
- Produces:
  - tabell `public.catalog_prompts`
  - tabell `public.catalog_prompt_variants`
  - tabell `public.catalog_packages`
  - tabell `public.catalog_package_variants`
  - tabell `public.catalog_package_items`
  - typer/checks för `context_key`, `status`, `package_type`

- [ ] **Step 1: Skriv verifieringsfilen först**

`verify_catalog_core.sql`:

```sql
-- verify_catalog_core.sql
-- Manuell checklista för katalogkärnans schema.

select to_regclass('public.catalog_prompts') is not null as has_catalog_prompts;
select to_regclass('public.catalog_prompt_variants') is not null as has_catalog_prompt_variants;
select to_regclass('public.catalog_packages') is not null as has_catalog_packages;
select to_regclass('public.catalog_package_variants') is not null as has_catalog_package_variants;
select to_regclass('public.catalog_package_items') is not null as has_catalog_package_items;

select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'catalog_prompt_variants'
order by ordinal_position;

select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'catalog_package_items'
order by ordinal_position;
```

- [ ] **Step 2: Skapa tabellerna i migrationen**

`20260721100000_catalog_core.sql` ska definiera:

```sql
create table if not exists public.catalog_prompts (
    id uuid primary key default gen_random_uuid(),
    slug text not null unique,
    status text not null check (status in ('draft', 'published')),
    prompt_kind text not null default 'prompt',
    icon_key text,
    image_key text,
    color_theme text,
    created_by uuid,
    updated_by uuid,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
```

```sql
create table if not exists public.catalog_prompt_variants (
    id uuid primary key default gen_random_uuid(),
    prompt_id uuid not null references public.catalog_prompts(id) on delete cascade,
    context_key text not null check (context_key in ('generell', 'skola', 'kommun', 'företag', 'förening', 'privat')),
    title text not null,
    summary text not null,
    prompt_text text not null,
    example_input text,
    audience_label text,
    tone_hint text,
    context_notes text,
    suggested_variables jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint catalog_prompt_variants_prompt_context_key unique (prompt_id, context_key)
);
```

```sql
create table if not exists public.catalog_packages (
    id uuid primary key default gen_random_uuid(),
    slug text not null unique,
    status text not null check (status in ('draft', 'published')),
    package_type text not null check (package_type in ('collection', 'workflow')),
    icon_key text,
    image_key text,
    color_theme text,
    created_by uuid,
    updated_by uuid,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
```

```sql
create table if not exists public.catalog_package_variants (
    id uuid primary key default gen_random_uuid(),
    package_id uuid not null references public.catalog_packages(id) on delete cascade,
    context_key text not null check (context_key in ('generell', 'skola', 'kommun', 'företag', 'förening', 'privat')),
    title text not null,
    summary text not null,
    intro_text text,
    audience_label text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint catalog_package_variants_package_context_key unique (package_id, context_key)
);
```

```sql
create table if not exists public.catalog_package_items (
    id uuid primary key default gen_random_uuid(),
    package_id uuid not null references public.catalog_packages(id) on delete cascade,
    prompt_id uuid not null references public.catalog_prompts(id) on delete restrict,
    sort_order integer not null,
    step_title text,
    step_intro text,
    is_required boolean not null default true,
    constraint catalog_package_items_package_prompt_key unique (package_id, prompt_id)
);
```

- [ ] **Step 3: Lägg till `updated_at`-trigger eller explicit update-funktion**

Om repot redan använder en generell updated-at-trigger, återanvänd den. Annars lägg in en enkel funktion:

```sql
create or replace function app_private.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
```

och triggra den på de fyra tabeller som har `updated_at`.

- [ ] **Step 4: Kör verifieringskommandon**

Run:

```powershell
rg -n "catalog_(prompts|prompt_variants|packages|package_variants|package_items)" supabase/migrations/20260721100000_catalog_core.sql
```

Expected: träffar för alla fem tabeller.

Run:

```powershell
Get-Content 'supabase/tests/verify_catalog_core.sql'
```

Expected: filen innehåller `to_regclass(...)`-kontroller för alla fem tabeller.

- [ ] **Step 5: Commit**

```powershell
git add supabase/migrations/20260721100000_catalog_core.sql supabase/tests/verify_catalog_core.sql
git commit -m "feat(db): add core catalog schema for prompts and packages"
```

### Task 2: Publiceringsregler och write-RPC:er för prompts

**Files:**
- Create: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/migrations/20260721110000_catalog_prompt_rpcs.sql`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/tests/verify_catalog_core.sql`

**Interfaces:**
- Consumes:
  - `public.catalog_prompts`
  - `public.catalog_prompt_variants`
- Produces:
  - `public.create_catalog_prompt(...) returns public.catalog_prompts`
  - `public.upsert_catalog_prompt_variant(...) returns public.catalog_prompt_variants`
  - `public.publish_catalog_prompt(p_prompt_id uuid) returns public.catalog_prompts`

- [ ] **Step 1: Utöka verifieringsfilen med promptflöden**

Lägg till i `verify_catalog_core.sql`:

```sql
-- Promptflöde
select proname
from pg_proc
where proname in ('create_catalog_prompt', 'upsert_catalog_prompt_variant', 'publish_catalog_prompt')
order by proname;
```

- [ ] **Step 2: Implementera create-RPC för promptutkast**

`20260721110000_catalog_prompt_rpcs.sql` ska innehålla en public wrapper över en app_private-funktion:

```sql
create or replace function app_private.create_catalog_prompt(
    p_slug text,
    p_title text,
    p_summary text,
    p_prompt_text text,
    p_icon_key text default null,
    p_image_key text default null,
    p_color_theme text default null
)
returns public.catalog_prompts
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_prompt public.catalog_prompts;
begin
    insert into public.catalog_prompts (
        slug, status, prompt_kind, icon_key, image_key, color_theme, created_by, updated_by
    ) values (
        p_slug, 'draft', 'prompt', p_icon_key, p_image_key, p_color_theme, auth.uid(), auth.uid()
    )
    returning * into v_prompt;

    insert into public.catalog_prompt_variants (
        prompt_id, context_key, title, summary, prompt_text
    ) values (
        v_prompt.id, 'generell', p_title, p_summary, p_prompt_text
    );

    return v_prompt;
end;
$$;
```

- [ ] **Step 3: Implementera upsert-RPC för promptvarianter**

```sql
create or replace function app_private.upsert_catalog_prompt_variant(
    p_prompt_id uuid,
    p_context_key text,
    p_title text,
    p_summary text,
    p_prompt_text text,
    p_example_input text default null,
    p_audience_label text default null,
    p_tone_hint text default null,
    p_context_notes text default null,
    p_suggested_variables jsonb default '{}'::jsonb
)
returns public.catalog_prompt_variants
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_variant public.catalog_prompt_variants;
begin
    insert into public.catalog_prompt_variants (
        prompt_id, context_key, title, summary, prompt_text, example_input,
        audience_label, tone_hint, context_notes, suggested_variables
    ) values (
        p_prompt_id, p_context_key, p_title, p_summary, p_prompt_text, p_example_input,
        p_audience_label, p_tone_hint, p_context_notes, coalesce(p_suggested_variables, '{}'::jsonb)
    )
    on conflict (prompt_id, context_key) do update
    set title = excluded.title,
        summary = excluded.summary,
        prompt_text = excluded.prompt_text,
        example_input = excluded.example_input,
        audience_label = excluded.audience_label,
        tone_hint = excluded.tone_hint,
        context_notes = excluded.context_notes,
        suggested_variables = excluded.suggested_variables
    returning * into v_variant;

    update public.catalog_prompts
       set updated_by = auth.uid()
     where id = p_prompt_id;

    return v_variant;
end;
$$;
```

- [ ] **Step 4: Implementera publish-RPC för prompt**

Publicering ska blockeras om `generell` saknas:

```sql
create or replace function app_private.publish_catalog_prompt(p_prompt_id uuid)
returns public.catalog_prompts
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_prompt public.catalog_prompts;
begin
    if not exists (
        select 1
          from public.catalog_prompt_variants
         where prompt_id = p_prompt_id
           and context_key = 'generell'
    ) then
        raise exception 'Prompten måste ha en generell variant innan publicering.';
    end if;

    update public.catalog_prompts
       set status = 'published',
           updated_by = auth.uid()
     where id = p_prompt_id
     returning * into v_prompt;

    return v_prompt;
end;
$$;
```

- [ ] **Step 5: Kör verifieringskommandon**

Run:

```powershell
rg -n "create_catalog_prompt|upsert_catalog_prompt_variant|publish_catalog_prompt" supabase/migrations/20260721110000_catalog_prompt_rpcs.sql
```

Expected: träffar på alla tre funktioner.

Run:

```powershell
rg -n "Prompten måste ha en generell variant" supabase/migrations/20260721110000_catalog_prompt_rpcs.sql
```

Expected: exakt en träff i publish-funktionen.

- [ ] **Step 6: Commit**

```powershell
git add supabase/migrations/20260721110000_catalog_prompt_rpcs.sql supabase/tests/verify_catalog_core.sql
git commit -m "feat(db): add prompt draft and publish RPCs"
```

### Task 3: Publiceringsregler och write-RPC:er för paket/arbetssätt

**Files:**
- Create: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/migrations/20260721120000_catalog_package_rpcs.sql`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/tests/verify_catalog_core.sql`

**Interfaces:**
- Consumes:
  - `public.catalog_packages`
  - `public.catalog_package_variants`
  - `public.catalog_package_items`
  - `public.catalog_prompts`
- Produces:
  - `public.create_catalog_package(...) returns public.catalog_packages`
  - `public.upsert_catalog_package_variant(...) returns public.catalog_package_variants`
  - `public.add_prompt_to_catalog_package(...) returns public.catalog_package_items`
  - `public.update_catalog_package_item(...) returns public.catalog_package_items`
  - `public.remove_prompt_from_catalog_package(...) returns void`
  - `public.publish_catalog_package(p_package_id uuid) returns public.catalog_packages`

- [ ] **Step 1: Utöka verifieringsfilen med paketflöden**

Lägg till i `verify_catalog_core.sql`:

```sql
-- Paketflöde
select proname
from pg_proc
where proname in (
  'create_catalog_package',
  'upsert_catalog_package_variant',
  'add_prompt_to_catalog_package',
  'update_catalog_package_item',
  'remove_prompt_from_catalog_package',
  'publish_catalog_package'
)
order by proname;
```

- [ ] **Step 2: Implementera create/upsert för paket**

Minimikod:

```sql
create or replace function app_private.create_catalog_package(
    p_slug text,
    p_package_type text,
    p_title text,
    p_summary text,
    p_intro_text text default null,
    p_icon_key text default null,
    p_image_key text default null,
    p_color_theme text default null
)
returns public.catalog_packages
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_package public.catalog_packages;
begin
    insert into public.catalog_packages (
        slug, status, package_type, icon_key, image_key, color_theme, created_by, updated_by
    ) values (
        p_slug, 'draft', p_package_type, p_icon_key, p_image_key, p_color_theme, auth.uid(), auth.uid()
    )
    returning * into v_package;

    insert into public.catalog_package_variants (
        package_id, context_key, title, summary, intro_text
    ) values (
        v_package.id, 'generell', p_title, p_summary, p_intro_text
    );

    return v_package;
end;
$$;
```

- [ ] **Step 3: Implementera relation-RPC:er för paketinnehåll**

```sql
create or replace function app_private.add_prompt_to_catalog_package(
    p_package_id uuid,
    p_prompt_id uuid,
    p_sort_order integer,
    p_step_title text default null,
    p_step_intro text default null,
    p_is_required boolean default true
)
returns public.catalog_package_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_item public.catalog_package_items;
begin
    insert into public.catalog_package_items (
        package_id, prompt_id, sort_order, step_title, step_intro, is_required
    ) values (
        p_package_id, p_prompt_id, p_sort_order, p_step_title, p_step_intro, p_is_required
    )
    returning * into v_item;

    return v_item;
end;
$$;
```

`update_catalog_package_item` ska uppdatera `sort_order`, `step_title`, `step_intro`, `is_required`.  
`remove_prompt_from_catalog_package` ska radera relationen via `package_id` + `prompt_id`.

- [ ] **Step 4: Implementera publish-RPC för paket**

Publicering ska blockera om:

- `generell` paketvariant saknas
- paketet saknar items
- någon ingående prompt inte är `published`

```sql
create or replace function app_private.publish_catalog_package(p_package_id uuid)
returns public.catalog_packages
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_package public.catalog_packages;
begin
    if not exists (
        select 1 from public.catalog_package_variants
         where package_id = p_package_id and context_key = 'generell'
    ) then
        raise exception 'Paketet måste ha en generell variant innan publicering.';
    end if;

    if not exists (
        select 1 from public.catalog_package_items where package_id = p_package_id
    ) then
        raise exception 'Paketet måste innehålla minst en prompt innan publicering.';
    end if;

    if exists (
        select 1
          from public.catalog_package_items cpi
          join public.catalog_prompts cp on cp.id = cpi.prompt_id
         where cpi.package_id = p_package_id
           and cp.status <> 'published'
    ) then
        raise exception 'Alla prompts i paketet måste vara publicerade innan paketet kan publiceras.';
    end if;

    update public.catalog_packages
       set status = 'published',
           updated_by = auth.uid()
     where id = p_package_id
     returning * into v_package;

    return v_package;
end;
$$;
```

- [ ] **Step 5: Kör verifieringskommandon**

Run:

```powershell
rg -n "Paketet måste ha en generell variant|Paketet måste innehålla minst en prompt|Alla prompts i paketet måste vara publicerade" supabase/migrations/20260721120000_catalog_package_rpcs.sql
```

Expected: tre träffar, en per regel.

- [ ] **Step 6: Commit**

```powershell
git add supabase/migrations/20260721120000_catalog_package_rpcs.sql supabase/tests/verify_catalog_core.sql
git commit -m "feat(db): add package and workflow draft/publish RPCs"
```

### Task 4: Read-RPC:er för publicerad katalog med kontextfallback

**Files:**
- Create: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/migrations/20260721130000_catalog_read_rpcs.sql`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/tests/verify_catalog_core.sql`

**Interfaces:**
- Consumes:
  - samtliga katalogtabeller
- Produces:
  - `public.list_published_prompts(p_context_key text)`
  - `public.get_published_prompt(p_slug text, p_context_key text)`
  - `public.list_published_packages(p_context_key text, p_package_type text default null)`
  - `public.get_published_package(p_slug text, p_context_key text)`
  - `public.list_published_package_prompts(p_package_slug text, p_context_key text)`

- [ ] **Step 1: Lägg till read-funktionerna i verifieringsfilen**

```sql
select proname
from pg_proc
where proname in (
  'list_published_prompts',
  'get_published_prompt',
  'list_published_packages',
  'get_published_package',
  'list_published_package_prompts'
)
order by proname;
```

- [ ] **Step 2: Implementera list/get för prompts med fallback**

Mönster:

```sql
left join public.catalog_prompt_variants requested
  on requested.prompt_id = cp.id
 and requested.context_key = p_context_key
left join public.catalog_prompt_variants fallback
  on fallback.prompt_id = cp.id
 and fallback.context_key = 'generell'
```

och returnera:

```sql
coalesce(requested.title, fallback.title) as title
```

Samma mönster ska gälla för summary, prompt_text, example_input, audience_label och tone_hint.

- [ ] **Step 3: Implementera list/get för paket med fallback**

Använd samma `coalesce(requested.*, fallback.*)`-mönster för:

- title
- summary
- intro_text
- audience_label

`list_published_packages` ska kunna filtrera på `package_type` när parameter anges.

- [ ] **Step 4: Implementera list för prompts i publicerat paket**

`list_published_package_prompts` ska:

- hitta publicerat paket via slug
- slå upp paketets publicerade prompts via `catalog_package_items`
- returnera både promptfält och relationfält:
  - `sort_order`
  - `step_title`
  - `step_intro`
  - `is_required`

- [ ] **Step 5: Kör verifieringskommandon**

Run:

```powershell
rg -n "coalesce\\(requested|context_key = 'generell'|list_published_package_prompts" supabase/migrations/20260721130000_catalog_read_rpcs.sql
```

Expected: tydliga fallbackträffar och en funktion för package-prompts.

- [ ] **Step 6: Commit**

```powershell
git add supabase/migrations/20260721130000_catalog_read_rpcs.sql supabase/tests/verify_catalog_core.sql
git commit -m "feat(db): add published catalog read RPCs with context fallback"
```

### Task 5: Chattskapande-RPC:er för utkast

**Files:**
- Create: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/migrations/20260721140000_catalog_chat_rpcs.sql`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/tests/verify_catalog_core.sql`

**Interfaces:**
- Consumes:
  - write-RPC:erna för prompts och paket
- Produces:
  - `public.create_prompt_draft_from_chat(...) returns public.catalog_prompts`
  - `public.create_package_draft_from_chat(...) returns public.catalog_packages`

- [ ] **Step 1: Lägg till verifieringskontroll**

```sql
select proname
from pg_proc
where proname in ('create_prompt_draft_from_chat', 'create_package_draft_from_chat')
order by proname;
```

- [ ] **Step 2: Implementera promptfrån-chatt som wrapper**

`create_prompt_draft_from_chat` ska i första versionen vara en tunn wrapper över `create_catalog_prompt(...)`, men med extra parametrar för:

- `p_example_input`
- `p_audience_label`
- `p_tone_hint`
- `p_suggested_variables`

och direkt efter promptskapandet ska den anropa `upsert_catalog_prompt_variant(...)` för att fylla dessa fält på den generella varianten.

- [ ] **Step 3: Implementera paketfrån-chatt med underliggande prompts**

`create_package_draft_from_chat` ska i första versionen acceptera ett JSONB-argument för promptutkast, t.ex.:

```sql
[
  {
    "slug": "svart-mail-svar",
    "title": "Svara på ett svårt mejl",
    "summary": "Hjälper användaren att svara sakligt och lugnt.",
    "prompt_text": "..."
  }
]
```

Funktionen ska:

- skapa paketutkast med `create_catalog_package(...)`
- loopa över JSON-listan
- skapa varje promptutkast med `create_catalog_prompt(...)`
- skapa relation i `catalog_package_items` med stigande `sort_order`

- [ ] **Step 4: Kör verifieringskommandon**

Run:

```powershell
rg -n "create_prompt_draft_from_chat|create_package_draft_from_chat|jsonb_array_elements" supabase/migrations/20260721140000_catalog_chat_rpcs.sql
```

Expected: träffar på båda funktionerna och JSON-loopning i paketfunktionen.

- [ ] **Step 5: Commit**

```powershell
git add supabase/migrations/20260721140000_catalog_chat_rpcs.sql supabase/tests/verify_catalog_core.sql
git commit -m "feat(db): add chat-driven draft creation for prompts and packages"
```

### Task 6: Admin-UI för grundläggande katalogredigering

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/admin.html`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/src/admin.js`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/style.css`

**Interfaces:**
- Consumes:
  - `create_catalog_prompt`
  - `upsert_catalog_prompt_variant`
  - `publish_catalog_prompt`
  - `create_catalog_package`
  - `upsert_catalog_package_variant`
  - `add_prompt_to_catalog_package`
  - `publish_catalog_package`
- Produces:
  - enkel adminsektion för katalogutkast
  - enkel adminsektion för paket/arbetssättutkast

- [ ] **Step 1: Lägg till separata sektioner i admin.html**

Lägg till två nya sektioner under plattformsadmin eller egen redaktionsyta:

```html
<section class="workspace-section" id="katalog-prompts" data-platform-only hidden>
  <div class="workspace-section-heading">
    <div>
      <h2>Katalogprompts</h2>
      <p>Skapa och publicera öppna prompts.</p>
    </div>
  </div>
</section>
```

```html
<section class="workspace-section" id="katalog-paket" data-platform-only hidden>
  <div class="workspace-section-heading">
    <div>
      <h2>Paket och arbetssätt</h2>
      <p>Skapa samlingar och arbetsflöden.</p>
    </div>
  </div>
</section>
```

- [ ] **Step 2: Implementera minsta promptformuläret i admin.js**

Formuläret ska i första versionen skicka:

```js
await supabase.rpc('create_catalog_prompt', {
  p_slug: slug,
  p_title: title,
  p_summary: summary,
  p_prompt_text: promptText,
  p_icon_key: iconKey || null,
  p_image_key: imageKey || null,
  p_color_theme: colorTheme || null
});
```

och visa svensk status via befintligt `setStatus`/`setErrorStatus`.

- [ ] **Step 3: Implementera minsta paketformuläret i admin.js**

Formuläret ska kunna skapa:

```js
await supabase.rpc('create_catalog_package', {
  p_slug: slug,
  p_package_type: packageType,
  p_title: title,
  p_summary: summary,
  p_intro_text: introText || null,
  p_icon_key: iconKey || null,
  p_image_key: imageKey || null,
  p_color_theme: colorTheme || null
});
```

och därefter lägga till utvalda prompts med `add_prompt_to_catalog_package`.

- [ ] **Step 4: Implementera publicera-knappar**

Knapparna ska anropa:

```js
await supabase.rpc('publish_catalog_prompt', { p_prompt_id: promptId });
```

och

```js
await supabase.rpc('publish_catalog_package', { p_package_id: packageId });
```

- [ ] **Step 5: Kör verifiering**

Run:

```powershell
npm run build
```

Expected: build succeeds.

Run:

```powershell
rg -n "Katalogprompts|Paket och arbetssätt|create_catalog_prompt|create_catalog_package|publish_catalog_package" admin.html src/admin.js
```

Expected: träffar på nya sektioner och RPC-anrop.

- [ ] **Step 6: Commit**

```powershell
git add admin.html src/admin.js style.css
git commit -m "feat(admin): add basic catalog prompt and package editor"
```

### Task 7: Lokal MCP-läsning mot den publicerade katalogen

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/mcp-server/server/mcp_server.py`
- Create: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/mcp-server/server/catalog.py`

**Interfaces:**
- Consumes:
  - `list_published_prompts`
  - `get_published_prompt`
  - `list_published_packages`
  - `get_published_package`
  - `list_published_package_prompts`
- Produces:
  - generiska MCP-tools för publicerad katalogläsning

- [ ] **Step 1: Lägg till en liten RPC-klientfil**

`catalog.py` ska följa mönstret från andra filer i `mcp-server/server/`, t.ex. `pro_templates.py`, och innehålla hjälpfunktioner:

```python
def list_published_prompts(context_key: str = "generell"): ...
def get_published_prompt(slug: str, context_key: str = "generell"): ...
def list_published_packages(context_key: str = "generell", package_type: str | None = None): ...
def get_published_package(slug: str, context_key: str = "generell"): ...
def list_published_package_prompts(package_slug: str, context_key: str = "generell"): ...
```

- [ ] **Step 2: Registrera verktygen i mcp_server.py**

Lägg till `@mcp.tool()`-funktioner som anropar hjälparna:

```python
@mcp.tool()
def list_packages(context_key: str = "generell", package_type: str | None = None):
    return _catalog.list_published_packages(context_key=context_key, package_type=package_type)
```

och motsvarande för prompt/paket-detaljer.

- [ ] **Step 3: Kör verifiering**

Run:

```powershell
python -m py_compile mcp-server/server/catalog.py mcp-server/server/mcp_server.py
```

Expected: ingen output.

Run:

```powershell
rg -n "list_packages|get_package|list_published_packages|get_published_prompt" mcp-server/server/mcp_server.py mcp-server/server/catalog.py
```

Expected: träffar på de nya generiska verktygen.

- [ ] **Step 4: Commit**

```powershell
git add mcp-server/server/catalog.py mcp-server/server/mcp_server.py
git commit -m "feat(mcp): read published catalog prompts and packages"
```

## Self-Review

- **Spec coverage:** Datamodell, fallback, draft/published, prompt- och paketflöden, chattskapande, admin-UI och MCP-läsning täcks av Task 1-7. Auth/auktorisering, sök/indexering och domänflytt lämnas avsiktligt utanför, i linje med specens scope.
- **Placeholder scan:** Planen använder inga `TBD`/`TODO`-platshållare i uppgiftsstegen; varje task har konkreta filer, funktioner, kommandon och commitsteg.
- **Type consistency:** Samma tabell- och funktionsnamn används konsekvent genom hela planen (`catalog_prompts`, `catalog_packages`, `publish_catalog_package`, `list_published_package_prompts`, osv.).
