# Valvet egna promptpaket (create_custom_package) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Valvet user bundle several of their own saved prompts into a named, ordered, privately-owned package via three new MCP tools (`create_custom_package`, `get_my_package`, `update_my_package_items`), reusing the existing `content_items`/MCP-key-based Valvet architecture.

**Architecture:** A package is a `content_items` row (`module='valvet'`, new `type='package'`). Membership + order live in a new join table `valvet_package_items(package_id, member_id, sort_order)` with `on delete cascade` on both FKs. Three new key-hash-authenticated Supabase RPCs (promptbanken repo) follow the exact `*_for_key` pattern already used by `save_my_item_for_key`/`get_my_item_for_key`/`list_my_items_for_key`. Three new MCP tools (mcp_promptbanken repo) follow the exact wiring pattern already used for `list_my_items`/`save_my_item` across `vault.py`, `mcp_server.py` (HTTP `_tool_definitions`/dispatch + stdio `@mcp.tool()`), and `hosted_guard.py`.

**Tech Stack:** PostgreSQL/PL-pgSQL (Supabase, `promptbanken` repo, `supabase/migrations/`), Python 3.12 (`mcp_promptbanken` repo, `mcp-server/server/`), manual SQL verify scripts + curl for testing (matches existing project convention — no pytest harness exists for this RPC/MCP-dispatch layer).

## Global Constraints

