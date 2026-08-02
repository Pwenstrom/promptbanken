# Unify catalog template source (frontend + open MCP + admin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `promptbanken.html`'s "Pro-mallar"-sektion, det öppna MCP-verktyget `recommend_packages`, och admin-MCP:s skrivväg alla läsa/skriva samma data (`catalog_prompts`/`catalog_prompt_variants` i Supabase), så att en admin-redigering syns överallt utan separat synk — och lägg till den enda verkliga fältluckan (`security_examples`, GDPR-anonymiseringsvarningar) som saknas i den nya katalogen jämfört med den gamla `pro_prompt_templates`-tabellen.

**Bakgrund (verifierat denna session):** `promptbanken.html`s `loadProTemplates()` anropar fortfarande Supabase-RPC:en `list_pro_templates()`, som läser direkt från `public.pro_prompt_templates` — en helt separat, osynkad tabell från `catalog_prompt_variants` som admin-MCP skriver till. Det öppna MCP-verktyget `recommend_packages` har samma problem internt (`_fetch_pro_templates("")`). De övriga 8 publika MCP-verktygen (`list_templates`, `search_templates`, `get_template`, `list_packages`, `get_package`, `list_package_prompts`, `health_check`, `get_client_routing_instructions`) läser **redan** korrekt från katalogen — de rörs inte av denna plan.

**Arkitektur:** Katalogens läs-RPC:er (`list_published_prompts`, `get_published_prompt`, `get_catalog_prompt_by_id`) och skriv-RPC:n (`upsert_catalog_prompt_variant`) utökas med en `security_examples text[]`-kolumn på `catalog_prompt_variants`. En engångsmigration backfyller värdet från `pro_prompt_templates` för de 66 legacy-raderna (matchade via den redan existerande `legacy-<area>-<sort_order>`-slug-konventionen). `promptbanken.html` och `recommend_packages` byter datakälla till katalogens redan existerande publika RPC:er — samma mönster som redan används av `list_templates`/`get_template`. `pro_prompt_templates`-tabellen och `list_pro_templates()`-RPC:n (Pro-nyckelgaterat MCP-verktyg, inte del av den öppna ytan) rörs INTE i denna plan — de lämnas orörda som teknisk skuld för en separat, framtida plan.

**Tech Stack:** PostgreSQL/Supabase (plpgsql/SQL RPC), Python/FastMCP (`mcp_promptbanken/mcp-server/server/`), vanilla JS i `promptbanken.html` (ingen bundling, inga `import`-satser).

## Global Constraints

- Repo 1: `promptbanken` — `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken`
- Repo 2: `mcp_promptbanken` — `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/mcp_promptbanken/mcp_promptbanken`
- **Inga tabeller eller RPC:er tas bort.** `pro_prompt_templates` och `list_pro_templates()` lämnas orörda och fortsätter fungera för det Pro-nyckelgaterade MCP-verktyget `list_pro_templates` (utanför scope, se `docs/superpowers/plans/`-notering i Task 6).
- **Ingen breaking change för externa MCP-klienter.** Alla 9 publika verktygsnamn och deras input/output-scheman är oförändrade — bara den interna datakällan för `recommend_packages` byts.
- Ny kolumn (`security_examples`) är nullable, additiv, kräver ingen befintlig kod-ändring för att inte krascha.
- `promptbanken.html` körs oprocessat (ingen bundling) — Supabase REST-anrop görs med råa `fetch()`, samma mönster som redan finns i filen för `loadMyPrompts()`.
- Deployordning är strikt: DB-migration (Task 1) måste vara körd i produktion innan Task 2–5 deployas, annars anropar de en kolumn/parameter som inte finns än.
- Verifiering: `rg`-sökningar, `python -m py_compile` för Python-filer, manuell körning i webbläsaren (`npm run web:dev` för promptbanken, `python -m py_compile` + live-test mot VPS för mcp_promptbanken).

---

### Task 1: Supabase-migration — `security_examples`-kolumn, backfill, uppdaterade RPC:er

**Files:**
- Create: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/migrations/20260802100000_catalog_security_examples.sql`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/supabase/tests/verify_catalog_core.sql`

