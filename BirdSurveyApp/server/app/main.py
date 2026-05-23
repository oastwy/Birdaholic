import os
import secrets
import string
from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import Depends, FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .auth import Principal, hash_token, new_token, require_admin, require_principal
from .db import connect, init_db


app = FastAPI(title="BirdSurvey Sync API")

origins = os.getenv("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class OrganizationIn(BaseModel):
    name: str


class ProjectIn(BaseModel):
    name: str
    organizationId: Optional[str] = None


class TokenIn(BaseModel):
    role: str = Field(pattern="^(super_admin|org_admin|member)$")
    label: str = ""
    organizationId: Optional[str] = None
    projectId: Optional[str] = None
    expiresAt: Optional[datetime] = None


class InviteIn(BaseModel):
    label: str = ""
    expiresAt: Optional[datetime] = None


class InviteCodeIn(BaseModel):
    projectId: str
    labelPrefix: str = ""
    maxUses: Optional[int] = None
    expiresAt: Optional[datetime] = None


class RedeemIn(BaseModel):
    code: str
    label: str = ""


class SyncItem(BaseModel):
    clientId: str
    payload: dict[str, Any]


class FieldConfigIn(SyncItem):
    kind: str


class SyncIn(BaseModel):
    surveySessions: list[SyncItem] = []
    surveyPoints: list[SyncItem] = []
    surveyEvents: list[SyncItem] = []
    fieldConfigs: list[FieldConfigIn] = []


connections: dict[str, list[WebSocket]] = {}


@app.on_event("startup")
def startup():
    init_db()
    token = os.getenv("BOOTSTRAP_SUPER_TOKEN", "").strip()
    if not token:
        return
    label = os.getenv("BOOTSTRAP_SUPER_LABEL", "super_admin")
    with connect() as conn:
        exists = conn.execute(
            "SELECT id FROM access_tokens WHERE token_hash = %s",
            (hash_token(token),),
        ).fetchone()
        if not exists:
            conn.execute(
                """
                INSERT INTO access_tokens(token_hash, label, role)
                VALUES (%s, %s, 'super_admin')
                """,
                (hash_token(token), label),
            )
            conn.commit()


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/me")
def me(principal: Principal = Depends(require_principal)):
    org_name = ""
    project_name = ""
    with connect() as conn:
        if principal.organization_id:
            row = conn.execute(
                "SELECT name FROM organizations WHERE id = %s",
                (principal.organization_id,),
            ).fetchone()
            org_name = row["name"] if row else ""
        if principal.project_id:
            row = conn.execute(
                "SELECT name FROM projects WHERE id = %s",
                (principal.project_id,),
            ).fetchone()
            project_name = row["name"] if row else ""
    return {
        "tokenId": principal.id,
        "role": principal.role,
        "label": principal.label,
        "organizationId": principal.organization_id or "",
        "organizationName": org_name,
        "projectId": principal.project_id or "",
        "projectName": project_name,
    }


@app.get("/admin/organizations")
def list_organizations(principal: Principal = Depends(require_admin)):
    with connect() as conn:
        if principal.role == "super_admin":
            rows = conn.execute(
                "SELECT id, name, created_at FROM organizations ORDER BY created_at DESC"
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT id, name, created_at FROM organizations WHERE id = %s",
                (principal.organization_id,),
            ).fetchall()
    return {
        "organizations": [
            {"id": str(r["id"]), "name": r["name"]} for r in rows
        ]
    }


@app.post("/admin/organizations")
def create_organization(
    data: OrganizationIn, principal: Principal = Depends(require_admin)
):
    if principal.role != "super_admin":
        raise HTTPException(status_code=403, detail="super_admin required")
    with connect() as conn:
        row = conn.execute(
            "INSERT INTO organizations(name) VALUES (%s) RETURNING id, name",
            (data.name,),
        ).fetchone()
        conn.commit()
    return {"id": str(row["id"]), "name": row["name"]}


@app.post("/projects")
def create_project(data: ProjectIn, principal: Principal = Depends(require_admin)):
    organization_id = data.organizationId or principal.organization_id
    if principal.role == "org_admin" and organization_id != principal.organization_id:
        raise HTTPException(status_code=403, detail="Cannot create outside organization")
    with connect() as conn:
        row = conn.execute(
            """
            INSERT INTO projects(organization_id, name, created_by_token_id)
            VALUES (%s, %s, %s)
            RETURNING id, organization_id, name
            """,
            (organization_id, data.name, principal.id),
        ).fetchone()
        conn.execute(
            """
            INSERT INTO project_members(project_id, token_id, role)
            VALUES (%s, %s, %s)
            ON CONFLICT DO NOTHING
            """,
            (row["id"], principal.id, principal.role),
        )
        conn.commit()
    return _project_json(row)


@app.get("/projects")
def list_projects(principal: Principal = Depends(require_principal)):
    with connect() as conn:
        if principal.role == "super_admin":
            rows = conn.execute(
                """
                SELECT p.id, p.organization_id, p.name, o.name AS organization_name
                FROM projects p LEFT JOIN organizations o ON o.id = p.organization_id
                ORDER BY p.created_at DESC
                """
            ).fetchall()
        elif principal.project_id:
            rows = conn.execute(
                """
                SELECT p.id, p.organization_id, p.name, o.name AS organization_name
                FROM projects p LEFT JOIN organizations o ON o.id = p.organization_id
                WHERE p.id = %s
                """,
                (principal.project_id,),
            ).fetchall()
        else:
            rows = conn.execute(
                """
                SELECT p.id, p.organization_id, p.name, o.name AS organization_name
                FROM projects p
                LEFT JOIN organizations o ON o.id = p.organization_id
                JOIN project_members m ON m.project_id = p.id
                WHERE m.token_id = %s OR p.organization_id = %s
                ORDER BY p.created_at DESC
                """,
                (principal.id, principal.organization_id),
            ).fetchall()
    return {"projects": [_project_json(r) for r in rows]}


@app.post("/admin/tokens")
def create_token(data: TokenIn, principal: Principal = Depends(require_admin)):
    if principal.role == "org_admin":
        if data.role == "super_admin":
            raise HTTPException(status_code=403, detail="Cannot create super_admin")
        if data.organizationId and data.organizationId != principal.organization_id:
            raise HTTPException(status_code=403, detail="Cannot create outside organization")
    raw = new_token()
    organization_id = data.organizationId or principal.organization_id
    with connect() as conn:
        row = conn.execute(
            """
            INSERT INTO access_tokens(
              token_hash, label, role, organization_id, project_id, expires_at,
              created_by_token_id
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING id, label, role, organization_id, project_id, expires_at
            """,
            (
                hash_token(raw),
                data.label,
                data.role,
                organization_id,
                data.projectId,
                data.expiresAt,
                principal.id,
            ),
        ).fetchone()
        if data.projectId:
            conn.execute(
                """
                INSERT INTO project_members(project_id, token_id, role)
                VALUES (%s, %s, %s)
                ON CONFLICT (project_id, token_id) DO UPDATE SET role = EXCLUDED.role
                """,
                (data.projectId, row["id"], data.role),
            )
        conn.commit()
    return {"token": raw, **_token_json(row)}


@app.get("/projects/{project_id}/members")
def project_members(project_id: str, principal: Principal = Depends(require_admin)):
    _ensure_project_access(project_id, principal, require_admin_role=True)
    with connect() as conn:
        rows = conn.execute(
            """
            SELECT t.id, t.label, t.role, t.organization_id, t.project_id,
                   t.revoked, t.expires_at, m.role AS project_role
            FROM project_members m
            JOIN access_tokens t ON t.id = m.token_id
            WHERE m.project_id = %s
            ORDER BY t.created_at DESC
            """,
            (project_id,),
        ).fetchall()
    return {"members": [_token_json(r) for r in rows]}


@app.post("/projects/{project_id}/invite")
def project_invite(
    project_id: str, data: InviteIn, principal: Principal = Depends(require_admin)
):
    _ensure_project_access(project_id, principal, require_admin_role=True)
    with connect() as conn:
        project = conn.execute(
            "SELECT organization_id FROM projects WHERE id = %s", (project_id,)
        ).fetchone()
    return create_token(
        TokenIn(
            role="member",
            label=data.label,
            organizationId=str(project["organization_id"]) if project else None,
            projectId=project_id,
            expiresAt=data.expiresAt,
        ),
        principal,
    )


@app.post("/admin/invite-codes")
def create_invite_code(
    data: InviteCodeIn, principal: Principal = Depends(require_admin)
):
    _ensure_project_access(data.projectId, principal, require_admin_role=True)
    with connect() as conn:
        project = conn.execute(
            "SELECT id, name, organization_id FROM projects WHERE id = %s",
            (data.projectId,),
        ).fetchone()
        if not project:
            raise HTTPException(status_code=404, detail="Project not found")
        for _ in range(10):
            code = "BIRD-" + "".join(
                secrets.choice(string.ascii_uppercase + string.digits) for _ in range(5)
            )
            exists = conn.execute(
                "SELECT id FROM invite_codes WHERE code = %s", (code,)
            ).fetchone()
            if not exists:
                break
        else:
            raise HTTPException(status_code=500, detail="Code generation failed")
        row = conn.execute(
            """
            INSERT INTO invite_codes(
              code, project_id, organization_id, label_prefix, max_uses,
              expires_at, created_by_token_id
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING id, code, project_id, max_uses, expires_at
            """,
            (
                code,
                data.projectId,
                str(project["organization_id"]) if project["organization_id"] else None,
                data.labelPrefix,
                data.maxUses,
                data.expiresAt,
                principal.id,
            ),
        ).fetchone()
        conn.commit()
    return {
        "code": row["code"],
        "projectId": str(row["project_id"]),
        "projectName": project["name"],
        "maxUses": row["max_uses"],
        "expiresAt": row["expires_at"].isoformat() if row["expires_at"] else None,
    }


@app.post("/invite/redeem")
def redeem_invite_code(data: RedeemIn):
    code = data.code.strip().upper()
    with connect() as conn:
        row = conn.execute(
            """
            SELECT ic.id, ic.project_id, ic.organization_id, ic.label_prefix,
                   ic.max_uses, ic.use_count, ic.expires_at,
                   p.name AS project_name
            FROM invite_codes ic
            JOIN projects p ON p.id = ic.project_id
            WHERE ic.code = %s
            """,
            (code,),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="邀请码无效")
        if row["expires_at"] and row["expires_at"] < datetime.now(timezone.utc):
            raise HTTPException(status_code=410, detail="邀请码已过期")
        if row["max_uses"] is not None and row["use_count"] >= row["max_uses"]:
            raise HTTPException(status_code=410, detail="邀请码已达到使用上限")
        label = data.label.strip() or (row["label_prefix"] + "成员")
        raw = new_token()
        token_row = conn.execute(
            """
            INSERT INTO access_tokens(
              token_hash, label, role, organization_id, project_id
            )
            VALUES (%s, %s, 'member', %s, %s)
            RETURNING id, label, role, organization_id, project_id
            """,
            (hash_token(raw), label, row["organization_id"], str(row["project_id"])),
        ).fetchone()
        conn.execute(
            """
            INSERT INTO project_members(project_id, token_id, role)
            VALUES (%s, %s, 'member')
            ON CONFLICT (project_id, token_id) DO NOTHING
            """,
            (str(row["project_id"]), token_row["id"]),
        )
        conn.execute(
            "UPDATE invite_codes SET use_count = use_count + 1 WHERE id = %s",
            (row["id"],),
        )
        conn.commit()
    return {
        "token": raw,
        "projectId": str(row["project_id"]),
        "projectName": row["project_name"],
        "organizationId": str(row["organization_id"]) if row["organization_id"] else "",
        "label": label,
    }


@app.get("/projects/{project_id}/sync")
def get_sync(
    project_id: str,
    since: Optional[datetime] = None,
    principal: Principal = Depends(require_principal),
):
    _ensure_project_access(project_id, principal)
    return _sync_payload(project_id, since)


@app.post("/projects/{project_id}/sync")
async def post_sync(
    project_id: str,
    data: SyncIn,
    since: Optional[datetime] = None,
    principal: Principal = Depends(require_principal),
):
    _ensure_project_access(project_id, principal)
    accepted = 0
    with connect() as conn:
        for point in data.surveyPoints:
            _upsert_simple(conn, "survey_points", project_id, point.clientId, point.payload)
            accepted += 1
        for config in data.fieldConfigs:
            _upsert_field_config(
                conn, project_id, config.clientId, config.kind, config.payload
            )
            accepted += 1
        for session in data.surveySessions:
            before = conn.execute(
                """
                SELECT id, owner_token_id, owner_label, payload
                FROM survey_sessions
                WHERE project_id = %s AND client_id = %s
                """,
                (project_id, session.clientId),
            ).fetchone()
            if before and str(before["owner_token_id"]) != principal.id and not principal.is_admin:
                raise HTTPException(status_code=403, detail="Cannot edit another member record")
            row = _upsert_session(conn, project_id, session.clientId, session.payload, principal)
            if before and str(before["owner_token_id"]) != principal.id:
                conn.execute(
                    """
                    INSERT INTO audit_logs(
                      project_id, actor_token_id, target_type, target_id, action,
                      summary, before_payload, after_payload
                    )
                    VALUES (%s, %s, 'survey_session', %s, 'admin_edit',
                            '管理员修改成员记录', %s, %s)
                    """,
                    (project_id, principal.id, row["id"], before["payload"], session.payload),
                )
            accepted += 1
        for event in data.surveyEvents:
            conn.execute(
                """
                INSERT INTO survey_events(project_id, client_event_id, payload)
                VALUES (%s, %s, %s)
                ON CONFLICT (project_id, client_event_id) DO NOTHING
                """,
                (project_id, event.clientId, event.payload),
            )
            accepted += 1
        conn.commit()
    await _broadcast(project_id, {"type": "sync", "accepted": accepted})
    payload = _sync_payload(project_id, since)
    payload["accepted"] = accepted
    payload["downloaded"] = len(payload["surveySessions"]) + len(payload["surveyPoints"])
    return payload


@app.websocket("/projects/{project_id}/events")
async def events_ws(websocket: WebSocket, project_id: str):
    await websocket.accept()
    connections.setdefault(project_id, []).append(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        connections[project_id].remove(websocket)


def _ensure_project_access(
    project_id: str, principal: Principal, require_admin_role: bool = False
):
    if require_admin_role and not principal.is_admin:
        raise HTTPException(status_code=403, detail="Admin token required")
    if principal.role == "super_admin":
        return
    with connect() as conn:
        row = conn.execute(
            """
            SELECT p.organization_id, m.role AS member_role
            FROM projects p
            LEFT JOIN project_members m ON m.project_id = p.id AND m.token_id = %s
            WHERE p.id = %s
            """,
            (principal.id, project_id),
        ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Project not found")
    if principal.project_id and principal.project_id != project_id:
        raise HTTPException(status_code=403, detail="Project not allowed")
    if principal.role == "org_admin" and str(row["organization_id"]) == principal.organization_id:
        return
    if row["member_role"]:
        return
    raise HTTPException(status_code=403, detail="Project not allowed")


def _upsert_simple(conn, table: str, project_id: str, client_id: str, payload: dict):
    conn.execute(
        f"""
        INSERT INTO {table}(project_id, client_id, payload)
        VALUES (%s, %s, %s)
        ON CONFLICT (project_id, client_id)
        DO UPDATE SET payload = EXCLUDED.payload,
                      revision = {table}.revision + 1,
                      updated_at = now()
        """,
        (project_id, client_id, payload),
    )


def _upsert_field_config(
    conn, project_id: str, client_id: str, kind: str, payload: dict
):
    conn.execute(
        """
        INSERT INTO field_configs(project_id, client_id, kind, payload)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (project_id, client_id)
        DO UPDATE SET kind = EXCLUDED.kind,
                      payload = EXCLUDED.payload,
                      revision = field_configs.revision + 1,
                      updated_at = now()
        """,
        (project_id, client_id, kind, payload),
    )


def _upsert_session(
    conn, project_id: str, client_id: str, payload: dict, principal: Principal
):
    return conn.execute(
        """
        INSERT INTO survey_sessions(
          project_id, client_id, owner_token_id, owner_label, payload
        )
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (project_id, client_id)
        DO UPDATE SET payload = EXCLUDED.payload,
                      revision = survey_sessions.revision + 1,
                      updated_at = now()
        RETURNING id, owner_token_id, owner_label, revision, updated_at
        """,
        (project_id, client_id, principal.id, principal.label, payload),
    ).fetchone()


def _sync_payload(project_id: str, since: Optional[datetime]):
    since_clause = "AND updated_at > %s" if since else ""
    params: tuple[Any, ...] = (project_id, since) if since else (project_id,)
    with connect() as conn:
        points = conn.execute(
            f"""
            SELECT id, client_id, payload, revision, updated_at
            FROM survey_points
            WHERE project_id = %s {since_clause}
            """,
            params,
        ).fetchall()
        sessions = conn.execute(
            f"""
            SELECT id, client_id, owner_token_id, owner_label, payload,
                   revision, updated_at
            FROM survey_sessions
            WHERE project_id = %s {since_clause}
            """,
            params,
        ).fetchall()
        configs = conn.execute(
            f"""
            SELECT id, client_id, kind, payload, revision, updated_at
            FROM field_configs
            WHERE project_id = %s {since_clause}
            """,
            params,
        ).fetchall()
    return {
        "surveyPoints": [_sync_item(r) for r in points],
        "surveySessions": [_sync_item(r) for r in sessions],
        "fieldConfigs": [_sync_item(r) for r in configs],
    }


def _sync_item(row: dict[str, Any]):
    return {
        "cloudId": str(row["id"]),
        "clientId": row["client_id"],
        "ownerTokenId": str(row.get("owner_token_id") or ""),
        "ownerUserLabel": row.get("owner_label") or "",
        "kind": row.get("kind") or "",
        "payload": row["payload"],
        "revision": row["revision"],
        "updatedAt": row["updated_at"].isoformat(),
    }


def _project_json(row: dict[str, Any]):
    return {
        "id": str(row["id"]),
        "organizationId": str(row["organization_id"] or ""),
        "organizationName": row.get("organization_name") or "",
        "name": row["name"],
    }


def _token_json(row: dict[str, Any]):
    return {
        "id": str(row["id"]),
        "label": row["label"],
        "role": row["role"],
        "organizationId": str(row["organization_id"] or ""),
        "projectId": str(row["project_id"] or ""),
        "revoked": row.get("revoked", False),
        "expiresAt": row["expires_at"].isoformat() if row.get("expires_at") else "",
    }


async def _broadcast(project_id: str, message: dict[str, Any]):
    for ws in list(connections.get(project_id, [])):
        try:
            await ws.send_json(message)
        except Exception:
            connections[project_id].remove(ws)
