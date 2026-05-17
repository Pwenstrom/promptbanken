from __future__ import annotations

from pathlib import Path
from typing import Any

from mcp.server.fastmcp import FastMCP

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


if __name__ == "__main__":
    mcp.run(transport="stdio")