**Interfaces:**
- Consumes: `public.catalog_prompt_variants`, `public.catalog_prompts`, `public.pro_prompt_templates` (oförändrade scheman förutom den nya kolumnen).
- Produces:
  - `public.catalog_prompt_variants.security_examples text[]` (ny kolumn, nullable)
  - `public.upsert_catalog_prompt_variant(...)` — ny sista parameter `p_security_examples text[] default null`
  - `public.list_published_prompts(text[])` — returtabellen får ett nytt sista fält `security_examples text[]`
  - `public.get_published_prompt(text, text[])` — samma tillägg
  - `public.get_catalog_prompt_by_id(uuid)` — samma tillägg (så admin ser fältet vid redigering)

- [x] **Step 1: Skriv migrationen — kolumn, backfill, write-RPC**

```sql
-- 20260802100000_catalog_security_examples.sql
-- Lägger till security_examples (GDPR-anonymiseringsvarningar) på
-- catalog_prompt_variants, backfyllar från pro_prompt_templates för de
-- legacy-migrerade raderna, och utökar upsert_catalog_prompt_variant så
-- admin-MCP kan skriva fältet. Se docs/superpowers/plans/
-- 2026-08-01-unify-catalog-template-source.md.

alter table public.catalog_prompt_variants
    add column if not exists security_examples text[];

-- Backfill: matcha via den redan existerande legacy-slug-konventionen
-- ('legacy-' || area || '-' || lpad(sort_order, 2, '0')) som seedmigrationen
-- 20260725120000_seed_catalog_from_existing_templates.sql byggde sluggarna
-- med. Sätter samma security_examples-array på alla context-varianter av
-- respektive prompt (fältet är inte context-specifikt i källtabellen).
update public.catalog_prompt_variants v
   set security_examples = t.security_examples
  from public.catalog_prompts cp
  join public.pro_prompt_templates t
    on cp.slug = 'legacy-' || t.area || '-' || lpad(t.sort_order::text, 2, '0')
 where v.prompt_id = cp.id
   and t.security_examples is not null
   and array_length(t.security_examples, 1) > 0;

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
    p_suggested_variables jsonb default null,
    p_risk_level text default null,
    p_area text default null,
    p_tags text[] default null,
    p_output_format text default null,
    p_parameter_schema jsonb default null,
    p_default_bindings jsonb default null,
    p_binding_overrides jsonb default null,
    p_security_examples text[] default null
)
returns catalog_prompt_variants
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_variant public.catalog_prompt_variants;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan redigera katalogen.';
    end if;

    if p_parameter_schema is not null and jsonb_typeof(p_parameter_schema) <> 'object' then
        raise exception 'parameter_schema måste vara ett jsonb-objekt.';
    end if;
    if p_default_bindings is not null and jsonb_typeof(p_default_bindings) <> 'object' then
        raise exception 'default_bindings måste vara ett jsonb-objekt.';
    end if;
    if p_binding_overrides is not null and jsonb_typeof(p_binding_overrides) <> 'array' then
        raise exception 'binding_overrides måste vara en jsonb-array.';
    end if;

    insert into public.catalog_prompt_variants (
        prompt_id, context_key, title, summary, prompt_text, example_input,
        audience_label, tone_hint, context_notes, suggested_variables,
        risk_level, area, tags, output_format,
        parameter_schema, default_bindings, binding_overrides, security_examples
    ) values (
        p_prompt_id, p_context_key, p_title, p_summary, p_prompt_text, p_example_input,
        p_audience_label, p_tone_hint, p_context_notes, coalesce(p_suggested_variables, '{}'::jsonb),
        p_risk_level, p_area, p_tags, p_output_format,
        p_parameter_schema, coalesce(p_default_bindings, '{}'::jsonb), coalesce(p_binding_overrides, '[]'::jsonb),
        p_security_examples
    )
    on conflict (prompt_id, context_key) do update
    set title = excluded.title,
        summary = excluded.summary,
        prompt_text = excluded.prompt_text,
        example_input = coalesce(p_example_input, catalog_prompt_variants.example_input),
        audience_label = coalesce(p_audience_label, catalog_prompt_variants.audience_label),
        tone_hint = coalesce(p_tone_hint, catalog_prompt_variants.tone_hint),
        context_notes = coalesce(p_context_notes, catalog_prompt_variants.context_notes),
        suggested_variables = coalesce(p_suggested_variables, catalog_prompt_variants.suggested_variables),
        risk_level = coalesce(p_risk_level, catalog_prompt_variants.risk_level),
        area = coalesce(p_area, catalog_prompt_variants.area),
        tags = coalesce(p_tags, catalog_prompt_variants.tags),
        output_format = coalesce(p_output_format, catalog_prompt_variants.output_format),
        parameter_schema = coalesce(p_parameter_schema, catalog_prompt_variants.parameter_schema),
        default_bindings = coalesce(p_default_bindings, catalog_prompt_variants.default_bindings),
        binding_overrides = coalesce(p_binding_overrides, catalog_prompt_variants.binding_overrides),
        security_examples = coalesce(p_security_examples, catalog_prompt_variants.security_examples)
    returning * into v_variant;

    update public.catalog_prompts
       set updated_by = auth.uid()
     where id = p_prompt_id;

    return v_variant;
end;
$$;

create or replace function public.upsert_catalog_prompt_variant(
    p_prompt_id uuid,
    p_context_key text,
    p_title text,
    p_summary text,
    p_prompt_text text,
    p_example_input text default null,
    p_audience_label text default null,
    p_tone_hint text default null,
    p_context_notes text default null,
    p_suggested_variables jsonb default null,
    p_risk_level text default null,
    p_area text default null,
    p_tags text[] default null,
    p_output_format text default null,
    p_parameter_schema jsonb default null,
    p_default_bindings jsonb default null,
    p_binding_overrides jsonb default null,
    p_security_examples text[] default null
)
returns catalog_prompt_variants
language sql
security definer
set search_path = 'public', 'app_private', 'pg_temp'
as $$
    select * from app_private.upsert_catalog_prompt_variant(
        p_prompt_id, p_context_key, p_title, p_summary, p_prompt_text,
        p_example_input, p_audience_label, p_tone_hint, p_context_notes, p_suggested_variables,
        p_risk_level, p_area, p_tags, p_output_format,
        p_parameter_schema, p_default_bindings, p_binding_overrides, p_security_examples
    );
$$;

revoke all on function public.upsert_catalog_prompt_variant(
    uuid, text, text, text, text, text, text, text, text, jsonb,
    text, text, text[], text, jsonb, jsonb, jsonb, text[]
) from public;
grant execute on function public.upsert_catalog_prompt_variant(
    uuid, text, text, text, text, text, text, text, text, jsonb,
    text, text, text[], text, jsonb, jsonb, jsonb, text[]
) to authenticated;
```

