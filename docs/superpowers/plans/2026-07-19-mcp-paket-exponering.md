# MCP-exponering av promptpaket Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Låt MCP-klienter aktivera/avaktivera promptpaket och kopiera enskilda mallar till Valvet — samma handlingar som webbens "Bläddra i Promptbanken"-flik redan gör, nu nyckelhash-baserat.

**Architecture:** Fyra nya `_for_key`-RPC:er i `promptbanken` (spegel av `save_my_item_for_key`/`archive_my_item_for_key`-mönstret). Fyra nya MCP-verktyg i `mcp_promptbanken` som anropar dem, kopplade in på alla tre ställen ett hostat verktyg kräver (manuell JSON-RPC-dispatch, `tools/list`-schema, REST-route) plus `hosted_guard.py`s allowlist.

**Tech Stack:** Postgres/Supabase (plpgsql), Python (FastMCP, httpx), Starlette REST-routes.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-19-mcp-paket-exponering-design.md` i detta repo.
- `copy_template_to_valvet` kräver `confirm=true`, annars avvisas (`raise exception 'confirm måste vara true för att kopiera en mall.'`).
- `activate_package`/`deactivate_package` rör ALDRIG `mcp_write_attempts` — ingen rate-limit-check, ingen loggning.
- `copy_template_to_valvet_for_key` DELAR rate limit (20/60s) och månadskvot (`app_private.valvet_catalog_copies`) med övriga skrivverktyg/webbens kopiering.
- Alla nya RPC:er: `security definer`, `set search_path = ''`, `app_private.`-implementation + tunn `public.`-wrapper, `revoke all from public`, `grant execute to anon`.
- Docstrings på engelska (matchar övriga verktyg i denna fil); `activate_package`/`deactivate_package` måste uttryckligen instruera modellen att bara anropa på explicit användarönskemål.
- `hosted_guard.py`s allowlist måste hållas i synk med tool-listan (CLAUDE.md-konvention).
- Migrationer mot live-DB körs via Supabase MCP `apply_migration` (samma konvention som tidigare denna session).

---

### Task 1: DB-migration — fyra `_for_key`-RPC:er (`promptbanken`)

**Files:**
- Create: `supabase/tests/verify_mcp_packages.sql`
- Create: `supabase/migrations/20260719120000_mcp_package_rpcs.sql`

**Interfaces:**
- Consumes: `public.valvet_package_activations` (tabell), `app_private.copy_template_to_valvet` (mönster, ej anropad direkt), `public.pro_prompt_templates`, `app_private.valvet_catalog_copies`, `app_private.has_active_pro_entitlement`, `app_private.slugify_candidate`.
- Produces: `public.copy_template_to_valvet_for_key(p_key_hash text, p_template_id uuid, p_confirm boolean) returns public.content_items`, `public.activate_package_for_key(p_key_hash text, p_area text) returns void`, `public.deactivate_package_for_key(p_key_hash text, p_area text) returns void`, `public.list_active_packages_for_key(p_key_hash text) returns table(area text)`. Alla grantade till `anon`. Task 3 anropar dessa fyra.

- [x] **Step 1: Skriv verifieringschecklistan**

`supabase/tests/verify_mcp_packages.sql`:
```sql
-- verify_mcp_packages.sql -- manuell checklista mot live.
-- Delprojekt 4: MCP-exponering av promptpaket.

-- 1. Ogiltig nyckel avvisas på alla fyra:
select public.list_active_packages_for_key('finns-inte');  -- ERROR: Ogiltig nyckel.
select public.activate_package_for_key('finns-inte', 'kommunikation');  -- ERROR: Ogiltig nyckel.
select public.deactivate_package_for_key('finns-inte', 'kommunikation');  -- ERROR: Ogiltig nyckel.
select public.copy_template_to_valvet_for_key('finns-inte', gen_random_uuid(), true);  -- ERROR: Ogiltig nyckel.

