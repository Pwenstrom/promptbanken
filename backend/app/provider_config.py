from __future__ import annotations

import base64
import hashlib
import os
import sqlite3
from dataclasses import dataclass
from pathlib import Path

from cryptography.fernet import Fernet


@dataclass(slots=True)
class ProviderRuntimeConfig:
    name: str
    enabled: bool
    api_key: str | None
    base_url: str


class SecretStore:
    """Server-side encrypted storage for provider API keys."""

    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._fernet = Fernet(self._build_encryption_key())
        self._ensure_schema()

    def _build_encryption_key(self) -> bytes:
        configured_key = os.getenv("PROVIDER_ENCRYPTION_KEY")
        if configured_key:
            return configured_key.encode("utf-8")

        # MVP fallback: derive key from admin token so encryption-at-rest always exists,
        # but rotate carefully because old data cannot be decrypted after token changes.
        key_material = os.getenv("PROVIDER_ENCRYPTION_KEY") or os.getenv("ADMIN_PANEL_TOKEN")
        if not key_material:
            raise RuntimeError("PROVIDER_ENCRYPTION_KEY eller ADMIN_PANEL_TOKEN måste vara satt.")
        digest = hashlib.sha256(key_material.encode("utf-8")).digest()
        return base64.urlsafe_b64encode(digest)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS provider_configs (
                    provider TEXT PRIMARY KEY,
                    enabled INTEGER NOT NULL DEFAULT 0,
                    base_url TEXT,
                    encrypted_api_key TEXT,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            )

    def get_config(self, provider: str) -> dict[str, str | int | None] | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT provider, enabled, base_url, encrypted_api_key FROM provider_configs WHERE provider = ?",
                (provider,),
            ).fetchone()

        if not row:
            return None

        return {
            "provider": row["provider"],
            "enabled": row["enabled"],
            "base_url": row["base_url"],
            "encrypted_api_key": row["encrypted_api_key"],
        }

    def upsert_config(
        self,
        provider: str,
        *,
        enabled: bool | None = None,
        base_url: str | None = None,
        api_key: str | None = None,
    ) -> None:
        current = self.get_config(provider)
        next_enabled = bool(current["enabled"]) if current else False
        next_base_url = current["base_url"] if current else None
        next_encrypted_key = current["encrypted_api_key"] if current else None

        if enabled is not None:
            next_enabled = enabled
        if base_url is not None:
            next_base_url = base_url
        if api_key is not None:
            next_encrypted_key = self._fernet.encrypt(api_key.encode("utf-8")).decode("utf-8")

        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO provider_configs(provider, enabled, base_url, encrypted_api_key, updated_at)
                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(provider) DO UPDATE SET
                    enabled = excluded.enabled,
                    base_url = excluded.base_url,
                    encrypted_api_key = excluded.encrypted_api_key,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (provider, int(next_enabled), next_base_url, next_encrypted_key),
            )

    def decrypt_api_key(self, encrypted_api_key: str | None) -> str | None:
        if not encrypted_api_key:
            return None
        return self._fernet.decrypt(encrypted_api_key.encode("utf-8")).decode("utf-8")


class ProviderConfigService:
    def __init__(self, db_path: Path) -> None:
        self.secret_store = SecretStore(db_path=db_path)

    def get_openai_runtime_config(self) -> ProviderRuntimeConfig:
        stored = self.secret_store.get_config("openai")
        env_key = os.getenv("OPENAI_API_KEY")
        env_base_url = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")

        if not stored:
            return ProviderRuntimeConfig(
                name="openai",
                enabled=bool(env_key),
                api_key=env_key,
                base_url=env_base_url,
            )

        stored_key = self.secret_store.decrypt_api_key(stored["encrypted_api_key"])
        return ProviderRuntimeConfig(
            name="openai",
            enabled=bool(stored["enabled"]),
            api_key=stored_key,
            base_url=(stored["base_url"] or env_base_url),
        )

    def list_provider_status(self) -> list[dict[str, str | bool | None]]:
        openai = self.get_openai_runtime_config()
        masked_suffix = None
        if openai.api_key and len(openai.api_key) >= 4:
            masked_suffix = f"***{openai.api_key[-4:]}"

        return [
            {
                "name": openai.name,
                "enabled": openai.enabled,
                "configured": bool(openai.api_key),
                "masked_key": masked_suffix,
                "base_url": openai.base_url,
            }
        ]

    def update_openai_config(self, *, enabled: bool | None, api_key: str | None, base_url: str | None) -> None:
        self.secret_store.upsert_config("openai", enabled=enabled, api_key=api_key, base_url=base_url)
