-- Runs once on the first boot (empty PGDATA).
-- The database and role themselves are created by the postgres image from
-- POSTGRES_DB / POSTGRES_USER / POSTGRES_PASSWORD.

-- gen_random_uuid() lives in core since PostgreSQL 13, but pgcrypto is cheap
-- insurance for extensions that expect it.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