-- Med en RIKTIG nyckels sha256-hash nedan (byt in):
-- 2. Aktivera/avaktivera-rundtur, idempotent:
select public.activate_package_for_key('<hash>', 'kommunikation');
select * from public.list_active_packages_for_key('<hash>');  -- 1 rad
select public.activate_package_for_key('<hash>', 'kommunikation');  -- no-op, inget fel
select public.deactivate_package_for_key('<hash>', 'kommunikation');
select * from public.list_active_packages_for_key('<hash>');  -- 0 rader
select public.deactivate_package_for_key('<hash>', 'kommunikation');  -- no-op, inget fel

-- 3. Kopiering kräver confirm=true:
select public.copy_template_to_valvet_for_key('<hash>', '<template-id>', false);
-- ERROR: confirm måste vara true för att kopiera en mall.

-- 4. Kopiering med confirm=true lyckas och räknas mot delad kvot:
select type, title, category, status, visibility, source
  from public.copy_template_to_valvet_for_key('<hash>', '<template-id>', true);
-- prompt / mallens titel / area_label / draft / private / catalog_copy
select * from public.valvet_catalog_copy_quota();  -- used ökat med 1

-- 5. Rate limit (20/60s) delas med andra skrivverktyg, aktivera/avaktivera opåverkade:
-- kör copy_template_to_valvet_for_key 21 ggr snabbt -> 21:a avvisas
-- ("För många försök, vänta en minut och försök igen.");
-- aktivera/avaktivera fungerar fortfarande direkt efter utan väntan.
```

- [x] **Step 2: Skriv migrationen**

`supabase/migrations/20260719120000_mcp_package_rpcs.sql`:
```sql
-- 20260719120000_mcp_package_rpcs.sql
-- Delprojekt 4: MCP-exponering av promptpaket. Fyra nyckelhash-baserade
-- RPC:er, samma mönster som save_my_item_for_key/archive_my_item_for_key
-- (20260716102000/20260716102500). Se
-- docs/superpowers/specs/2026-07-19-mcp-paket-exponering-design.md

create or replace function app_private.copy_template_to_valvet_for_key(
    p_key_hash    text,
    p_template_id uuid,
    p_confirm     boolean
)
returns public.content_items
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key             public.api_keys%rowtype;
    v_ws              public.workspaces%rowtype;
    v_source          public.pro_prompt_templates%rowtype;
    v_row             public.content_items%rowtype;
    v_recent_attempts integer;
    v_copy_count      integer;
    v_slug            text;
    v_is_pro          boolean;
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

    if p_confirm is distinct from true then
        raise exception 'confirm måste vara true för att kopiera en mall.';
    end if;

    select count(*) into v_recent_attempts
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash and created_at >= now() - interval '60 seconds';
    if v_recent_attempts >= 20 then
        raise exception 'För många försök, vänta en minut och försök igen.';
    end if;

    v_is_pro := app_private.has_active_pro_entitlement(v_ws.owner_user_id);

    select * into v_source from public.pro_prompt_templates where id = p_template_id;
    if not found then
        raise exception 'Den här mallen finns inte.';
    end if;

    if not v_is_pro then
        select count(*) into v_copy_count
          from app_private.valvet_catalog_copies
         where workspace_id = v_ws.id
           and created_at >= date_trunc('month', now());
        if v_copy_count >= 5 then
            raise exception 'Månadskvoten på 5 kopior är förbrukad. Uppgradera till Pro för obegränsad kopiering.';
        end if;
    end if;

    v_slug := app_private.slugify_candidate(v_source.title, 'valv');
    while exists (select 1 from public.content_items where workspace_id = v_ws.id and slug = v_slug) loop
        v_slug := app_private.slugify_candidate(v_source.title, 'valv') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    end loop;

    perform set_config('request.jwt.claim.sub', v_ws.owner_user_id::text, true);

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, module, title, slug,
        content, category, status, visibility, source, source_content_item_id
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id,
        'prompt'::public.content_item_type, 'valvet',
        v_source.title, v_slug, v_source.prompt_text, v_source.area_label,
        'draft', 'private', 'catalog_copy', null
    )
    returning * into v_row;

    insert into app_private.valvet_catalog_copies (workspace_id, source_content_item_id)
    values (v_ws.id, p_template_id);

    insert into app_private.mcp_write_attempts (key_hash, workspace_id, tool, outcome)
    values (p_key_hash, v_ws.id, 'copy_template_to_valvet', 'success');

    return v_row;
