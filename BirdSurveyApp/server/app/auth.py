import hashlib
import secrets
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from fastapi import Depends, Header, HTTPException

from .db import connect


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def new_token() -> str:
    return secrets.token_urlsafe(32)


@dataclass
class Principal:
    id: str
    role: str
    label: str
    organization_id: Optional[str]
    project_id: Optional[str]

    @property
    def is_admin(self) -> bool:
        return self.role in {"super_admin", "org_admin"}


def require_principal(authorization: str = Header(default="")) -> Principal:
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    with connect() as conn:
        row = conn.execute(
            """
            SELECT id, role, label, organization_id, project_id, revoked, expires_at
            FROM access_tokens
            WHERE token_hash = %s
            """,
            (hash_token(token),),
        ).fetchone()
    if not row or row["revoked"]:
        raise HTTPException(status_code=401, detail="Invalid or revoked token")
    expires_at = row["expires_at"]
    if expires_at and expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=401, detail="Token expired")
    return Principal(
        id=str(row["id"]),
        role=row["role"],
        label=row["label"] or "",
        organization_id=str(row["organization_id"]) if row["organization_id"] else None,
        project_id=str(row["project_id"]) if row["project_id"] else None,
    )


def require_admin(principal: Principal = Depends(require_principal)) -> Principal:
    if not principal.is_admin:
        raise HTTPException(status_code=403, detail="Admin token required")
    return principal
