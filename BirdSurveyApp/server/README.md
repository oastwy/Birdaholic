# BirdSurvey Token Sync Server

FastAPI + PostgreSQL backend for optional token-based collaboration sync.

## Deploy

```bash
cp .env.example .env
# edit POSTGRES_PASSWORD and BOOTSTRAP_SUPER_TOKEN
docker compose up -d --build
```

The bootstrap token is created as `super_admin` on startup. Use it in the app
or API calls as:

```bash
curl -H "Authorization: Bearer $BOOTSTRAP_SUPER_TOKEN" http://server:8000/me
```

## First Admin Flow

1. `POST /admin/organizations` with `{ "name": "机构名" }`.
2. `POST /projects` with `{ "organizationId": "...", "name": "项目名" }`.
3. `POST /admin/tokens` to create `org_admin` or `member` tokens.
4. Members fill server URL and token in the app settings.

All admin edits to records owned by another token are written to `audit_logs`.