end;
$$;

revoke all on function app_private.copy_template_to_valvet_for_key(text, uuid, boolean) from public;

create or replace function public.copy_template_to_valvet_for_key(
    p_key_hash text, p_template_id uuid, p_confirm boolean
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.copy_template_to_valvet_for_key(p_key_hash, p_template_id, p_confirm);
$$;

revoke all on function public.copy_template_to_valvet_for_key(text, uuid, boolean) from public;
grant execute on function public.copy_template_to_valvet_for_key(text, uuid, boolean) to anon;


-- Aktivera/avaktivera/lista: rör ALDRIG mcp_write_attempts (varken
-- rate-limit-check eller loggning) -- ren UI-konfiguration, inte en
-- skriv-handling som ska räknas mot delad rate limit.
create or replace function app_private.activate_package_for_key(
    p_key_hash text,
    p_area     text
)
returns void
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
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

    insert into public.valvet_package_activations (workspace_id, area)
    values (v_ws.id, p_area)
    on conflict (workspace_id, area) do nothing;
end;
$$;

revoke all on function app_private.activate_package_for_key(text, text) from public;

create or replace function public.activate_package_for_key(p_key_hash text, p_area text)
returns void
language sql
security definer
set search_path = ''
as $$
    select app_private.activate_package_for_key(p_key_hash, p_area);
$$;

revoke all on function public.activate_package_for_key(text, text) from public;
grant execute on function public.activate_package_for_key(text, text) to anon;


create or replace function app_private.deactivate_package_for_key(
    p_key_hash text,
    p_area     text
)
returns void
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
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

    delete from public.valvet_package_activations
     where workspace_id = v_ws.id and area = p_area;
end;
$$;

revoke all on function app_private.deactivate_package_for_key(text, text) from public;

create or replace function public.deactivate_package_for_key(p_key_hash text, p_area text)
returns void
language sql
security definer
set search_path = ''
as $$
    select app_private.deactivate_package_for_key(p_key_hash, p_area);
$$;

revoke all on function public.deactivate_package_for_key(text, text) from public;
grant execute on function public.deactivate_package_for_key(text, text) to anon;


create or replace function app_private.list_active_packages_for_key(p_key_hash text)
returns table(area text)
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
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

    return query select a.area from public.valvet_package_activations a where a.workspace_id = v_ws.id;
end;
$$;

revoke all on function app_private.list_active_packages_for_key(text) from public;

create or replace function public.list_active_packages_for_key(p_key_hash text)
returns table(area text)
language sql
security definer
set search_path = ''
as $$
    select * from app_private.list_active_packages_for_key(p_key_hash);
$$;

revoke all on function public.list_active_packages_for_key(text) from public;
grant execute on function public.list_active_packages_for_key(text) to anon;
```

- [x] **Step 3: Applicera mot live via Supabase MCP `apply_migration`** (namn `mcp_package_rpcs`).

- [x] **Step 4: Kör checklistans steg 1 (ogiltig nyckel) mot live, bekräfta alla fyra avvisar.**

- [x] **Step 5: Hämta en riktig nyckels sha256-hash och ett riktigt `template_id` för steg 2–5** — kör t.ex.
  `select encode(digest('<en-riktig-mcp-nyckel>', 'sha256'), 'hex');` samt `select id from public.pro_prompt_templates limit 1;`. Kör resten av checklistan mot live.

- [x] **Step 6: Commit**

```powershell
git add supabase/migrations/20260719120000_mcp_package_rpcs.sql supabase/tests/verify_mcp_packages.sql
git commit -m "feat: key-hash RPCs for MCP package activation and template copy"
```

### Task 2: `vault.py` — fyra Python-wrapperfunktioner (`mcp_promptbanken`)

**Files:**
- Modify: `mcp-server/server/vault.py`

**Interfaces:**
- Consumes: Task 1:s fyra RPC:er via `_call_rpc` (redan definierad i denna fil).
- Produces: `activate_package(mcp_key, area) -> None`, `deactivate_package(mcp_key, area) -> None`, `list_active_packages(mcp_key) -> list[str]`, `copy_template(mcp_key, template_id, confirm) -> dict`. Task 3 importerar dessa fyra.

- [x] **Step 1:** Lägg till i slutet av `vault.py` (efter befintliga `log_write_attempt`, före ev. filslut):

```python
def list_active_packages(mcp_key: str) -> list[str]:
    """List the areas (package identifiers) the caller's workspace has activated."""
    if not mcp_key or not is_configured():
        return []
    try:
        rows = _call_rpc("list_active_packages_for_key", {"p_key_hash": _hash_key(mcp_key)})
        return [row["area"] for row in rows]
    except Exception as exc:
        logger.error("list_active_packages_failed error=%s", exc)
        return []


def activate_package(mcp_key: str, area: str) -> None:
    """Activate a prompt package (idempotent). Lets exceptions propagate --
    same reasoning as save_item: a silent failure would hide from the
    client model that the activation didn't happen."""
    if not mcp_key or not is_configured():
        raise RuntimeError("MCP-nyckel saknas eller SUPABASE_URL/SUPABASE_ANON_KEY är inte konfigurerat.")
    _call_rpc("activate_package_for_key", {"p_key_hash": _hash_key(mcp_key), "p_area": area})


def deactivate_package(mcp_key: str, area: str) -> None:
    """Deactivate a prompt package (idempotent)."""
    if not mcp_key or not is_configured():
        raise RuntimeError("MCP-nyckel saknas eller SUPABASE_URL/SUPABASE_ANON_KEY är inte konfigurerat.")
    _call_rpc("deactivate_package_for_key", {"p_key_hash": _hash_key(mcp_key), "p_area": area})


def copy_template(mcp_key: str, template_id: str, confirm: bool) -> dict[str, Any]:
    """Copy one prompt package template into the caller's Valvet. Requires
    confirm=true -- it creates real content and counts against the shared
    monthly copy quota."""
    if not mcp_key or not is_configured():
        raise RuntimeError("MCP-nyckel saknas eller SUPABASE_URL/SUPABASE_ANON_KEY är inte konfigurerat.")
    return _call_rpc(
        "copy_template_to_valvet_for_key",
        {"p_key_hash": _hash_key(mcp_key), "p_template_id": template_id, "p_confirm": confirm},
    )
```

- [x] **Step 2:** `python -m py_compile mcp-server/server/vault.py` — OK.

- [x] **Step 3: Commit** — `git commit -m "feat: vault.py wrappers for package activation and template copy"`

### Task 3: `mcp_server.py` — fyra verktyg, tre inkopplingsställen

**Files:**
- Modify: `mcp-server/server/mcp_server.py`

**Interfaces:**
- Consumes: Task 2:s fyra funktioner (importeras som `_vault_list_active_packages`, `_vault_activate_package`, `_vault_deactivate_package`, `_vault_copy_template`, samma aliasing-konvention som rad 28–34).
- Produces: fyra nya MCP-tools synliga i `tools/list`: `list_active_packages`, `activate_package`, `deactivate_package`, `copy_template_to_valvet`.

- [x] **Step 1: Imports** — lägg till efter rad 34 (`from .vault import log_write_attempt as _vault_log_write_attempt`):

```python
from .vault import list_active_packages as _vault_list_active_packages
from .vault import activate_package as _vault_activate_package
from .vault import deactivate_package as _vault_deactivate_package
from .vault import copy_template as _vault_copy_template
```

- [x] **Step 2: Payload-helpers** — lägg till efter `_archive_my_item_payload` (efter rad 304):

```python
def _list_active_packages_payload(mcp_key: str) -> dict[str, Any]:
    if not mcp_key:
        return {"areas": []}
    return {"areas": _vault_list_active_packages(mcp_key)}


def _activate_package_payload(mcp_key: str, area: str) -> dict[str, Any]:
    if not mcp_key:
        return {"status": "error", "message": "MCP-nyckel krävs (X-MCP-Key eller Authorization)."}
    try:
        _vault_activate_package(mcp_key, area)
        return {"status": "success", "area": area}
    except httpx.HTTPStatusError as exc:
        logger.info("tool_call name=activate_package status=error detail=%s", exc.response.text)
        return {"status": "error", "message": _clean_http_error_message(exc)}
    except RuntimeError as exc:
        return {"status": "error", "message": str(exc)}
    except Exception as exc:
        logger.error("activate_package_failed error=%s", exc)
        return {"status": "error", "message": "Kunde inte aktivera paketet."}


def _deactivate_package_payload(mcp_key: str, area: str) -> dict[str, Any]:
    if not mcp_key:
        return {"status": "error", "message": "MCP-nyckel krävs (X-MCP-Key eller Authorization)."}
    try:
        _vault_deactivate_package(mcp_key, area)
        return {"status": "success", "area": area}
    except httpx.HTTPStatusError as exc:
        logger.info("tool_call name=deactivate_package status=error detail=%s", exc.response.text)
        return {"status": "error", "message": _clean_http_error_message(exc)}
    except RuntimeError as exc:
        return {"status": "error", "message": str(exc)}
    except Exception as exc:
        logger.error("deactivate_package_failed error=%s", exc)
        return {"status": "error", "message": "Kunde inte avaktivera paketet."}


def _copy_template_to_valvet_payload(mcp_key: str, template_id: str, confirm: bool) -> dict[str, Any]:
    if not mcp_key:
        return {"status": "error", "message": "MCP-nyckel krävs (X-MCP-Key eller Authorization)."}
    try:
        item = _vault_copy_template(mcp_key, template_id, confirm)
        return {"status": "success", "item": item}
    except httpx.HTTPStatusError as exc:
        detail = exc.response.text
        logger.info("tool_call name=copy_template_to_valvet status=error detail=%s", detail)
        outcome = _classify_vault_write_error(detail)
        _vault_log_write_attempt(mcp_key, "copy_template_to_valvet", outcome)
        return {"status": "error", "message": _clean_http_error_message(exc)}
    except RuntimeError as exc:
        return {"status": "error", "message": str(exc)}
    except Exception as exc:
        logger.error("copy_template_to_valvet_failed error=%s", exc)
        return {"status": "error", "message": "Kunde inte kopiera mallen."}
```

- [x] **Step 3: `_tool_definitions()` — lägg till fyra scheman** direkt efter `archive_my_item`s block (leta upp `"name": "archive_my_item"` i `_tool_definitions()`, infoga efter dess stängande `},`):

```python
        {
            "name": "list_active_packages",
            "description": (
                "List the prompt packages (areas) the caller's Valvet workspace has "
                "activated. Activation only affects which packages the user sees "
                "expanded on their Valvet web page -- it never changes what "
                "list_pro_templates returns."
            ),
            "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        },
        {
            "name": "activate_package",
            "description": (
                "Activate a prompt package (identified by its 'area' field from "
                "list_pro_templates) so its templates appear expanded on the user's "
                "Valvet page. Idempotent. Only call this when the user has explicitly "
                "asked to activate a package -- do not call it proactively just "
                "because it seems helpful."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {"area": {"type": "string"}},
                "required": ["area"],
                "additionalProperties": False,
            },
        },
        {
            "name": "deactivate_package",
            "description": (
                "Deactivate a prompt package. Idempotent. Only call this when the "
                "user has explicitly asked to deactivate a package -- do not call it "
                "proactively just because it seems helpful."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {"area": {"type": "string"}},
                "required": ["area"],
                "additionalProperties": False,
            },
        },
        {
            "name": "copy_template_to_valvet",
            "description": (
                "Copy one prompt template (from list_pro_templates, identified by its "
                "id) into the caller's Valvet as a real, independent, editable item. "
                "Requires confirm=true -- it creates content and counts against the "
                "shared monthly copy quota (Free: 5/calendar month, Pro: unlimited)."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "template_id": {"type": "string", "format": "uuid"},
                    "confirm": {"type": "boolean"},
                },
                "required": ["template_id", "confirm"],
                "additionalProperties": False,
            },
        },
