# Rollbaserade rekommendationer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nytt read-only MCP-verktyg `recommend_packages(role)` som föreslår promptpaket utifrån en yrkesroll — inget lagras, ingen nyckel krävs, ingen DB-ändring.

**Architecture:** Statisk rollmappning + `SkillRouter._normalize`-återanvändning i en ny liten fil, inkopplad i `mcp_server.py` på samma tre ställen som varje hostat verktyg kräver.

**Tech Stack:** Python (FastMCP).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-19-rollbaserade-rekommendationer-design.md` i `promptbanken`-repot.
- Ingen DB-migration. Ingen nyckel krävs för verktyget.
- Rollmappningen är exakt den Peter godkände (se spec-tabellen) — `arbetsbank` är universellt (matchar alltid).
- Okänd roll → returnera alla 7 områden med `role_recognized: false`, aldrig tomt.
- Återanvänd `SkillRouter._normalize` (statisk metod, `skill_router.py`) — inga nya normaliseringsregler.

---

### Task 1: `package_recommendations.py` + inkoppling i `mcp_server.py` (`mcp_promptbanken`)

**Files:**
- Create: `mcp-server/server/package_recommendations.py`
- Modify: `mcp-server/server/mcp_server.py`
- Modify: `mcp-server/server/hosted_guard.py`

**Interfaces:**
- Consumes: `SkillRouter._normalize` (`skill_router.py`), `pro_templates.list_pro_templates("")` (redan öppen, returnerar `area`/`area_label` per mall).
- Produces: `recommend(role: str, templates: list[dict]) -> dict` med formen `{"role_recognized": bool, "packages": [{"area": str, "area_label": str, "template_count": int}]}`.

- [x] **Step 1: Skriv `package_recommendations.py`**

```python
"""Rollbaserade paketrekommendationer (delprojekt 5). Statisk mappning
område -> roller, godkänd av Peter 2026-07-19 (se
docs/superpowers/specs/2026-07-19-rollbaserade-rekommendationer-design.md
i promptbanken-repot). Ingen nyckel, ingen lagrad roll -- ren funktion av
en klient-skickad rollterm.
"""
from __future__ import annotations

from typing import Any

from .skill_router import SkillRouter

# None = universellt (matchar alltid, oavsett roll).
_AREA_ROLES: dict[str, set[str] | None] = {
    "kommunikation": {"kommunikator", "handlaggare", "kundcenter"},
    "forandringsledning": {"samordnare", "verksamhetsutvecklare", "chef"},
    "processer": {"verksamhetsutvecklare", "utredare", "samordnare"},
    "beslutsberedning": {"utredare", "handlaggare", "chef", "sekreterare"},
    "visuellt": {"kommunikator", "pedagog"},
    "ledarskap": {"chef", "samordnare"},
    "arbetsbank": None,
}


def recommend(role: str, templates: list[dict[str, Any]]) -> dict[str, Any]:
    """templates: the full list_pro_templates() payload (area/area_label per row)."""
    areas: dict[str, str] = {}
    for t in templates:
        areas.setdefault(t["area"], t["area_label"])

    counts: dict[str, int] = {}
    for t in templates:
        counts[t["area"]] = counts.get(t["area"], 0) + 1

    normalized_role = SkillRouter._normalize(role)
    matched_areas = [
        area
        for area, roles in _AREA_ROLES.items()
        if area in areas and (roles is None or normalized_role in {SkillRouter._normalize(r) for r in roles})
    ]

    role_recognized = bool(matched_areas) and any(
        _AREA_ROLES[area] is not None for area in matched_areas
    )
    result_areas = matched_areas if role_recognized else list(areas.keys())

    packages = [
        {"area": area, "area_label": areas[area], "template_count": counts.get(area, 0)}
        for area in result_areas
    ]
    return {"role_recognized": role_recognized, "packages": packages}
```

- [x] **Step 2: Kompilera** — `python -m py_compile mcp-server/server/package_recommendations.py` — OK.

- [x] **Step 3: Import + payload-helper i `mcp_server.py`** — lägg till importen bredvid övriga `.vault`-importer (efter `from .vault import copy_template as _vault_copy_template`):

```python
from .package_recommendations import recommend as _recommend_packages
```

Lägg till payload-helper efter `_copy_template_to_valvet_payload`:

```python
def _recommend_packages_payload(role: str) -> dict[str, Any]:
    templates = _fetch_pro_templates("")
    return _recommend_packages(role, templates)
