from __future__ import annotations

from pathlib import Path
from typing import Any

from mcp.server.fastmcp import FastMCP

from .pro_templates import ProTemplatesNotConfigured, ProTemplatesClient
from .risk_checker import RiskChecker
from .skill_repository import SkillRepository
from .skill_router import SkillRouter
from . import catalog as _catalog
from .catalog_renderer import render_variant_fields


repo_root = Path(__file__).resolve().parents[1]
repository = SkillRepository(repo_root=repo_root)
router = SkillRouter(repository=repository)
risk_checker = RiskChecker()

mcp = FastMCP("promptbanken-skill-router")


@mcp.tool()
def list_skills() -> list[dict[str, Any]]:
    """List all Promptbanken skills with metadata, excluding full prompt text."""
    return [skill.to_dict() for skill in repository.list_skills()]


@mcp.tool()
def get_skill(skill_id: str, include_prompt: bool = True) -> dict[str, Any]:
    """Get one skill by id, optionally including the full prompt text."""
    skill = repository.get_skill(skill_id)
    prompt = repository.get_prompt(skill_id) if include_prompt else None
    return skill.to_dict(include_prompt=include_prompt, prompt=prompt)


@mcp.tool()
def route_skill(task: str, role: str | None = None, audience: str | None = None) -> dict[str, Any]:
    """Route a user task to the most relevant Promptbanken skill."""
    matches = router.route(task=task, role=role, audience=audience)
    return {
        "recommended": matches[0].to_dict() if matches else None,
        "alternatives": [match.to_dict() for match in matches[1:]],
    }


@mcp.tool()
def compile_skill_prompt(skill_id: str, user_task: str = "", user_input: str = "") -> dict[str, Any]:
    """Return a ready-to-use prompt assembled from a skill and optional user context."""
    skill = repository.get_skill(skill_id)
    prompt = repository.get_prompt(skill_id)
    risk = risk_checker.check(user_input or user_task)
    compiled = prompt
    if user_task:
        compiled += f"\n\nUppgift:\n{user_task.strip()}"
    if user_input:
        compiled += f"\n\nIndata:\n{user_input.strip()}"
    return {
        "skill": skill.to_dict(),
        "compiled_prompt": compiled,
        "risk_check": risk.to_dict(),
    }


@mcp.tool()
def check_input_risk(text: str) -> dict[str, object]:
    """Check text for common personal-data patterns before using a prompt."""
    return risk_checker.check(text).to_dict()


@mcp.tool()
def list_pro_templates() -> dict[str, Any]:
    """List the full Promptbanken template library (name kept for backwards
    compatibility -- the catalog is open since 2026-07-19, no Pro plan
    required; full prompt text is always included)."""
    try:
        client = ProTemplatesClient.from_env()
    except ProTemplatesNotConfigured as exc:
        return {"error": str(exc), "templates": []}

    templates = client.list_templates()
    return {
        "unlocked": bool(templates) and all(t.get("is_unlocked") for t in templates),
        "templates": templates,
    }


@mcp.tool()
def list_my_private_prompts() -> dict[str, Any]:
    """List the caller's own private Pro prompts (personal workspace) via
    PROMPTBANKEN_MCP_KEY. Never returns other members' private prompts or
    organization prompts."""
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


@mcp.tool()
def list_prompts(context_keys: list[str] | None = None) -> dict[str, Any]:
    """List all published catalog prompts. Pass one or more context_keys
    (e.g. ["kommun", "skola"]) to combine profiles; each prompt appears once,
    using the first matching profile's copy, falling back to 'generell'."""
    try:
        return {
            "prompts": _catalog.list_published_prompts(context_keys=context_keys)
        }
    except _catalog.CatalogNotConfigured as exc:
        return {"error": str(exc), "prompts": []}


def _render_bindings(
    context_keys: list[str] | None = None,
    role: str | None = None,
    audience: str | None = None,
    tone: str | None = None,
    input_text: str | None = None,
) -> dict[str, Any]:
    bindings: dict[str, Any] = {}
    if context_keys:
        bindings["kontext"] = context_keys[0]
    if role:
        bindings["roll"] = role
    if audience:
        bindings["malgrupp"] = audience
    if tone:
        bindings["ton"] = tone
    if input_text is not None:
        bindings["input"] = input_text
    return bindings


def _render_variants(
    variants: list[dict[str, Any]],
    context_keys: list[str] | None = None,
    role: str | None = None,
    audience: str | None = None,
    tone: str | None = None,
    input_text: str | None = None,
) -> list[dict[str, Any]]:
    bindings = _render_bindings(context_keys, role, audience, tone, input_text)
    return [render_variant_fields(variant, bindings) for variant in variants]


@mcp.tool()
def get_prompt(
    slug: str,
    context_keys: list[str] | None = None,
    role: str | None = None,
    audience: str | None = None,
    tone: str | None = None,
    input_text: str | None = None,
) -> dict[str, Any]:
    """Get one published catalog prompt by slug. Returns one entry per
    matching context_key (in the order passed) plus a guaranteed 'generell'
    entry. Optional role, audience, tone and input_text are used to add
    rendered_prompt_text with resolved template parameters."""
    try:
        variants = _catalog.get_published_prompt(slug, context_keys=context_keys)
    except _catalog.CatalogNotConfigured as exc:
        return {"error": str(exc)}
    if not variants:
        return {"error": f"Ingen publicerad prompt hittades med slug '{slug}'."}
    return {
        "variants": _render_variants(
            variants, context_keys, role, audience, tone, input_text
        )
    }


@mcp.tool()
def list_packages(
    context_keys: list[str] | None = None, package_type: str | None = None
) -> dict[str, Any]:
    """List all published catalog packages/workflows, combining profiles the
    same way as list_prompts."""
    try:
        return {
            "packages": _catalog.list_published_packages(
                context_keys=context_keys, package_type=package_type
            )
        }
    except _catalog.CatalogNotConfigured as exc:
        return {"error": str(exc), "packages": []}


@mcp.tool()
def get_package(
    slug: str,
    context_keys: list[str] | None = None,
    role: str | None = None,
    audience: str | None = None,
    tone: str | None = None,
    input_text: str | None = None,
) -> dict[str, Any]:
    """Get one published catalog package by slug. Returns one entry per
    matching context_key plus a guaranteed 'generell' entry. Optional role,
    audience, tone and input_text add rendered_intro_text when applicable."""
    try:
        variants = _catalog.get_published_package(slug, context_keys=context_keys)
    except _catalog.CatalogNotConfigured as exc:
        return {"error": str(exc)}
    if not variants:
        return {"error": f"Inget publicerat paket hittades med slug '{slug}'."}
    return {
        "variants": _render_variants(
            variants, context_keys, role, audience, tone, input_text
        )
    }


@mcp.tool()
def list_package_prompts(
    package_slug: str,
    context_keys: list[str] | None = None,
    role: str | None = None,
    audience: str | None = None,
    tone: str | None = None,
    input_text: str | None = None,
) -> dict[str, Any]:
    """List the published prompts belonging to one published package, in
    sort order, combining profiles the same way as list_prompts. Optional
    role, audience, tone and input_text add rendered_prompt_text."""
    try:
        prompts = _catalog.list_published_package_prompts(
            package_slug, context_keys=context_keys
        )
        return {
            "prompts": _render_variants(
                prompts, context_keys, role, audience, tone, input_text
            )
        }
    except _catalog.CatalogNotConfigured as exc:
        return {"error": str(exc), "prompts": []}


if __name__ == "__main__":
    mcp.run(transport="stdio")
