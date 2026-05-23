# BirdSurvey Sync Server Handoff

## Context

Project repo: `/Users/wuyang/Github/BirdSurveyApp`

Current pushed branch:
- Remote: `git@github.com:oastwy/Birdaholic.git`
- Branch: `codex/birdsurvey-1.4.0`
- Latest commit: `6d52293 Add token sync backend and survey naming`

Current app version:
- `1.5.0+20`
- APK: `/Users/wuyang/Github/BirdSurveyApp/release/BirdSurvey_1.5.0_20260523.apk`

Domain/server:
- Domain: `birding.today`
- A record: `124.223.101.188`
- HTTPS works
- nginx: `nginx/1.26.3`
- OS page indicates OpenCloudOS
- `https://birding.today/health` currently returns nginx 404, so backend is not deployed/reverse-proxied yet.

## What Was Implemented

### Flutter App

Files changed:
- `pubspec.yaml`
- `lib/models/survey_session.dart`
- `lib/services/database_service.dart`
- `lib/services/sync_service.dart`
- `lib/providers/survey_provider.dart`
- `lib/screens/settings_screen.dart`
- `lib/screens/survey_start_screen.dart`

Features:
- Settings page now has:
  - `服务器地址`
  - `同步 Token`
  - `验证 Token`
  - `立即同步`
- App stores sync config in `SharedPreferences`:
  - `sync_server_url`
  - `sync_token`
  - `sync_project_id`
- Added local cloud fields to `SurveySession`:
  - `cloudId`
  - `cloudProjectId`
  - `ownerTokenId`
  - `ownerUserLabel`
  - `revision`
  - `updatedAt`
  - `syncState`
- DB migration bumped to version `10`.
- Start survey page has a `调查名称` input.
- `SurveyProvider.startSurvey(..., title: ...)` stores `SurveySession.title`.
- Default title if empty:
  - selected site: `位点名 yyyy-MM-dd HH:mm`
  - transect: `样线调查 yyyy-MM-dd HH:mm`
  - point survey: `样点调查 yyyy-MM-dd HH:mm`

### Backend Scaffold

New folder:
- `server/`

Files:
- `server/docker-compose.yml`
- `server/Dockerfile`
- `server/.env.example`
- `server/requirements.txt`
- `server/README.md`
- `server/app/main.py`
- `server/app/auth.py`
- `server/app/db.py`
- `server/app/schema.sql`

Stack:
- FastAPI
- PostgreSQL
- Docker Compose
- WebSocket endpoint scaffold

Token roles:
- `super_admin`
- `org_admin`
- `member`

Main API:
- `GET /health`
- `GET /me`
- `POST /admin/organizations`
- `POST /admin/tokens`
- `POST /projects`
- `GET /projects`
- `GET /projects/{project_id}/sync`
- `POST /projects/{project_id}/sync`
- `GET /projects/{project_id}/members`
- `POST /projects/{project_id}/invite`
- `WS /projects/{project_id}/events`

DB tables:
- `organizations`
- `projects`
- `access_tokens`
- `project_members`
- `survey_points`
- `survey_sessions`
- `survey_events`
- `field_configs`
- `audit_logs`

Important behavior:
- Tokens are stored hashed with SHA-256.
- `BOOTSTRAP_SUPER_TOKEN` creates a `super_admin` token on startup.
- Members cannot edit other users' records.
- Admin edits of another token's record write `audit_logs`.
- App currently uploads local history/survey points/field config to first available cloud project.
- Full bidirectional merge UI is not done yet.

## Verification Already Done

Commands run:

```bash
/Users/wuyang/.flutter-sdk/bin/flutter test --no-pub
/Users/wuyang/.flutter-sdk/bin/flutter analyze --no-pub
/Users/wuyang/.flutter-sdk/bin/flutter build apk --release
python3 -m py_compile server/app/*.py
```

Results:
- Tests passed.
- Android release build passed.
- Python syntax compile passed.
- `flutter analyze --no-pub` exits with 4 existing info-level issues, not introduced by this task:
  - `lib/screens/survey_points_screen.dart:280`
  - `lib/screens/survey_points_screen.dart:281`
  - `lib/screens/survey_points_screen.dart:381`
  - `lib/services/weather_service.dart:33`

## Deployment Goal

Deploy the backend to the Tencent Cloud server behind `birding.today`.

Recommended route:
- Keep existing website at `/`
- Mount sync API under `/api/`
- App settings should use:

```text
https://birding.today/api
```

Nginx should reverse proxy:

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:8000/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

For WebSocket:

```nginx
location ~ ^/api/projects/.+/events$ {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
}
```

## Server Deployment Steps

On server:

```bash
cd /opt
git clone git@github.com:oastwy/Birdaholic.git birdsurvey
cd /opt/birdsurvey/BirdSurveyApp/server
cp .env.example .env
```

Edit `.env`:

```env
POSTGRES_DB=birdsurvey
POSTGRES_USER=birdsurvey
POSTGRES_PASSWORD=<strong-password>
DATABASE_URL=postgresql://birdsurvey:<strong-password>@db:5432/birdsurvey
BOOTSTRAP_SUPER_TOKEN=<long-random-token>
BOOTSTRAP_SUPER_LABEL=wuyang
CORS_ORIGINS=*
```

Start:

```bash
docker compose up -d --build
```

Smoke test locally on server:

```bash
curl http://127.0.0.1:8000/health
curl -H "Authorization: Bearer <BOOTSTRAP_SUPER_TOKEN>" http://127.0.0.1:8000/me
```

After nginx reverse proxy:

```bash
curl https://birding.today/api/health
curl -H "Authorization: Bearer <BOOTSTRAP_SUPER_TOKEN>" https://birding.today/api/me
```

## Initial API Setup

Create organization:

```bash
curl -X POST https://birding.today/api/admin/organizations \
  -H "Authorization: Bearer <SUPER_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name":"机构名称"}'
```

Create project:

```bash
curl -X POST https://birding.today/api/projects \
  -H "Authorization: Bearer <SUPER_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name":"项目名称","organizationId":"<ORG_ID>"}'
```

Create org admin token:

```bash
curl -X POST https://birding.today/api/admin/tokens \
  -H "Authorization: Bearer <SUPER_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"role":"org_admin","label":"老师/管理员","organizationId":"<ORG_ID>"}'
```

Create member token:

```bash
curl -X POST https://birding.today/api/admin/tokens \
  -H "Authorization: Bearer <SUPER_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"role":"member","label":"志愿者A","organizationId":"<ORG_ID>","projectId":"<PROJECT_ID>"}'
```

## Important Next Work

This is not yet complete real-time collaboration UX.

Needed next:
1. App must download remote survey sessions and show them in history/project records.
2. App must support admin opening another member's record, editing copy, saving back, and displaying audit history.
3. App should support selecting cloud project in Settings instead of silently using first project.
4. Add conflict handling:
   - local dirty vs newer cloud revision
   - admin overwrite with audit log
   - member own-record update
5. Add token management UI or simple admin web page.
6. Add server deployment hardening:
   - firewall
   - nginx config
   - HTTPS renewal check
   - PostgreSQL backup
   - server `.env` not committed
7. Add API tests for permissions:
   - super admin can manage all
   - org admin limited to org
   - member only own records
   - revoked token rejected

## Notes

Do not revert unrelated dirty files in repo. There were unrelated deleted old APKs and files outside `BirdSurveyApp`; they were intentionally not staged in commit `6d52293`.