```

- [x] **Step 4: Manuell JSON-RPC-dispatch** — lägg till efter `archive_my_item`s block i dispatchen (efter raden `return _json_rpc_error(request_id, -32601, "Tool not found")`s FÖREGÅENDE block, dvs efter det `if tool_name == "archive_my_item": ... )` blocket och FÖRE `return _json_rpc_error(request_id, -32601, "Tool not found")`):

```python
        if tool_name == "list_active_packages":
            return _json_rpc_result(request_id, _mcp_content_result(_list_active_packages_payload(mcp_key)))
        if tool_name == "activate_package":
            area = arguments.get("area")
            if not isinstance(area, str) or not area:
                return _json_rpc_error(request_id, -32602, "Invalid activate_package arguments")
            return _json_rpc_result(request_id, _mcp_content_result(_activate_package_payload(mcp_key, area)))
        if tool_name == "deactivate_package":
            area = arguments.get("area")
            if not isinstance(area, str) or not area:
                return _json_rpc_error(request_id, -32602, "Invalid deactivate_package arguments")
            return _json_rpc_result(request_id, _mcp_content_result(_deactivate_package_payload(mcp_key, area)))
        if tool_name == "copy_template_to_valvet":
            template_id = arguments.get("template_id")
            confirm = arguments.get("confirm")
            if not isinstance(template_id, str) or not template_id or not isinstance(confirm, bool):
                return _json_rpc_error(request_id, -32602, "Invalid copy_template_to_valvet arguments")
            return _json_rpc_result(
                request_id, _mcp_content_result(_copy_template_to_valvet_payload(mcp_key, template_id, confirm))
            )
