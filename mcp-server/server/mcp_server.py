from __future__ import annotations

from pathlib import Path
from typing import Any

from mcp.server.fastmcp import FastMCP

from .pro_templates import ProTemplatesNotConfigured, ProTemplatesClient
from .risk_checker import RiskChecker
from .skill_repository import SkillRepository
from .skill_router import SkillRouter


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


if __name__ == "__main__":
    mcp.run(transport="stdio")
