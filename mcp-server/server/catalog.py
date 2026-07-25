from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any


class CatalogNotConfigured(Exception):
    """Raised when SUPABASE_URL/SUPABASE_ANON_KEY are missing."""


def _supabase_config() -> tuple[str, str]:
    supabase_url = os.getenv("SUPABASE_URL", "").rstrip("/")
    supabase_anon_key = os.getenv("SUPABASE_ANON_KEY", "")

    if not supabase_url or not supabase_anon_key:
        raise CatalogNotConfigured(
            "SUPABASE_URL och SUPABASE_ANON_KEY måste vara satta som miljövariabler "
            "för att läsa den publicerade katalogen. Katalogläsningen är öppen -- "
            "ingen MCP-nyckel krävs."
        )

    return supabase_url, supabase_anon_key


def _call_rpc(function_name: str, payload: dict[str, Any]) -> Any:
    supabase_url, supabase_anon_key = _supabase_config()
    url = f"{supabase_url}/rest/v1/rpc/{function_name}"
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "apikey": supabase_anon_key,
            "Authorization": f"Bearer {supabase_anon_key}",
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


def list_published_prompts(context_key: str = "generell") -> list[dict[str, Any]]:
    return _call_rpc("list_published_prompts", {"p_context_key": context_key})


def get_published_prompt(slug: str, context_key: str = "generell") -> dict[str, Any] | None:
    rows = _call_rpc("get_published_prompt", {"p_slug": slug, "p_context_key": context_key})
    return rows[0] if rows else None


def list_published_packages(
    context_key: str = "generell", package_type: str | None = None
) -> list[dict[str, Any]]:
    return _call_rpc(
        "list_published_packages",
        {"p_context_key": context_key, "p_package_type": package_type},
    )


def get_published_package(slug: str, context_key: str = "generell") -> dict[str, Any] | None:
    rows = _call_rpc("get_published_package", {"p_slug": slug, "p_context_key": context_key})
    return rows[0] if rows else None


def list_published_package_prompts(
    package_slug: str, context_key: str = "generell"
) -> list[dict[str, Any]]:
    return _call_rpc(
        "list_published_package_prompts",
        {"p_package_slug": package_slug, "p_context_key": context_key},
    )