- [x] **Step 2: Uppdatera de tre läs-RPC:erna med `security_examples`**

```sql
create or replace function public.list_published_prompts(
    p_context_keys text[] default array['generell']
)
returns table (
    id uuid,
    slug text,
    icon_key text,
    image_key text,
    color_theme text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    risk_level text,
    area text,
    tags text[],
    output_format text,
    security_examples text[]
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cp.id,
        cp.slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        coalesce(matched.context_key, fallback.context_key) as context_key,
        coalesce(matched.title, fallback.title) as title,
        coalesce(matched.summary, fallback.summary) as summary,
        coalesce(matched.prompt_text, fallback.prompt_text) as prompt_text,
        coalesce(matched.example_input, fallback.example_input) as example_input,
        coalesce(matched.audience_label, fallback.audience_label) as audience_label,
        coalesce(matched.tone_hint, fallback.tone_hint) as tone_hint,
        coalesce(matched.parameter_schema, fallback.parameter_schema) as parameter_schema,
        coalesce(matched.default_bindings, fallback.default_bindings, '{}'::jsonb) as default_bindings,
        coalesce(matched.binding_overrides, fallback.binding_overrides, '[]'::jsonb) as binding_overrides,
        coalesce(matched.risk_level, fallback.risk_level) as risk_level,
        coalesce(matched.area, fallback.area) as area,
        coalesce(matched.tags, fallback.tags) as tags,
        coalesce(matched.output_format, fallback.output_format) as output_format,
        coalesce(matched.security_examples, fallback.security_examples) as security_examples
    from public.catalog_prompts cp
    left join lateral (
        select v.*
          from public.catalog_prompt_variants v
         where v.prompt_id = cp.id
           and v.context_key = any(p_context_keys)
         order by array_position(p_context_keys, v.context_key)
         limit 1
    ) matched on true
    left join public.catalog_prompt_variants fallback
      on fallback.prompt_id = cp.id
     and fallback.context_key = 'generell'
    where cp.status = 'published'
    order by cp.slug;
$$;

revoke all on function public.list_published_prompts(text[]) from public;
grant execute on function public.list_published_prompts(text[]) to anon, authenticated;

create or replace function public.get_published_prompt(
    p_slug text,
    p_context_keys text[] default array['generell']
)
returns table (
    id uuid,
    slug text,
    icon_key text,
    image_key text,
    color_theme text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    example_input text,
    audience_label text,
    tone_hint text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    risk_level text,
    area text,
    tags text[],
    output_format text,
    security_examples text[]
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        cp.id,
        cp.slug,
        cp.icon_key,
        cp.image_key,
        cp.color_theme,
        v.context_key,
        v.title,
        v.summary,
        v.prompt_text,
        v.example_input,
        v.audience_label,
        v.tone_hint,
        v.parameter_schema,
        coalesce(v.default_bindings, '{}'::jsonb) as default_bindings,
        coalesce(v.binding_overrides, '[]'::jsonb) as binding_overrides,
        v.risk_level,
        v.area,
        v.tags,
        v.output_format,
        v.security_examples
    from public.catalog_prompts cp
    join public.catalog_prompt_variants v on v.prompt_id = cp.id
    where cp.slug = p_slug
      and cp.status = 'published'
      and (v.context_key = any(p_context_keys) or v.context_key = 'generell')
    order by
        case when v.context_key = 'generell' then 1 else 0 end,
        coalesce(array_position(p_context_keys, v.context_key), 999);
$$;

revoke all on function public.get_published_prompt(text, text[]) from public;
grant execute on function public.get_published_prompt(text, text[]) to anon, authenticated;
```

