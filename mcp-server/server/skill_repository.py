from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Skill:
    id: str
    name: str
    description: str
    file: str
    intents: list[str]
    roles: list[str]
    audiences: list[str]
    risk_level: str
    requires_anonymization: bool
    output_type: str
    language: str
    version: str

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Skill":
        return cls(
            id=data["id"],
            name=data["name"],
            description=data["description"],
            file=data["file"],
            intents=list(data.get("intents", [])),
            roles=list(data.get("roles", [])),
            audiences=list(data.get("audiences", [])),
            risk_level=data.get("risk_level", "medium"),
            requires_anonymization=bool(data.get("requires_anonymization", True)),
            output_type=data.get("output_type", "text"),
            language=data.get("language", "sv-SE"),
            version=data.get("version", "1.0.0"),
        )

    def to_dict(self, include_prompt: bool = False, prompt: str | None = None) -> dict[str, Any]:
        result: dict[str, Any] = {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "intents": self.intents,
            "roles": self.roles,
            "audiences": self.audiences,
            "risk_level": self.risk_level,
            "requires_anonymization": self.requires_anonymization,
            "output_type": self.output_type,
            "language": self.language,
            "version": self.version,
        }
        if include_prompt:
            result["prompt"] = prompt or ""
        return result


class SkillRepository:
    def __init__(self, repo_root: Path) -> None:
        self.repo_root = repo_root
        self.config_path = repo_root / "skills.json"

    def list_skills(self) -> list[Skill]:
        data = json.loads(self.config_path.read_text(encoding="utf-8"))
        return [Skill.from_dict(skill) for skill in data.get("skills", [])]

    def get_skill(self, skill_id: str) -> Skill:
        match = next((skill for skill in self.list_skills() if skill.id == skill_id), None)
        if not match:
            raise KeyError(f"Skill '{skill_id}' was not found")
        return match

    def get_prompt(self, skill_id: str) -> str:
        skill = self.get_skill(skill_id)
        prompt_path = self.repo_root / skill.file
        if not prompt_path.exists():
            raise FileNotFoundError(f"Prompt file '{skill.file}' was not found")
        return prompt_path.read_text(encoding="utf-8").strip()