- Ownership check for package RPCs uses `workspace_id = v_ws.id` **only** — do **not** add the `owner_user_id = v_ws.owner_user_id` clause that `list_my_items_for_key`/`get_my_item_for_key`/etc. have. This is the one deliberate deviation from the copied template (see design spec, "Scope": workspace_id-scoped not owner_user_id-scoped, so a future team-sharing migration doesn't require rewriting these tables).
- All new SQL functions: `security definer`, `set search_path = ''`, schema-qualify every reference (`public.content_items`, `app_private.*`) — matches every existing Valvet RPC in this repo, required by the search-path hardening pattern from `20260717090000_valvet_write_rpcs_search_path_hardening.sql`.
- Every new `app_private.*_for_key` function gets a thin `public.*_for_key` SQL wrapper, `revoke all ... from public`, then `grant execute ... to anon, authenticated` — exact pattern from every existing `_for_key` RPC in this repo. Do not grant directly on the `app_private` function.
- Python: every new `vault.py` function follows the existing signature style — `mcp_key` first positional arg, `if not mcp_key or not is_configured(): return <empty/raise>` guard, `_call_rpc(name, payload)` for the actual call. Write RPCs (create/update) let exceptions propagate (never silently swallow a write failure) — read RPCs (get) catch and log, returning `None`/`[]`.
- Reference spec: `docs/superpowers/specs/2026-08-05-valvet-custom-packages-design.md` (promptbanken repo). Every task below implements one piece of it — do not deviate from validation rules or error messages defined there without updating the spec first.

---

## File Structure

**promptbanken repo:**
- Create: `supabase/migrations/2026080X_valvet_custom_packages.sql` — enum value, table, all three RPCs + wrappers + grants (one migration file, matches how `20260718100000_copy_catalog_item_to_valvet.sql` bundled a whole feature's schema+RPCs together)
- Create: `supabase/tests/verify_valvet_custom_packages.sql` — manual verify script, same style as `supabase/tests/verify_copy_published_prompt_to_valvet.sql`

**mcp_promptbanken repo (`mcp_promptbanken/mcp-server/server/`):**
- Modify: `vault.py` — add `create_package`, `get_package`, `update_package_items` functions
- Modify: `mcp_server.py` — three places: (1) HTTP `_tool_definitions()` list, (2) `_handle_mcp_message` `tools/call` dispatch, (3) stdio `@mcp.tool()` functions (all gated `if SERVER_MODE != "hosted":`, matching every existing Valvet tool)
- Modify: `hosted_guard.py` — add three tool names to `allowed_methods` + entries to `allowed_tool_args` with validation

---

### Task 1: Supabase schema + `create_custom_package`

**Files:**
- Create: `supabase/migrations/20260806100000_valvet_custom_packages.sql`
- Test: `supabase/tests/verify_valvet_custom_packages.sql` (start this file in this task, add to it in Tasks 2–3)

**Interfaces:**
- Produces: `public.create_custom_package_for_key(p_key_hash text, p_title text, p_description text, p_category text, p_prompt_ids uuid[]) returns public.content_items` — the package row (same shape `save_my_item_for_key` returns).
- Produces: table `public.valvet_package_items(package_id uuid, member_id uuid, sort_order integer)`, primary key `(package_id, member_id)`, both FKs `on delete cascade`.
- Produces: `content_item_type` enum gains `'package'`.

- [ ] **Step 1: Write the migration — enum + table**

```sql
-- 20260806100000_valvet_custom_packages.sql
-- Lets a Valvet user bundle several of their own saved prompts into a
-- named, ordered private package. See design spec:
-- docs/superpowers/specs/2026-08-05-valvet-custom-packages-design.md
--
-- Ownership check on all three RPCs below uses workspace_id only (NOT
-- owner_user_id = v_ws.owner_user_id, unlike list_my_items_for_key etc.)
-- -- deliberate, see spec "Scope": future team-sharing shouldn't require
-- rewriting this table. No behavior change today: personal workspaces
-- have exactly one owner.

alter type public.content_item_type add value if not exists 'package';

create table if not exists public.valvet_package_items (
    package_id uuid not null references public.content_items(id) on delete cascade,
    member_id  uuid not null references public.content_items(id) on delete cascade,
    sort_order integer not null,
    primary key (package_id, member_id)
);

create index if not exists valvet_package_items_package_id_idx
    on public.valvet_package_items (package_id, sort_order);

revoke all on table public.valvet_package_items from public;
grant select on table public.valvet_package_items to anon, authenticated;
```

- [ ] **Step 2: Write `create_custom_package_for_key`**

Append to the same migration file:

```sql
create or replace function app_private.create_custom_package_for_key(
    p_key_hash    text,
    p_title       text,
    p_description text,
    p_category    text,
    p_prompt_ids  uuid[]
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key         public.api_keys%rowtype;
    v_ws          public.workspaces%rowtype;
    v_recent_attempts integer;
    v_bad_id      uuid;
    v_slug        text;
    v_row         public.content_items%rowtype;
    v_idx         integer;
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

    if trim(coalesce(p_title, '')) = '' or length(p_title) > 200 then
        raise exception 'Titel måste vara 1–200 tecken.';
    end if;

    if p_prompt_ids is null or array_length(p_prompt_ids, 1) is null or array_length(p_prompt_ids, 1) = 0 then
        raise exception 'Ett paket behöver minst en prompt.';
    end if;

    -- Every id must exist, belong to this workspace, module='valvet', not archived.
    select id into v_bad_id
      from unnest(p_prompt_ids) as id
     where not exists (
        select 1 from public.content_items ci
         where ci.id = id
           and ci.workspace_id = v_ws.id
           and ci.module = 'valvet'
           and ci.status <> 'archived'
     )
     limit 1;
    if v_bad_id is not null then
        raise exception 'Prompten % finns inte, tillhör inte din arbetsyta, eller är arkiverad.', v_bad_id;
    end if;

    v_slug := app_private.slugify_candidate(p_title, 'paket');
    while exists (select 1 from public.content_items where workspace_id = v_ws.id and slug = v_slug) loop
        v_slug := app_private.slugify_candidate(p_title, 'paket') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    end loop;

    perform set_config('request.jwt.claim.sub', v_ws.owner_user_id::text, true);

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, module, title, slug,
        content, category, status, visibility
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id, 'package'::public.content_item_type, 'valvet',
        p_title, v_slug, coalesce(p_description, ''), p_category, 'draft', 'private'
    )
    returning * into v_row;

    v_idx := 0;
    insert into public.valvet_package_items (package_id, member_id, sort_order)
    select v_row.id, pid, row_number() over () - 1
      from unnest(p_prompt_ids) as pid;

    insert into app_private.mcp_write_attempts (key_hash, workspace_id, tool, outcome)
    values (p_key_hash, v_ws.id, 'create_custom_package', 'success');

    return v_row;
end;
$$;

revoke all on function app_private.create_custom_package_for_key(text, text, text, text, uuid[]) from public;

create or replace function public.create_custom_package_for_key(
    p_key_hash text, p_title text, p_description text, p_category text, p_prompt_ids uuid[]
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.create_custom_package_for_key(p_key_hash, p_title, p_description, p_category, p_prompt_ids);
$$;

revoke all on function public.create_custom_package_for_key(text, text, text, text, uuid[]) from public;
grant execute on function public.create_custom_package_for_key(text, text, text, text, uuid[]) to anon, authenticated;
```

- [ ] **Step 3: Start the verify script**

```sql
-- supabase/tests/verify_valvet_custom_packages.sql
-- Manuellt körbart end-to-end-flöde mot staging/länkad produktion.
-- Alla tre RPC:erna är nyckelhash-baserade (samma modell som
-- save_my_item_for_key) -- kör via curl mot /mcp/key eller REST direkt
-- med en riktig testnyckel, inte som postgres-superuser.
--
-- Fixturer: en Pro-nyckel med minst 3 egna icke-arkiverade Valvet-prompts
-- (module='valvet') -- byt in deras riktiga id:n nedan.

-- 1. Skapa ett paket med 3 prompts.
select * from public.create_custom_package_for_key(
    '<key_hash>', 'Mitt testpaket', 'En kort beskrivning', 'arbetsbank',
    array['<prompt-id-1>', '<prompt-id-2>', '<prompt-id-3>']::uuid[]
);
-- Förväntat: 1 rad, type='package', module='valvet', status='draft',
-- visibility='private', content='En kort beskrivning'.

-- 2. Verifiera medlemsordning direkt i tabellen.
select member_id, sort_order from public.valvet_package_items
 where package_id = '<id-fran-steg-1>' order by sort_order;
-- Förväntat: 3 rader, sort_order 0/1/2 i samma ordning som arrayen i steg 1.

-- 3. Tomt prompt_ids[] -> avvisas.
select * from public.create_custom_package_for_key(
    '<key_hash>', 'Tomt paket', '', 'arbetsbank', array[]::uuid[]
);
-- Förväntat: ERROR 'Ett paket behöver minst en prompt.'

-- 4. Ett id från en annan workspace (eller ett påhittat uuid) -> avvisas.
select * from public.create_custom_package_for_key(
    '<key_hash>', 'Fel workspace', '', 'arbetsbank', array[gen_random_uuid()]::uuid[]
);
-- Förväntat: ERROR 'Prompten ... finns inte, tillhör inte din arbetsyta, eller är arkiverad.'
```

- [ ] **Step 4: Deploy and run the verify script's steps 1–4 manually**

Deploy per repo convention (`supabase db push` if the CLI's migration history is in sync -- see `docs superpowers` history for the 2026-08-05 collision incident and its fix; the CLI should now work normally). Run steps 1–4 above against staging/production via Studio SQL editor or `psql`, substituting real ids from an existing Pro test workspace. Confirm actual output matches every "Förväntat" comment before continuing.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260806100000_valvet_custom_packages.sql supabase/tests/verify_valvet_custom_packages.sql
git commit -m "feat(db): add valvet_package_items table and create_custom_package_for_key RPC"
```

---

### Task 2: `get_my_package_for_key`

**Files:**
- Modify: `supabase/migrations/20260806100000_valvet_custom_packages.sql` (append)
- Modify: `supabase/tests/verify_valvet_custom_packages.sql` (append)

**Interfaces:**
- Consumes: `public.valvet_package_items` (Task 1), `public.content_items`.
- Produces: `public.get_my_package_for_key(p_key_hash text, p_id uuid) returns table(package_id uuid, package_title text, package_description text, package_category text, package_status text, package_updated_at timestamptz, member_id uuid, member_type text, member_title text, member_content text, member_category text, member_status text, member_sort_order integer)` — one row per non-archived member, package fields repeated (same flat-denormalized shape as the existing `list_package_prompts` catalog RPC). Empty result (no rows) means "not found, not yours, or not a package" -- same convention as `get_my_item_for_key`.

- [ ] **Step 1: Write `get_my_package_for_key`**

Append to `supabase/migrations/20260806100000_valvet_custom_packages.sql`:

```sql
create or replace function app_private.get_my_package_for_key(
    p_key_hash text,
    p_id       uuid
)
returns table(
    package_id uuid, package_title text, package_description text,
    package_category text, package_status text, package_updated_at timestamptz,
    member_id uuid, member_type text, member_title text, member_content text,
    member_category text, member_status text, member_sort_order integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
    v_pkg public.content_items%rowtype;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then return; end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then return; end if;

    select * into v_pkg from public.content_items
     where id = p_id and workspace_id = v_ws.id and module = 'valvet' and type = 'package';
    if not found then return; end if;

    return query
    select v_pkg.id, v_pkg.title, v_pkg.content, v_pkg.category, v_pkg.status::text, v_pkg.updated_at,
           ci.id, ci.type::text, ci.title, ci.content, ci.category, ci.status::text, vpi.sort_order
      from public.valvet_package_items vpi
      join public.content_items ci on ci.id = vpi.member_id
     where vpi.package_id = v_pkg.id
       and ci.status <> 'archived'
     order by vpi.sort_order;
end;
$$;

revoke all on function app_private.get_my_package_for_key(text, uuid) from public;

create or replace function public.get_my_package_for_key(p_key_hash text, p_id uuid)
returns table(
    package_id uuid, package_title text, package_description text,
    package_category text, package_status text, package_updated_at timestamptz,
    member_id uuid, member_type text, member_title text, member_content text,
    member_category text, member_status text, member_sort_order integer
)
language sql
security definer
set search_path = ''
as $$
    select * from app_private.get_my_package_for_key(p_key_hash, p_id);
$$;

revoke all on function public.get_my_package_for_key(text, uuid) from public;
grant execute on function public.get_my_package_for_key(text, uuid) to anon, authenticated;
```

- [ ] **Step 2: Append to the verify script**

```sql
-- 5. Hämta paketet från steg 1, verifiera ordning och att alla 3 medlemmar finns.
select * from public.get_my_package_for_key('<key_hash>', '<id-fran-steg-1>');
-- Förväntat: 3 rader, samma package_id/package_title på alla, member_sort_order 0/1/2.

-- 6. Arkivera en medlemsprompt (via befintlig archive_my_item_for_key), hämta paketet igen.
select * from public.archive_my_item_for_key('<key_hash>', '<prompt-id-2>', true, false);
select * from public.get_my_package_for_key('<key_hash>', '<id-fran-steg-1>');
-- Förväntat: nu 2 rader (prompt-id-2 saknas), kopplingsraden i
-- valvet_package_items ligger dock kvar orörd (kolla separat: select * from
-- public.valvet_package_items where package_id = '<id-fran-steg-1>' -- ska
-- fortfarande visa 3 rader).

-- 7. Återställ samma prompt, hämta paketet en tredje gång.
select * from public.archive_my_item_for_key('<key_hash>', '<prompt-id-2>', true, true);
select * from public.get_my_package_for_key('<key_hash>', '<id-fran-steg-1>');
-- Förväntat: 3 rader igen, ingen ny update_my_package_items-anrop behövdes.

-- 8. Fel id (finns inte / annan workspace) -> tomt resultat.
select * from public.get_my_package_for_key('<key_hash>', gen_random_uuid());
-- Förväntat: 0 rader, inget fel.
```

- [ ] **Step 3: Deploy and run steps 5–8**

Same deploy method as Task 1. Confirm all four steps match expectations.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260806100000_valvet_custom_packages.sql supabase/tests/verify_valvet_custom_packages.sql
git commit -m "feat(db): add get_my_package_for_key RPC"
```

---

### Task 3: `update_my_package_items_for_key`

**Files:**
- Modify: `supabase/migrations/20260806100000_valvet_custom_packages.sql` (append)
- Modify: `supabase/tests/verify_valvet_custom_packages.sql` (append)

**Interfaces:**
- Consumes: same tables as Tasks 1–2.
- Produces: `public.update_my_package_items_for_key(p_key_hash text, p_id uuid, p_prompt_ids uuid[]) returns public.content_items` — replaces the ENTIRE membership list atomically, returns the package's own row (title/description/category unchanged -- use the existing `update_my_item_for_key` for those, per spec).

- [ ] **Step 1: Write `update_my_package_items_for_key`**

Append to the same migration file:

```sql
create or replace function app_private.update_my_package_items_for_key(
    p_key_hash   text,
    p_id         uuid,
    p_prompt_ids uuid[]
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key    public.api_keys%rowtype;
    v_ws     public.workspaces%rowtype;
    v_pkg    public.content_items%rowtype;
    v_bad_id uuid;
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

    select count(*) into v_recent_attempts
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash and created_at >= now() - interval '60 seconds';
    if v_recent_attempts >= 20 then
        raise exception 'För många försök, vänta en minut och försök igen.';
    end if;

    select * into v_pkg from public.content_items
     where id = p_id and workspace_id = v_ws.id and module = 'valvet' and type = 'package';
    if not found then
        raise exception 'Paketet hittades inte.';
    end if;

    if p_prompt_ids is null or array_length(p_prompt_ids, 1) is null or array_length(p_prompt_ids, 1) = 0 then
        raise exception 'Ett paket behöver minst en prompt.';
    end if;

    select id into v_bad_id
      from unnest(p_prompt_ids) as id
     where not exists (
        select 1 from public.content_items ci
         where ci.id = id
           and ci.workspace_id = v_ws.id
           and ci.module = 'valvet'
           and ci.status <> 'archived'
     )
     limit 1;
    if v_bad_id is not null then
        raise exception 'Prompten % finns inte, tillhör inte din arbetsyta, eller är arkiverad.', v_bad_id;
    end if;

    delete from public.valvet_package_items where package_id = p_id;

    insert into public.valvet_package_items (package_id, member_id, sort_order)
    select p_id, pid, row_number() over () - 1
      from unnest(p_prompt_ids) as pid;

    insert into app_private.mcp_write_attempts (key_hash, workspace_id, tool, outcome)
    values (p_key_hash, v_ws.id, 'update_my_package_items', 'success');

    return v_pkg;
end;
$$;

revoke all on function app_private.update_my_package_items_for_key(text, uuid, uuid[]) from public;

create or replace function public.update_my_package_items_for_key(
    p_key_hash text, p_id uuid, p_prompt_ids uuid[]
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.update_my_package_items_for_key(p_key_hash, p_id, p_prompt_ids);
$$;

revoke all on function public.update_my_package_items_for_key(text, uuid, uuid[]) from public;
grant execute on function public.update_my_package_items_for_key(text, uuid, uuid[]) to anon, authenticated;
```

- [ ] **Step 2: Append to the verify script**

```sql
-- 9. Ersätt medlemslistan med en ny (bara prompt-1 och prompt-3, ny ordning).
select * from public.update_my_package_items_for_key(
    '<key_hash>', '<id-fran-steg-1>', array['<prompt-id-3>', '<prompt-id-1>']::uuid[]
);
select member_id, sort_order from public.valvet_package_items
 where package_id = '<id-fran-steg-1>' order by sort_order;
-- Förväntat: bara 2 rader kvar, prompt-id-3 sort_order=0, prompt-id-1 sort_order=1.

-- 10. Tomt prompt_ids[] på en uppdatering -> avvisas, gammal lista orörd.
select * from public.update_my_package_items_for_key('<key_hash>', '<id-fran-steg-1>', array[]::uuid[]);
-- Förväntat: ERROR 'Ett paket behöver minst en prompt.'
select count(*) from public.valvet_package_items where package_id = '<id-fran-steg-1>';
-- Förväntat: fortfarande 2 (steg 9:s lista, inte raderad av det misslyckade anropet).

-- 11. Uppdatera ett id som inte är ett paket (t.ex. prompt-id-1 självt) -> avvisas.
select * from public.update_my_package_items_for_key('<key_hash>', '<prompt-id-1>', array['<prompt-id-3>']::uuid[]);
-- Förväntat: ERROR 'Paketet hittades inte.'
```

- [ ] **Step 3: Deploy and run steps 9–11**

Same deploy method as Tasks 1–2. Confirm all match expectations, especially step 10's "old list untouched on rejected call."

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260806100000_valvet_custom_packages.sql supabase/tests/verify_valvet_custom_packages.sql
git commit -m "feat(db): add update_my_package_items_for_key RPC"
```

---

### Task 4: `vault.py` — Python RPC wrappers

**Files:**
- Modify: `mcp-server/server/vault.py` (mcp_promptbanken repo)

**Interfaces:**
- Consumes: `create_custom_package_for_key`, `get_my_package_for_key`, `update_my_package_items_for_key` (Tasks 1–3), `_hash_key`, `is_configured`, `_call_rpc` (all already in this file).
- Produces: `create_package(mcp_key, title, description, category, prompt_ids) -> dict[str, Any]`, `get_package(mcp_key, package_id) -> list[dict[str, Any]]`, `update_package_items(mcp_key, package_id, prompt_ids) -> dict[str, Any]`.

- [ ] **Step 1: Add the three functions**

Append to `mcp-server/server/vault.py`, after `copy_template` (end of file):

```python
def create_package(
    mcp_key: str,
    title: str,
    description: str,
    category: str | None,
    prompt_ids: list[str],
) -> dict[str, Any]:
    """Create a new package bundling existing Valvet items. Lets exceptions
    propagate -- same reasoning as save_item: a silent failure would hide
    from the client model that the write didn't happen."""
    if not mcp_key or not is_configured():
        raise RuntimeError("MCP-nyckel saknas eller SUPABASE_URL/SUPABASE_ANON_KEY är inte konfigurerat.")
    return _call_rpc(
        "create_custom_package_for_key",
        {
            "p_key_hash": _hash_key(mcp_key),
            "p_title": title,
            "p_description": description,
            "p_category": category,
            "p_prompt_ids": prompt_ids,
        },
    )


def get_package(mcp_key: str, package_id: str) -> list[dict[str, Any]]:
    """Fetch one package with its expanded, ordered, non-archived members.
    Empty list means not found / not owned / not a package -- same
    convention as get_item returning None."""
    if not mcp_key or not is_configured():
        return []
    try:
        return _call_rpc(
            "get_my_package_for_key", {"p_key_hash": _hash_key(mcp_key), "p_id": package_id}
        )
    except Exception as exc:
        logger.error("get_my_package_failed error=%s", exc)
        return []


def update_package_items(mcp_key: str, package_id: str, prompt_ids: list[str]) -> dict[str, Any]:
    """Replace a package's entire membership list atomically. Lets
    exceptions propagate -- same reasoning as update_item."""
    if not mcp_key or not is_configured():
        raise RuntimeError("MCP-nyckel saknas eller SUPABASE_URL/SUPABASE_ANON_KEY är inte konfigurerat.")
    return _call_rpc(
        "update_my_package_items_for_key",
        {
            "p_key_hash": _hash_key(mcp_key),
            "p_id": package_id,
            "p_prompt_ids": prompt_ids,
        },
    )
```

- [ ] **Step 2: Sanity-check with a local Python import**

Run: `cd mcp-server && python -c "from server import vault; print(vault.create_package, vault.get_package, vault.update_package_items)"`
Expected: prints three `<function ...>` reprs, no `ImportError`/`SyntaxError`.

- [ ] **Step 3: Commit**

```bash
git add mcp-server/server/vault.py
git commit -m "feat(mcp): add create_package/get_package/update_package_items to vault.py"
```

---

### Task 5: Register the three MCP tools in `mcp_server.py`

**Files:**
- Modify: `mcp-server/server/mcp_server.py`

**Interfaces:**
- Consumes: `vault.create_package`/`vault.get_package`/`vault.update_package_items` (Task 4), imported the same way the six existing vault functions already are (`from .vault import save_item as _vault_save_item` etc., near the top of the file).
- Produces: three new entries in `_tool_definitions()` (HTTP surface), three new `tools/call` branches in `_handle_mcp_message`, three new `@mcp.tool()` functions (stdio surface, gated `if SERVER_MODE != "hosted":` like every other Valvet tool).

- [ ] **Step 1: Import the three new vault functions**

Find this existing import block near the top of `mcp_server.py`:

```python
from .vault import list_items as _vault_list_items
from .vault import search_items as _vault_search_items
from .vault import get_item as _vault_get_item
from .vault import save_item as _vault_save_item
from .vault import update_item as _vault_update_item
from .vault import archive_item as _vault_archive_item
from .vault import log_write_attempt as _vault_log_write_attempt
from .vault import list_active_packages as _vault_list_active_packages
from .vault import activate_package as _vault_activate_package
from .vault import deactivate_package as _vault_deactivate_package
from .vault import copy_template as _vault_copy_template
```

Add immediately after it:

```python
from .vault import create_package as _vault_create_package
from .vault import get_package as _vault_get_package
from .vault import update_package_items as _vault_update_package_items
```

- [ ] **Step 2: Add HTTP tool definitions**

In `_tool_definitions()`, find the `archive_my_item` entry (ends right before `list_active_packages`) and insert these three entries right after it, before the existing `list_active_packages` entry:

```python
        {
            "name": "create_custom_package",
            "description": (
                "Create a new package bundling several of the caller's own existing "
                "Valvet items (from list_my_items/get_my_item) into one named, ordered, "
                "private unit. Every id in prompt_ids must already exist in the caller's "
                "Valvet and not be archived -- an invalid id rejects the whole call, no "
                "partial package is created. Retrieve the package afterwards with "
                "get_my_package (it also shows up in list_my_items/search_my_items as "
                "type='package'). To add/remove/reorder members later, use "
                "update_my_package_items (title/description/category are edited via the "
                "regular update_my_item, the package is just a normal Valvet item)."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "description": {"type": "string"},
                    "category": {"type": "string"},
                    "prompt_ids": {"type": "array", "items": {"type": "string", "format": "uuid"}},
                },
                "required": ["title", "prompt_ids"],
                "additionalProperties": False,
            },
        },
        {
            "name": "get_my_package",
            "description": (
                "Fetch one package with its members expanded in order (each member's "
                "id/type/title/content/category/status). Archived members are omitted "
                "from the list but stay linked -- they reappear automatically if "
                "restored, no update_my_package_items call needed. Empty result means "
                "the id doesn't exist, isn't yours, or isn't a package."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {"id": {"type": "string", "format": "uuid"}},
                "required": ["id"],
                "additionalProperties": False,
            },
        },
        {
            "name": "update_my_package_items",
            "description": (
                "Replace a package's ENTIRE member list atomically (not an add/remove "
                "diff) -- pass the full new prompt_ids array in the order you want. "
                "Same validation as create_custom_package: every id must already exist "
                "in the caller's Valvet and not be archived, or the whole call is "
                "rejected and the old list is left untouched."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "id": {"type": "string", "format": "uuid"},
                    "prompt_ids": {"type": "array", "items": {"type": "string", "format": "uuid"}},
                },
                "required": ["id", "prompt_ids"],
                "additionalProperties": False,
            },
        },
```

- [ ] **Step 3: Add dispatch branches in `_handle_mcp_message`**

Find the existing `if tool_name == "archive_my_item":` branch inside the `tools/call` handling in `_handle_mcp_message`. It looks like this (paraphrased from the existing `save_my_item`/`get_my_item` branches you'll see right above it):

```python
        if tool_name == "archive_my_item":
            ...
            return _json_rpc_result(request_id, _mcp_content_result(result))
```

Insert these three branches immediately after it:

```python
        if tool_name == "create_custom_package":
            title = arguments.get("title")
            prompt_ids = arguments.get("prompt_ids")
            if not isinstance(title, str) or not title:
                return _json_rpc_error(request_id, -32602, "Invalid create_custom_package arguments")
            if not isinstance(prompt_ids, list) or not all(isinstance(p, str) for p in prompt_ids):
                return _json_rpc_error(request_id, -32602, "Invalid create_custom_package arguments")
            try:
                result = _vault_create_package(
                    mcp_key,
                    title,
                    arguments.get("description", ""),
                    arguments.get("category"),
                    prompt_ids,
                )
                return _json_rpc_result(request_id, _mcp_content_result(result))
            except httpx.HTTPStatusError as exc:
                return _json_rpc_result(request_id, _mcp_content_result(
                    {"status": "error", "message": _clean_http_error_message(exc)}
                ))
        if tool_name == "get_my_package":
            package_id = arguments.get("id")
            if not isinstance(package_id, str) or not package_id:
                return _json_rpc_error(request_id, -32602, "Invalid get_my_package arguments")
            return _json_rpc_result(request_id, _mcp_content_result(
                {"members": _vault_get_package(mcp_key, package_id)}
            ))
        if tool_name == "update_my_package_items":
            package_id = arguments.get("id")
            prompt_ids = arguments.get("prompt_ids")
            if not isinstance(package_id, str) or not package_id:
                return _json_rpc_error(request_id, -32602, "Invalid update_my_package_items arguments")
            if not isinstance(prompt_ids, list) or not all(isinstance(p, str) for p in prompt_ids):
                return _json_rpc_error(request_id, -32602, "Invalid update_my_package_items arguments")
            try:
                result = _vault_update_package_items(mcp_key, package_id, prompt_ids)
                return _json_rpc_result(request_id, _mcp_content_result(result))
            except httpx.HTTPStatusError as exc:
                return _json_rpc_result(request_id, _mcp_content_result(
                    {"status": "error", "message": _clean_http_error_message(exc)}
                ))
```

Check `_clean_http_error_message` is already imported/defined in this file (it's used by `save_workspace_prompt`'s error path) -- if it only lives in a helper used by a different function, reuse the exact same call already made elsewhere in this file for `save_my_item`'s error handling instead of inventing a new pattern.

- [ ] **Step 4: Add stdio `@mcp.tool()` functions**

Find the existing stdio block:

```python
if SERVER_MODE != "hosted":
    @mcp.tool()
    def archive_my_item(id: str, confirm: bool, restore: bool = False) -> dict[str, Any]:
        ...
```

Insert immediately after it:

```python
if SERVER_MODE != "hosted":
    @mcp.tool()
    def create_custom_package(
        title: str,
        prompt_ids: list[str],
        description: str = "",
        category: str | None = None,
    ) -> dict[str, Any]:
        """Create a new package bundling several of the caller's own existing
        Valvet items into one named, ordered, private unit. Every id in
        prompt_ids must already exist in the caller's Valvet and not be
        archived -- an invalid id rejects the whole call. Retrieve the
        package afterwards with get_my_package (it also shows up in
        list_my_items/search_my_items as type='package')."""
        logger.info("tool_call name=create_custom_package")
        return _vault_create_package("", title, description, category, prompt_ids)


if SERVER_MODE != "hosted":
    @mcp.tool()
    def get_my_package(id: str) -> dict[str, Any]:
        """Fetch one package with its members expanded in order. Archived
        members are omitted but stay linked -- they reappear automatically
        if restored. Empty result means the id doesn't exist, isn't yours,
        or isn't a package."""
        logger.info("tool_call name=get_my_package")
        return {"members": _vault_get_package("", id)}


if SERVER_MODE != "hosted":
    @mcp.tool()
    def update_my_package_items(id: str, prompt_ids: list[str]) -> dict[str, Any]:
        """Replace a package's ENTIRE member list atomically -- pass the full
        new prompt_ids array in the order you want. Same validation as
        create_custom_package."""
        logger.info("tool_call name=update_my_package_items")
        return _vault_update_package_items("", id, prompt_ids)
```

- [ ] **Step 5: Verify syntax**

Run: `cd mcp-server && python -m py_compile server/mcp_server.py`
Expected: no output, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add mcp-server/server/mcp_server.py
git commit -m "feat(mcp): register create_custom_package/get_my_package/update_my_package_items tools"
```

---

### Task 6: Allow the three tools through `HostedMetadataGuard`

**Files:**
- Modify: `mcp-server/server/hosted_guard.py`

**Interfaces:**
- Consumes: nothing new — extends the existing `allowed_methods` set and `allowed_tool_args` dict already defined in `HostedMetadataGuard.__init__`.
- Produces: the guard no longer blocks these three tool names on the hosted `/mcp`/`/mcp/key` routes (without this, Task 5's HTTP dispatch code is unreachable in production — every existing Valvet tool has a matching guard entry, this is not optional).

- [ ] **Step 1: Add to `allowed_methods`**

Find this block in `HostedMetadataGuard.__init__`:

```python
            "list_active_packages",
            "activate_package",
            "deactivate_package",
            "copy_template_to_valvet",
            "recommend_packages",
        }
```

Change to:

```python
            "list_active_packages",
            "activate_package",
            "deactivate_package",
            "copy_template_to_valvet",
            "create_custom_package",
            "get_my_package",
            "update_my_package_items",
            "recommend_packages",
        }
```

- [ ] **Step 2: Add to `allowed_tool_args`**

Find this block right after it:

```python
            "list_active_packages": set(),
            "activate_package": {"area"},
            "deactivate_package": {"area"},
            "copy_template_to_valvet": {"template_id", "confirm"},
            "recommend_packages": {"role"},
        }
```

Change to:

```python
            "list_active_packages": set(),
            "activate_package": {"area"},
            "deactivate_package": {"area"},
            "copy_template_to_valvet": {"template_id", "confirm"},
            "create_custom_package": {"title", "description", "category", "prompt_ids"},
            "get_my_package": {"id"},
            "update_my_package_items": {"id", "prompt_ids"},
            "recommend_packages": {"role"},
        }
```

- [ ] **Step 3: Add per-tool arg validation**

Find `inspect_tool_args`'s `elif tool_name == "copy_template_to_valvet":` branch. Insert immediately after its `elif` block (before the next `elif tool_name == "recommend_packages":`):

```python
        elif tool_name == "create_custom_package":
            title = arguments.get("title")
            prompt_ids = arguments.get("prompt_ids")
            if not isinstance(title, str) or not title:
                return {"reason": "invalid_title", "method": method, "tool": tool_name, "id": request_id}
            if not isinstance(prompt_ids, list) or not prompt_ids or not all(isinstance(p, str) for p in prompt_ids):
                return {"reason": "invalid_prompt_ids", "method": method, "tool": tool_name, "id": request_id}
            description = arguments.get("description")
            if description is not None and not isinstance(description, str):
                return {"reason": "invalid_description", "method": method, "tool": tool_name, "id": request_id}
        elif tool_name == "get_my_package":
            package_id = arguments.get("id")
            if not isinstance(package_id, str) or not package_id:
                return {"reason": "invalid_id", "method": method, "tool": tool_name, "id": request_id}
        elif tool_name == "update_my_package_items":
            package_id = arguments.get("id")
            prompt_ids = arguments.get("prompt_ids")
            if not isinstance(package_id, str) or not package_id:
                return {"reason": "invalid_id", "method": method, "tool": tool_name, "id": request_id}
            if not isinstance(prompt_ids, list) or not prompt_ids or not all(isinstance(p, str) for p in prompt_ids):
                return {"reason": "invalid_prompt_ids", "method": method, "tool": tool_name, "id": request_id}
```

- [ ] **Step 4: Verify syntax**

Run: `cd mcp-server && python -m py_compile server/hosted_guard.py`
Expected: no output, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add mcp-server/server/hosted_guard.py
git commit -m "feat(mcp): allow create_custom_package/get_my_package/update_my_package_items through HostedMetadataGuard"
```

---

### Task 7: Deploy and end-to-end verification

**Files:** none (deploy + manual verification only)

**Interfaces:** none new — this task exercises everything built in Tasks 1–6 together, through the real hosted server, the way ChatGPT/Claude actually will.

- [ ] **Step 1: Deploy the Supabase migration** (if not already deployed live during Tasks 1–3's steps)

`cd promptbanken && supabase db push` — confirm it lists exactly `20260806100000_valvet_custom_packages.sql` and completes with no errors.

- [ ] **Step 2: Deploy mcp_promptbanken to the VPS**

Follow the `vps-deploy` skill exactly (disk-space check first, `git pull`, confirm the diff with the user, `docker-compose up -d --build`, handle the known `ContainerConfig` recreate error if it occurs, verify `/healthz`).

- [ ] **Step 3: End-to-end curl test against the live server**

Using a real Pro test key and two real existing Valvet item ids:

```bash
curl -s -X POST localhost:8000/mcp/key -H "Content-Type: application/json" \
  -H "X-MCP-Key: <test-key>" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_custom_package","arguments":{"title":"E2E testpaket","prompt_ids":["<id-1>","<id-2>"]}}}'
```

Expected: `status`-free success payload with the new package's `id`, `type: "package"`, `module: "valvet"`.

```bash
curl -s -X POST localhost:8000/mcp/key -H "Content-Type: application/json" \
  -H "X-MCP-Key: <test-key>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_my_package","arguments":{"id":"<package-id-from-above>"}}}'
```

Expected: `members` array with 2 rows, matching `<id-1>`/`<id-2>`, correct `member_sort_order`.

- [ ] **Step 4: Update the spec/status docs**

Mark `docs/superpowers/plans/2026-08-05-valvet-custom-packages.md` (this file) and `docs/superpowers/specs/2026-08-05-valvet-custom-packages-design.md` as implemented (one-line note at the top of each, matching how other completed plans in this repo are marked, e.g. `docs: mark unify-catalog-template-source plan complete`). Log completion in the octopus hub (`STATUS.md`, `valvet_promptbanken`/`mcp_promptbanken` sections).

- [ ] **Step 5: Final commit**

```bash
git add docs/superpowers/plans/2026-08-05-valvet-custom-packages.md docs/superpowers/specs/2026-08-05-valvet-custom-packages-design.md
git commit -m "docs: mark valvet-custom-packages plan complete (deployed and verified)"
```