- [x] **Step 3: Uppdatera `get_catalog_prompt_by_id` (admin-läsning) med `security_examples`**

```sql
create or replace function app_private.get_catalog_prompt_by_id(p_prompt_id uuid)
returns table (
    id uuid,
    slug text,
    status text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    risk_level text,
    area text,
    tags text[],
    output_format text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    security_examples text[]
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa en katalogprompt.';
    end if;

    return query
    select cp.id, cp.slug, cp.status, v.context_key, v.title, v.summary, v.prompt_text,
           v.risk_level, v.area, v.tags, v.output_format,
           v.parameter_schema, v.default_bindings, v.binding_overrides, v.security_examples
      from public.catalog_prompts cp
      join public.catalog_prompt_variants v on v.prompt_id = cp.id
     where cp.id = p_prompt_id
     order by case when v.context_key = 'generell' then 0 else 1 end;
end;
$$;

create or replace function public.get_catalog_prompt_by_id(p_prompt_id uuid)
returns table (
    id uuid,
    slug text,
    status text,
    context_key text,
    title text,
    summary text,
    prompt_text text,
    risk_level text,
    area text,
    tags text[],
    output_format text,
    parameter_schema jsonb,
    default_bindings jsonb,
    binding_overrides jsonb,
    security_examples text[]
)
language sql
security definer
set search_path = 'public', 'app_private', 'pg_temp'
as $$
    select * from app_private.get_catalog_prompt_by_id(p_prompt_id);
$$;
```

- [x] **Step 4: Utöka verifieringsfilen**

Lägg till i slutet av `verify_catalog_core.sql`:

```sql
-- security_examples: kolumn finns, och de tre publika läs-RPC:erna samt
-- write-RPC:n har fältet i sin signatur.
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'catalog_prompt_variants'
   and column_name = 'security_examples';

select p.proname, pg_get_function_result(p.oid) as return_type
  from pg_proc p
 where p.proname in ('list_published_prompts', 'get_published_prompt', 'get_catalog_prompt_by_id')
   and pg_get_function_result(p.oid) like '%security_examples%';
```

- [x] **Step 5: Kör verifieringskommandon**

Run:

```powershell
rg -n "security_examples" supabase/migrations/20260802100000_catalog_security_examples.sql
```

Expected: träffar i kolumn-tillägget, backfillen, write-RPC:n (båda varianterna) och de tre läs-RPC:erna — minst 8 träffar.

- [x] **Step 6: Deploya migrationen till produktion**

Kör mot länkad produktion (`supabase db push` eller motsvarande enligt projektets vanliga rutin — se `AGENTS.md`). **Detta steg måste vara klart innan Task 2–5 deployas.**

- [x] **Step 7: Verifiera backfillen i produktion**

```sql
select count(*) from public.catalog_prompt_variants where security_examples is not null;
```

Expected: > 0 (minst de 66 legacy-varianternas `generell`-rader, ofta fler eftersom samma array skrivs på alla context-varianter av samma prompt).