```

(`_fetch_pro_templates` är redan importerad högre upp i filen som `from .pro_templates import list_pro_templates as _fetch_pro_templates` — verifiera exakt aliasnamn i filen innan du skriver raden; om aliaset heter något annat, använd det istället.)

- [x] **Step 4: `_tool_definitions()`** — lägg till sist i listan (efter `copy_template_to_valvet`s block, före den avslutande `]`):

```python
        {
            "name": "recommend_packages",
            "description": (
                "Recommend prompt packages (areas) suited to a job role. Pass a "
                "short role term (e.g. 'chef', 'kommunikator') -- if the calling "
                "client doesn't know the user's role, it should ask the user first. "
                "If the role isn't recognized, all packages are returned with "
                "role_recognized=false rather than an empty result."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {"role": {"type": "string"}},
                "required": ["role"],
                "additionalProperties": False,
            },
        },
```

- [x] **Step 5: Manuell JSON-RPC-dispatch** — lägg till efter `copy_template_to_valvet`s block, före `return _json_rpc_error(request_id, -32601, "Tool not found")`:

```python
        if tool_name == "recommend_packages":
            role = arguments.get("role")
            if not isinstance(role, str) or not role:
                return _json_rpc_error(request_id, -32602, "Invalid recommend_packages arguments")
            return _json_rpc_result(request_id, _mcp_content_result(_recommend_packages_payload(role)))
```

- [x] **Step 6: `@mcp.tool()`-registrering** — lägg till i slutet av filen, efter `copy_template_to_valvet`:

```python
@mcp.tool()
def recommend_packages(role: str) -> dict[str, Any]:
    """Recommend prompt packages for a job role (see tools/call description above)."""
    logger.info("tool_call name=recommend_packages")
    return _recommend_packages_payload(role)
```

- [x] **Step 7: REST-endpoint** — lägg till efter `_api_vault_copy_template`:

```python
async def _api_recommend_packages(request: Request) -> JSONResponse:
    role = request.query_params.get("role", "")
    if not role:
        return JSONResponse(_error("INVALID_ARGUMENTS", "role query param is required"), status_code=400)
    return JSONResponse(_recommend_packages_payload(role))
```

Route (lägg till efter `/api/v1/vault/packages/copy`):

```python
            Route("/api/v1/vault/packages/recommendations", endpoint=_api_recommend_packages, methods=["GET"]),
```

- [x] **Step 8: `hosted_guard.py`** — lägg till `"recommend_packages"` i `allowed_methods` och `"recommend_packages": {"role"}` i `allowed_tool_args`, plus valideringsgren:

```python
        elif tool_name == "recommend_packages":
            role = arguments.get("role")
            if not isinstance(role, str) or not role:
                return {"reason": "invalid_role", "method": method, "tool": tool_name, "id": request_id}
```

- [x] **Step 9: Kompilera allt** — `python -m py_compile mcp-server/server/mcp_server.py mcp-server/server/hosted_guard.py mcp-server/server/package_recommendations.py` — OK.

- [x] **Step 10: Runtime-smoke-test lokalt** (utan Docker) — importera modulen och kör `recommend("chef", ...)`/`recommend("okänd-roll", ...)` direkt mot en liten testlista, bekräfta `role_recognized`-flaggan och `arbetsbank` alltid med när rollen känns igen.

- [x] **Step 11: Commit**

```powershell
git add mcp-server/server/package_recommendations.py mcp-server/server/mcp_server.py mcp-server/server/hosted_guard.py
git commit -m "feat: recommend_packages MCP tool for role-based package suggestions"
```

### Task 2: Deploy + verifiering

- [x] **Step 1:** Push till origin/main.
- [x] **Step 2:** VPS: `git pull --ff-only && docker-compose up -d --build` (ContainerConfig-workaround vid behov).
- [x] **Step 3:** `curl tools/call recommend_packages` med `role: "chef"` → `ledarskap`, `forandringsledning`, `beslutsberedning`, `arbetsbank`, `role_recognized: true`.
- [x] **Step 4:** Samma med `role: "okänd-roll-xyz"` → alla 7, `role_recognized: false`.
- [x] **Step 5:** Samma med `role: "KOMMUNIKATÖR"` (versaler) → matchar (bekräftar normalisering).
- [x] **Step 6:** Uppdatera minnesfilen `valvet-fas1-status` — hela visionen (6/6 delprojekt) klar.