```

- [x] **Step 5: `@mcp.tool()`-registrering** — lägg till i slutet av filen, efter `archive_my_item`s decorerade funktion (samma stil, tom-sträng-nyckel för local-mode-symmetri):

```python
@mcp.tool()
def list_active_packages() -> dict[str, Any]:
    """List activated prompt packages (see tools/call description above)."""
    logger.info("tool_call name=list_active_packages")
    return _list_active_packages_payload("")


@mcp.tool()
def activate_package(area: str) -> dict[str, Any]:
    """Activate a prompt package (see tools/call description above)."""
    logger.info("tool_call name=activate_package")
    return _activate_package_payload("", area)


@mcp.tool()
def deactivate_package(area: str) -> dict[str, Any]:
    """Deactivate a prompt package (see tools/call description above)."""
    logger.info("tool_call name=deactivate_package")
    return _deactivate_package_payload("", area)


@mcp.tool()
def copy_template_to_valvet(template_id: str, confirm: bool) -> dict[str, Any]:
    """Copy a prompt template to Valvet (see tools/call description above)."""
    logger.info("tool_call name=copy_template_to_valvet")
    return _copy_template_to_valvet_payload("", template_id, confirm)
```

- [x] **Step 6: REST-endpoints** — lägg till efter den sista `/api/v1/vault/items/{item_id}/archive`-endpointfunktionen (leta upp `_api_vault_archive_item` eller motsvarande, infoga efter den):

```python
async def _api_vault_list_active_packages(request: Request) -> JSONResponse:
    mcp_key = _mcp_key_from_request(request)
    payload = _list_active_packages_payload(mcp_key)
    logger.info("http_request path=/api/v1/vault/packages status=200")
    return JSONResponse(payload)