- [x] **Step 8: Commit**

```powershell
git add supabase/migrations/20260802100000_catalog_security_examples.sql supabase/tests/verify_catalog_core.sql
git commit -m "feat(db): add security_examples to catalog_prompt_variants, backfill from legacy templates"
```

---

### Task 2: Admin-MCP — `security_examples`-parameter på skrivverktyget

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/mcp_promptbanken/mcp_promptbanken/mcp-server/server/admin_catalog.py`
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/mcp_promptbanken/mcp_promptbanken/mcp-server/server/mcp_server.py`

**Interfaces:**
- Consumes: `public.upsert_catalog_prompt_variant(...)` från Task 1 (ny `p_security_examples`-parameter sist).
- Produces: `admin_catalog.upsert_prompt_variant(..., security_examples: list[str] | None = None)`, MCP-verktyget `admin_upsert_prompt_variant` tar en ny valfri `security_examples: list[string]`-parameter.

- [x] **Step 1: Utöka `admin_catalog.upsert_prompt_variant`**

I `admin_catalog.py`, ersätt hela `upsert_prompt_variant`-funktionen (rad 103-135):

```python
def upsert_prompt_variant(
    prompt_id: str,
    context_key: str,
    title: str,
    summary: str,
    prompt_text: str,
    risk_level: str | None = None,
    area: str | None = None,
    tags: list[str] | None = None,
    output_format: str | None = None,
    parameter_schema: dict[str, Any] | None = None,
    default_bindings: dict[str, Any] | None = None,
    binding_overrides: list[Any] | None = None,
    security_examples: list[str] | None = None,
) -> dict[str, Any]:
    return _write(
        "admin_upsert_prompt_variant",
        "upsert_catalog_prompt_variant",
        {
            "p_prompt_id": prompt_id,
            "p_context_key": context_key,
            "p_title": title,
            "p_summary": summary,
            "p_prompt_text": prompt_text,
            "p_risk_level": risk_level,
            "p_area": area,
            "p_tags": tags,
            "p_output_format": output_format,
            "p_parameter_schema": parameter_schema,
            "p_default_bindings": default_bindings,
            "p_binding_overrides": binding_overrides,
            "p_security_examples": security_examples,
        },
        target_id=prompt_id,
    )
```

- [x] **Step 2: Utöka verktygets inputSchema i `mcp_server.py`**

I `mcp_server.py`, i `admin_upsert_prompt_variant`-verktygets `inputSchema.properties` (rad ~2836-2849), lägg till efter `"binding_overrides"`:

```python
                    "binding_overrides": {"type": "array"},
                    "security_examples": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "GDPR-anonymiseringsexempel/varningar specifika för denna prompt.",
                    },
```

- [x] **Step 3: Skicka parametern vidare i dispatchen**

I `mcp_server.py`, i `admin_upsert_prompt_variant`-dispatchen (rad ~3048-3061), lägg till efter `binding_overrides=arguments.get("binding_overrides"),`:

```python
                binding_overrides=arguments.get("binding_overrides"),
                security_examples=arguments.get("security_examples"),
```

- [x] **Step 4: Verifiera att filerna kompilerar**

Run:

```powershell
python -m py_compile mcp-server/server/admin_catalog.py mcp-server/server/mcp_server.py
```

Expected: ingen output.

- [x] **Step 5: Verifiera parameterkedjan**

Run:

```powershell
rg -n "security_examples" mcp-server/server/admin_catalog.py mcp-server/server/mcp_server.py
```

Expected: minst 4 träffar (funktionssignatur + payload-dict i admin_catalog.py, inputSchema + dispatch i mcp_server.py).

- [x] **Step 6: Commit**

```powershell
git add mcp-server/server/admin_catalog.py mcp-server/server/mcp_server.py
git commit -m "feat(admin): accept security_examples on admin_upsert_prompt_variant"
```

---

