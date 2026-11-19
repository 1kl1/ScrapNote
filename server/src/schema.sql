CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY, email text NOT NULL UNIQUE, password_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), last_sign_in_at timestamptz
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash text PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_owner ON sessions(user_id);
CREATE TABLE IF NOT EXISTS vault_manifests (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  revision integer NOT NULL DEFAULT 0 CHECK (revision >= 0),
  entries jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(entries)='object'),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS vault_blobs (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  digest text NOT NULL CHECK (digest ~ '^[a-f0-9]{64}$'),
  size integer NOT NULL CHECK (size >= 0 AND size <= 26214400),
  content bytea, zipline_id text, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, digest),
  CHECK ((content IS NOT NULL AND zipline_id IS NULL) OR (content IS NULL AND zipline_id IS NOT NULL))
);