async def _api_vault_activate_package(request: Request) -> JSONResponse:
    mcp_key = _mcp_key_from_request(request)
    body = await request.json()
    area = body.get("area") if isinstance(body, dict) else None
    if not isinstance(area, str) or not area:
        return JSONResponse({"status": "error", "message": "area krävs."}, status_code=400)
    payload = _activate_package_payload(mcp_key, area)
    status_code = 200 if payload.get("status") == "success" else 400
    logger.info("http_request path=/api/v1/vault/packages method=POST status=%s", status_code)
    return JSONResponse(payload, status_code=status_code)


async def _api_vault_deactivate_package(request: Request) -> JSONResponse:
    mcp_key = _mcp_key_from_request(request)
    area = request.path_params["area"]
    payload = _deactivate_package_payload(mcp_key, area)
    status_code = 200 if payload.get("status") == "success" else 400
    logger.info("http_request path=/api/v1/vault/packages/%s method=DELETE status=%s", area, status_code)
    return JSONResponse(payload, status_code=status_code)


async def _api_vault_copy_template(request: Request) -> JSONResponse:
    mcp_key = _mcp_key_from_request(request)
    body = await request.json()
    template_id = body.get("template_id") if isinstance(body, dict) else None
    confirm = body.get("confirm") if isinstance(body, dict) else None
    if not isinstance(template_id, str) or not template_id or not isinstance(confirm, bool):
        return JSONResponse({"status": "error", "message": "template_id och confirm krävs."}, status_code=400)
    payload = _copy_template_to_valvet_payload(mcp_key, template_id, confirm)
    status_code = 200 if payload.get("status") == "success" else 400
    logger.info("http_request path=/api/v1/vault/packages/copy method=POST status=%s", status_code)
    return JSONResponse(payload, status_code=status_code)