### Task 3: Öppet MCP — `recommend_packages` byter bort från legacy-tabellen

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/mcp_promptbanken/mcp_promptbanken/mcp-server/server/mcp_server.py`

**Interfaces:**
- Consumes: `_catalog.list_published_prompts(context_keys=[...])` (redan existerande, används av `_list_templates_payload`), `_catalog_area_index(context_keys)` (redan existerande helper, rad 307-337), `_catalog_prompt_to_template_summary(prompt, area_index)` (redan existerande, rad 356-370).
- Produces: `_recommend_packages_payload(role: str) -> dict[str, Any]` (oförändrad signatur — bara den interna datakällan byts). `package_recommendations.recommend(role, templates)` (i `mcp_promptbanken`, filen `package_recommendations.py`) är oförändrad — den läser bara `t["area"]`/`t["area_label"]` ur listan, vilket `_catalog_prompt_to_template_summary` redan producerar.

- [x] **Step 1: Byt datakälla i `_recommend_packages_payload`**

I `mcp_server.py`, ersätt hela funktionen (rad 1049-1051):

```python
def _recommend_packages_payload(role: str) -> dict[str, Any]:
    context_keys = _normalize_context_keys(None)
    prompts = _catalog.list_published_prompts(context_keys=context_keys)
    area_index = _catalog_area_index(context_keys)
    templates = [_catalog_prompt_to_template_summary(p, area_index=area_index) for p in prompts]
    return _recommend_packages(role, templates)
```

- [x] **Step 2: Verifiera att `_fetch_pro_templates` inte längre används här**

Run:

```powershell
rg -n "_fetch_pro_templates" mcp-server/server/mcp_server.py
```

Expected: exakt en träff kvar — raden `templates = _fetch_pro_templates(mcp_key)` inuti `_pro_templates_payload` (det Pro-nyckelgaterade `list_pro_templates`-verktyget, medvetet utanför scope för denna plan, se Global Constraints).

- [x] **Step 3: Verifiera att filen kompilerar**

Run:

```powershell
python -m py_compile mcp-server/server/mcp_server.py
```

Expected: ingen output.

- [x] **Step 4: Manuellt smoke-test lokalt**

Run (med `SUPABASE_URL`/`SUPABASE_ANON_KEY` satta i miljön, t.ex. via `.env` som redan finns i repot):

```powershell
python -c "from mcp_server.server.mcp_server import _recommend_packages_payload; import json; print(json.dumps(_recommend_packages_payload('chef'), ensure_ascii=False, indent=2))"
```

Expected: `role_recognized: true`, en lista `packages` med `area`/`area_label`/`template_count` — samma form som innan bytet, bara datan kommer nu från katalogen istället för `pro_prompt_templates`.

- [x] **Step 5: Commit**

```powershell
git add mcp-server/server/mcp_server.py
git commit -m "fix(mcp): read recommend_packages areas from the catalog instead of legacy pro_prompt_templates"
```

---

### Task 4: Öppet MCP — surfacea `security_examples` på `get_template`/`list_templates`

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/mcp_promptbanken/mcp_promptbanken/mcp-server/server/mcp_server.py`

**Interfaces:**
- Consumes: `security_examples`-fältet från `_catalog.list_published_prompts`/`_catalog.get_published_prompt` (Task 1 — flödar automatiskt genom `catalog.py` utan kodändring där, eftersom den bara vidarebefordrar rå RPC-JSON).
- Produces: `_catalog_prompt_to_template(...)` (rad 373-392) inkluderar nu `security_examples` i sitt returnerade dict, vilket gör att `get_template`/`list_templates`/`search_templates` visar fältet för AI-klienter.

- [x] **Step 1: Lägg till fältet i `_catalog_prompt_to_template`**

I `mcp_server.py`, i funktionen (rad 373-392), lägg till efter `"binding_overrides": prompt.get("binding_overrides"),`:

```python
        "binding_overrides": prompt.get("binding_overrides"),
        "security_examples": prompt.get("security_examples") or [],
```

- [x] **Step 2: Verifiera**

Run:

```powershell
rg -n "security_examples" mcp-server/server/mcp_server.py
```

Expected: minst 3 träffar nu (Task 2:s inputSchema/dispatch + denna nya raden).

```powershell
python -m py_compile mcp-server/server/mcp_server.py
```

Expected: ingen output.

- [x] **Step 3: Commit**

```powershell
git add mcp-server/server/mcp_server.py
git commit -m "feat(mcp): expose security_examples on get_template/list_templates payloads"
```

---

### Task 5: Frontend — `promptbanken.html` läser Pro-mallar från katalogen

**Files:**
- Modify: `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/promptbanken/promptbanken.html`

