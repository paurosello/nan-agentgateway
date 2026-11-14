# nan-agentgateway

Standalone [agentgateway](https://agentgateway.dev) (OSS, Apache-2.0) packaged for
[NaN Cloud](https://nan.builders/docs/apps): one HTTP port, UI enabled, **SQLite
on the persistent volume** by default (Postgres optional, same image).

## What it runs

| | |
|---|---|
| Image | `cr.agentgateway.dev/agentgateway:v1.6.0` (binary copied into `wolfi-base`) |
| Port | `4000` — proxy, config API, and UI |
| UI | `https://<app-domain>/ui` |
| Storage | `hybrid` — baseline from `config/config.yaml`, UI/API writes in the database |
| Database | `DATABASE_URL`, default `sqlite:///data/agentgateway.db` |

There is no custom build step: the version is an `ARG`, and the same image works
with SQLite or Postgres — only the env var changes.

## Deploy on NaN Cloud

1. **Space → New App**, pick `paurosello/nan-agentgateway`, branch `main`,
   Dockerfile path `Dockerfile`.
2. Check **Expose over HTTP**, port **4000**.
3. In **Advanced options**:
   - **Persistent storage**: enable (NaN mounts it at `/data`).
   - **Replicas**: keep at **1** — SQLite must not be shared between pods.
   - Resources: `500m` / `512Mi` is plenty for a single gateway.
4. Environment variables: **none required**. The image defaults to
   `DATABASE_URL=sqlite:///data/agentgateway.db`.

Deploy, then open `https://<app-domain>/ui`.

### Why the entrypoint exists

The upstream image is Wolfi-based and distroless (no shell, runs as uid 65532).
NaN mounts persistent storage **root-owned** at `/data`, and SQLite then fails
with `unable to open database file (code: 14)`. So this image copies the same
binary into `wolfi-base`, starts as root, chowns the SQLite directory on the
volume, and `su-exec`s down to uid 65532 before starting the gateway. If the
container is started as non-root by the platform, that step is skipped.

Verified: root-owned `0755 /data` volume → gateway boots, creates
`/data/agentgateway.db*`, `/ui` returns `200`.

### Switching to Postgres

Same image, just override the env var and bump replicas if needed:

```
DATABASE_URL=postgres://USER:***@HOST:5432/DBNAME
```

The user needs `CREATE TABLE` rights — agentgateway creates its schema on first
start (analytics, logs, API keys, UI-managed config).

`db/` contains a plain PostgreSQL 17 image you can deploy as a **worker** app in
the same Space if you have no Postgres yet (`POSTGRES_PASSWORD`,
`POSTGRES_USER=agentgateway`, `POSTGRES_DB=agentgateway`, persistent storage
enabled — the cluster lives in `/data/pgdata`). Full mesh networking between NaN
apps is not guaranteed; SQLite avoids the question entirely.

## After the first start

The baseline config defines no LLM providers, models, MCP targets, or routes.
Add them in the UI (`/ui` → LLM / MCP). Because storage mode is `hybrid`, those
resources are written to the database, not the config file, so they survive
restarts and redeploys. They live in `/data/agentgateway.db` — back that file up
(or copy it out) before deleting the app.

## Upgrade agentgateway

Change the `ARG` in the `Dockerfile` and push:

```dockerfile
ARG AGENTGATEWAY_VERSION=v1.6.0
```

Check <https://github.com/agentgateway/agentgateway/releases> for the tag, then
redeploy the app in NaN. Resources stored in the database carry over.

## References

- `config/config.yaml` — baseline config (storage `hybrid`, DB URL from env, UI on 4000).
- `docker-entrypoint.sh` — /data ownership fix + privilege drop.
- `db/` — fallback PostgreSQL image (only needed if you prefer Postgres).
- `debug/` — connectivity probe app for in-Space DNS/TCP troubleshooting.