```

- [x] **Step 7: Route-registrering** — lägg till i `Route(...)`-listan direkt efter den sista `/api/v1/vault/items/{item_id}/archive`-raden:

```python
            Route("/api/v1/vault/packages", endpoint=_api_vault_list_active_packages, methods=["GET"]),
            Route("/api/v1/vault/packages", endpoint=_api_vault_activate_package, methods=["POST"]),
            Route("/api/v1/vault/packages/{area}", endpoint=_api_vault_deactivate_package, methods=["DELETE"]),
            Route("/api/v1/vault/packages/copy", endpoint=_api_vault_copy_template, methods=["POST"]),
```

- [x] **Step 8:** `python -m py_compile mcp-server/server/mcp_server.py` — OK.

- [x] **Step 9: Commit** — `git commit -m "feat: MCP tools for package activation and template copy"`

### Task 4: `hosted_guard.py` — allowlist

**Files:**
- Modify: `mcp-server/server/hosted_guard.py`

- [x] **Step 1:** Lägg till i `self.allowed_methods` (efter `"archive_my_item",`):

```python
            "list_active_packages",
            "activate_package",
            "deactivate_package",
            "copy_template_to_valvet",
```

- [x] **Step 2:** Lägg till i `self.allowed_tool_args` (efter `"archive_my_item": {"id", "confirm", "restore"},`):

```python
            "list_active_packages": set(),
            "activate_package": {"area"},
            "deactivate_package": {"area"},
            "copy_template_to_valvet": {"template_id", "confirm"},
```

- [x] **Step 3:** Lägg till valideringsgrenar i `inspect_tool_args` (efter `archive_my_item`-grenen, före `elif arguments:`):

```python
        elif tool_name == "list_active_packages":
            pass
        elif tool_name in ("activate_package", "deactivate_package"):
            area = arguments.get("area")
            if not isinstance(area, str) or not area:
                return {"reason": "invalid_area", "method": method, "tool": tool_name, "id": request_id}
        elif tool_name == "copy_template_to_valvet":
            template_id = arguments.get("template_id")
            confirm = arguments.get("confirm")
            if not isinstance(template_id, str) or not template_id or not isinstance(confirm, bool):
                return {"reason": "invalid_copy_template_arguments", "method": method, "tool": tool_name, "id": request_id}
```

- [x] **Step 4:** `python -m py_compile mcp-server/server/hosted_guard.py` — OK.

- [x] **Step 5: Commit** — `git commit -m "feat: allow package tools through hosted metadata guard"`

### Task 5: Deploy + end-to-end-verifiering

- [x] **Step 1:** Push till origin/main.
- [x] **Step 2:** VPS: `ssh promptbanken-vps` → `cd ~/mcp_promptbanken && git pull --ff-only && docker-compose up -d --build` (ContainerConfig-workaround vid behov).
- [x] **Step 3:** `curl -s -X POST https://mcp.promptbanken.se/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -H 'X-MCP-Key: <riktig-nyckel>' -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"activate_package","arguments":{"area":"kommunikation"}}}'` — `status: success`.
- [x] **Step 4:** Samma mot `copy_template_to_valvet` med `confirm:false` (avvisas) och `confirm:true` (lyckas).
- [x] **Step 5:** Browser: verifiera i Valvets webbflik att paketet aktiverat via MCP visas expanderat, och att mallen kopierad via MCP syns under "Mina insättningar".
- [x] **Step 6:** Uppdatera minnesfilen `valvet-fas1-status` med utfallet.
