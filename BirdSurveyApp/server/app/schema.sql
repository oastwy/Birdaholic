CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES organizations(id),
  name TEXT NOT NULL,
  created_by_token_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS access_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL CHECK (role IN ('super_admin', 'org_admin', 'member')),
  organization_id UUID REFERENCES organizations(id),
  project_id UUID REFERENCES projects(id),
  revoked BOOLEAN NOT NULL DEFAULT false,
  expires_at TIMESTAMPTZ,
  created_by_token_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_members (
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  token_id UUID REFERENCES access_tokens(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (project_id, token_id)
);

CREATE TABLE IF NOT EXISTS survey_points (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  client_id TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  revision INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  UNIQUE(project_id, client_id)
);

CREATE TABLE IF NOT EXISTS survey_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  client_id TEXT NOT NULL,
  owner_token_id UUID REFERENCES access_tokens(id),
  owner_label TEXT NOT NULL DEFAULT '',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  revision INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  UNIQUE(project_id, client_id)
);

CREATE TABLE IF NOT EXISTS survey_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  session_id UUID REFERENCES survey_sessions(id) ON DELETE CASCADE,
  client_event_id TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(project_id, client_event_id)
);

CREATE TABLE IF NOT EXISTS field_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  client_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  revision INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(project_id, client_id)
);

CREATE TABLE IF NOT EXISTS invite_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  organization_id UUID REFERENCES organizations(id),
  label_prefix TEXT NOT NULL DEFAULT '',
  max_uses INTEGER,
  use_count INTEGER NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ,
  created_by_token_id UUID REFERENCES access_tokens(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  actor_token_id UUID REFERENCES access_tokens(id),
  target_type TEXT NOT NULL,
  target_id UUID,
  action TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  before_payload JSONB,
  after_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
