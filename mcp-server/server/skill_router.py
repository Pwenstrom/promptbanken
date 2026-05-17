from __future__ import annotations

import re
from dataclasses import dataclass

from .skill_repository import Skill, SkillRepository


@dataclass(frozen=True)
class SkillMatch:
    skill: Skill
    score: int
    reasons: list[str]

    def to_dict(self) -> dict[str, object]:
        return {
            "skill": self.skill.to_dict(),
            "score": self.score,
            "reasons": self.reasons,
        }


class SkillRouter:
    def __init__(self, repository: SkillRepository) -> None:
        self.repository = repository

    def route(self, task: str, role: str | None = None, audience: str | None = None, limit: int = 3) -> list[SkillMatch]:
        terms = self._terms(task)
        matches = [self._score(skill, terms, role, audience) for skill in self.repository.list_skills()]
        ranked = sorted((match for match in matches if match.score > 0), key=lambda match: match.score, reverse=True)
        return ranked[:limit] if ranked else self._fallback(limit)

    def _score(self, skill: Skill, terms: set[str], role: str | None, audience: str | None) -> SkillMatch:
        score = 0
        reasons: list[str] = []
        searchable = self._terms(" ".join([skill.name, skill.description, *skill.intents]))
        overlap = terms & searchable
        if overlap:
            score += len(overlap) * 4
            reasons.append(f"Matchar uppgiftstermer: {', '.join(sorted(overlap)[:5])}")

        if role and self._normalize(role) in {self._normalize(item) for item in skill.roles}:
            score += 3
            reasons.append(f"Matchar roll: {role}")

        if audience and self._normalize(audience) in {self._normalize(item) for item in skill.audiences}:
            score += 2
            reasons.append(f"Matchar malgrupp: {audience}")

        return SkillMatch(skill=skill, score=score, reasons=reasons)

    def _fallback(self, limit: int) -> list[SkillMatch]:
        defaults = ["klarsprak", "sammanfattning", "mejl"]
        skills = []
        for skill_id in defaults[:limit]:
            try:
                skill = self.repository.get_skill(skill_id)
            except KeyError:
                continue
            skills.append(SkillMatch(skill=skill, score=0, reasons=["Fallback nar ingen tydlig match hittades."]))
        return skills

    @staticmethod
    def _terms(text: str) -> set[str]:
        return {SkillRouter._normalize(term) for term in re.findall(r"[\wåäöÅÄÖ]+", text.lower()) if len(term) > 2}

    @staticmethod
    def _normalize(text: str) -> str:
        return text.strip().lower().replace("å", "a").replace("ä", "a").replace("ö", "o")