**Interfaces:**
- Consumes: `public.list_published_prompts(p_context_keys)` och `public.list_published_packages(p_context_keys)` (Task 1, redan publikt grantade till `anon` sen tidigare — samma RPC:er som `script.js`s öppna katalogsektion redan använder via `callCatalogRpc`).
- Produces: `loadProTemplates()` behåller sin befintliga kontraktspunkt `window.registerProTemplates?.(mappedItems)` oförändrad — `registerProTemplates` i `script.js` (rad 1903-) kräver ingen ändring.

**Bakgrund:** `promptbanken.html` har ingen egen `callCatalogRpc`-helper (den finns bara i `script.js`). Denna task lägger en liten lokal fetch-helper i `promptbanken.html`, samma mönster som `script.js`s `callCatalogRpc` men fristående, eftersom `promptbanken.html` inte laddar `script.js` som modul.

- [x] **Step 1: Lägg till en lokal katalog-RPC-helper**

I `promptbanken.html`, direkt före `async function loadProTemplates()` (rad 696), lägg till:

```javascript
      async function callOpenCatalogRpc(functionName, payload) {
        const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${functionName}`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': supabaseAnonKey,
            'Authorization': `Bearer ${supabaseAnonKey}`
          },
          body: JSON.stringify(payload)
        });
        if (!response.ok) {
          throw new Error(`Kataloganrop ${functionName} misslyckades: ${response.status}`);
        }
        return response.json();
      }
```

Not: `supabaseUrl`/`supabaseAnonKey` — kontrollera exakt variabelnamn som redan används högre upp i samma `<script>`-block för `supabase.rpc(...)`-anropen (t.ex. `loadMyPrompts`) och återanvänd samma namn. Om filen bara har en färdig `supabase`-klient (via `createClient(...)`) och inga separata `supabaseUrl`/`supabaseAnonKey`-variabler, läs istället `supabase.supabaseUrl`/`supabase.supabaseKey` (den JS-klientens interna properties, redan tillgängliga eftersom `supabase`-objektet skapas i samma fil).

- [x] **Step 2: Ersätt `loadProTemplates` med katalogbaserad version**

Ersätt hela funktionen (rad 696-713):

```javascript
      async function loadProTemplates() {
        let prompts;
        let packages;
        try {
          [prompts, packages] = await Promise.all([
            callOpenCatalogRpc('list_published_prompts', { p_context_keys: ['generell'] }),
            callOpenCatalogRpc('list_published_packages', { p_context_keys: ['generell'] })
          ]);
        } catch (error) {
          console.error('Kunde inte hämta promptbibliotekets fördjupningsmallar', error);
          return;
        }

        const areaLabels = new Map(packages.map((pkg) => [pkg.slug, pkg.title]));

        const mappedItems = prompts.map((prompt) => ({
          id: prompt.id,
          title: prompt.title,
          description: prompt.summary || '',
          content: prompt.prompt_text || '',
          category: areaLabels.get(prompt.area) || prompt.area || '',
          risk: riskLabels[prompt.risk_level] || riskLabels.low
        }));

        window.registerProTemplates?.(mappedItems);
      }
```

Not: `security_examples` mappas medvetet **inte** in i `mappedItems` här — `registerProTemplates`/`promptUiMeta` i `script.js` har idag inget fält för säkerhetsexempel på denna kortyp (samma begränsning som redan gäller `registerOwnPrompts`). Fältet finns nu tillgängligt i RPC-svaret för en framtida UI-utökning, men att lägga till visning av det är utanför denna plans scope (bara datakälleunifiering + att fältet inte tappas i databasen).

- [x] **Step 3: Verifiera**

Run:

```powershell
rg -n "list_pro_templates" promptbanken.html
```

Expected: inga träffar kvar (funktionen anropar inte längre den gamla RPC:n).

```powershell
rg -n "callOpenCatalogRpc|loadProTemplates" promptbanken.html
```

Expected: träffar för helper-definitionen och den nya funktionskroppen.

- [x] **Step 4: Manuell körning i webbläsaren**

Run:

```powershell
npm run web:dev
```

Öppna `promptbanken.html` i webbläsaren, öppna dev-konsolen, kontrollera:
- Inga fel loggade för `loadProTemplates`
- Nätverksfliken visar `POST .../rpc/list_published_prompts` och `POST .../rpc/list_published_packages` (inte längre `list_pro_templates`)
- Leta upp kortet för "Skapa egen AI-mall" (den ursprungliga bug-rapportens prompt) och bekräfta att det visar samma risknivå som admin skrev (**Medelrisk**, inte längre Låg risk)

- [x] **Step 5: Commit**

```powershell
git add promptbanken.html
git commit -m "fix(web): read Pro template list from the catalog instead of legacy pro_prompt_templates"
```

---

### Task 6: Deploy och slutverifiering

**Files:** Inga nya filändringar — deploy- och verifieringssteg.

- [x] **Step 1: Bekräfta deployordning**

Task 1 (databasmigration) måste redan vara körd i produktion (gjordes i Task 1 Step 6) innan detta steg. Kontrollera:

```sql
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'catalog_prompt_variants'
   and column_name = 'security_examples';
