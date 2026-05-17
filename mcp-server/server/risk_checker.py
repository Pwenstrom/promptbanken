from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class RiskCheck:
    allowed: bool
    warnings: list[str]
    recommended_action: str

    def to_dict(self) -> dict[str, object]:
        return {
            "allowed": self.allowed,
            "warnings": self.warnings,
            "recommended_action": self.recommended_action,
        }


class RiskChecker:
    PATTERNS = {
        "personnummer": re.compile(r"\b(?:\d{6}|\d{8})[-+]?\d{4}\b"),
        "e-postadress": re.compile(r"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b"),
        "telefonnummer": re.compile(r"\b(?:\+46|0)\s?(?:\d[\s-]?){7,12}\b"),
        "arendenummer": re.compile(r"\b(?:dnr|diarie|arende|ärende)[\s:.-]*[A-Za-z0-9/-]{3,}\b", re.IGNORECASE),
    }

    def check(self, text: str) -> RiskCheck:
        warnings = [
            f"Texten verkar innehalla {label}."
            for label, pattern in self.PATTERNS.items()
            if pattern.search(text)
        ]
        return RiskCheck(
            allowed=True,
            warnings=warnings,
            recommended_action=(
                "Anonymisera eller generalisera markerade uppgifter innan prompten anvands."
                if warnings
                else "Ingen tydlig personuppgiftsrisk hittades med enkel regelkontroll."
            ),
        )