```

Expected: en rad. Om tom — stanna, kör Task 1 Step 6 färdigt först.

- [x] **Step 2: Deploya mcp_promptbanken (Task 2, 3, 4) till VPS**

Använd `vps-deploy`-skillen: `git pull` + `docker-compose up -d --build` för `promptbanken-mcp`-tjänsten. Följ dess disk-space-kontroll först (VPS-disken har varit full förut denna session).

- [x] **Step 3: Verifiera mcp_promptbanken live**

```powershell
curl -s -o /dev/null -w "healthz: %{http_code}\n" localhost:8000/healthz
```

Expected: 200. Kör sedan ett riktigt `recommend_packages`-anrop mot `/mcp` (via en MCP-klient eller `curl` med JSON-RPC-body) med `role: "chef"` och bekräfta att svaret fortfarande ger `role_recognized: true` med rimliga `area`/`area_label`-par.

- [x] **Step 4: Deploya promptbanken (Task 5) via GitHub Pages**

Push till `main` — `deploy.yml`-workflowet bygger och deployar automatiskt (bekräftat tidigare denna session, `npm run build` + `actions/deploy-pages`).

- [x] **Step 5: Verifiera live på `app.promptbanken.se`**

Öppna sidan, hitta "Skapa egen AI-mall"-kortet, bekräfta risknivån visar **Medelrisk**. Öppna dev-konsolens nätverksflik, bekräfta att `list_pro_templates`-anropet är borta och ersatt av `list_published_prompts`/`list_published_packages`.

- [x] **Step 6: Uppdatera octopus-statusen**

Logga i `C:/Users/petwen/OneDrive - Höglandsförbundet/Projekt/octopus/STATUS.md` under både `promptbanken` och `mcp_promptbanken` att katalog-källorna är unifierade, med commit-hashar från Task 1-5.

**Känd kvarstående teknisk skuld (medvetet utanför scope):** `pro_prompt_templates`-tabellen och det Pro-nyckelgaterade MCP-verktyget `list_pro_templates` (skiljt från de öppna verktygen) läser fortfarande legacy-tabellen. En framtida plan bör antingen migrera det verktyget till katalogen också, eller formellt deprecata det om Pro-mall-konceptet inte längre är aktuellt (jfr VISION.md: Promptbanken som öppet publikt bibliotek).

## Self-Review

- **Spec coverage:** "Samma källa i frontend, mcp öppen och admin" — Task 3 (recommend_packages) och Task 5 (frontend) täcker de två återstående osynkade läsvägarna; de andra 8 öppna verktygen var redan katalogbaserade (verifierat i kod, ingen task behövs för dem). Admin-skrivvägen (Task 2) och läs-RPC:erna (Task 1) hålls i synk genom samma `security_examples`-tillägg på båda sidor. security_examples-beslutet (lägg till kolumn, rekommenderat alternativ) är genomfört fullt ut: schema, backfill, write-RPC, tre läs-RPC:er, admin-tool-parameter, exponering i get_template/list_templates.
- **Placeholder scan:** Inga TBD/TODO. Task 5 Step 1 har en explicit "kontrollera exakt variabelnamn"-instruktion snarare än en gissning, eftersom exakt variabelnamn för Supabase-URL/nyckel i `promptbanken.html` inte lästes ordagrant ur filen under research — flaggat som en verifieringsinstruktion, inte en obestämd platshållare, med ett konkret fallback-alternativ angivet.
- **Type consistency:** `security_examples` som `text[]`/`list[str] | None`/`string[]` konsekvent genom SQL (Task 1), Python (Task 2, 4) och JS (Task 5, medvetet ej mappad in i UI men datan tappas inte). Funktionssignaturer för `upsert_catalog_prompt_variant` matchar exakt mellan `app_private.`- och `public.`-varianterna i Task 1.
