# nan-agentgateway

Standalone [agentgateway](https://agentgateway.dev) (OSS, Apache-2.0) packaged for
[NaN Cloud](https://nan.builders/docs/apps): one HTTP port, UI enabled, **SQLite
on the persistent volume** by default (Postgres optional, same image).

This repo doubles as a **template for one gateway per person**: every deployment
is independent — own URL, own UI, own volume, own credentials. If you are
deploying your own copy, follow [docs/self-service.md](docs/self-service.md)
instead of this file.

## What it runs

| | |
|---|---|
| Image | `cr.agentgateway.dev/agentgateway:v1.7.0` (binary copied into `wolfi-base`) |
| Port | `4000` — proxy, config API, and UI |
| UI | `https://<app-domain>/ui` |
| Storage | `hybrid` — baseline from `config/config.yaml`, UI/API writes in the database |
| Database | `DATABASE_URL`, default `sqlite:///data/agentgateway.db` |
| UI auth | **none by default** — enable `ui.policies` in Settings ([why](docs/self-service.md#2-lock-the-ui-first)) |

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
4. Environment variables: the image defaults to
   `DATABASE_URL=sqlite:///data/agentgateway.db`. Set `NAN_API_KEY` for the
   pre-configured `NaN` provider (boots cleanly if unset; recommended to add
   after locking auth, or lock both `/ui` and `/v1/*` immediately after deploy —
   see [docs/self-service.md](docs/self-service.md)).

Deploy, then open `https://<app-domain>/ui`.

> **Secure the UI and `/v1/*` before you share the URL.** The UI is the admin
> plane (it can read `/api/config` and rewrite the whole gateway config), and
> the pre-configured `NaN` provider / `*` model make `/v1/chat/completions` live
> as soon as `NAN_API_KEY` is set. See [Security model](#security-model).

### Give someone their own instance

Each person forks (or deploys directly) this repo into their own Space. Nothing
is shared, so nobody can read or change anybody else's configuration, and
forking lets each person customize the baseline provider/models in
`config/config.yaml`. Full walkthrough:
[docs/self-service.md](docs/self-service.md). Short version — **New App**,
repository your fork (or `paurosello/nan-agentgateway`), port `4000`, persistent
storage on, **1 replica**, resources `500m`/`512Mi`.

Prefer to keep one gateway and give people access without the UI? Mint virtual
API keys instead; see step 3 of the same guide.

### Why the entrypoint exists

The upstream runtime image is Chainguard's `glibc-dynamic` (Wolfi-based and
distroless: no shell, runs as uid 65532, binary at `/app/agentgateway`). NaN
mounts persistent storage **root-owned** at `/data`, and SQLite then fails
with `unable to open database file (code: 14)`. So this image copies the same
binary into `wolfi-base`, starts as root, chowns the SQLite directory on the
volume, and `su-exec`s down to uid 65532 before starting the gateway. If the
container is started as non-root by the platform, that step is skipped.

Verified: root-owned `0755 /data` volume → gateway boots, creates
`/data/agentgateway.db*`, `/ui` returns `200`.

## Security model

There are two planes and they use different policies:

| Plane | Paths | Policy | Notes |
|---|---|---|---|
| Admin | `/ui`, `/api/*` | `ui.policies` | Protects the UI **and** the config API it calls |
| Data | LLM (`/v1/*`), MCP (`/mcp`, `/sse`) | gateway / `llm.policies` / `mcp.policies` | What your users actually call |

The UI is a **full admin** in agentgateway OSS: an authenticated user can read
`/api/config` (including provider API keys), save any change, and remove the
auth policy. Fine-grained roles (`admin` / `viewer` / `self-service` presets)
are a Solo Enterprise feature and are not in the OSS schema (verified against
1.7.0). Practical consequences:

- **Lock the UI first.** Settings → UI → Basic auth (`mode: strict`) or OIDC.
  `./scripts/htpasswd.sh <user>` prints the line. Until then, anyone who
  finds the URL can rewrite the gateway, read logs, and send traffic.
- **Do not share the UI credential with end users.** Give them virtual API keys
  instead (LLM → Virtual API Keys → *Enable API key auth* → `Strict`), with
  per-key budgets, allowed models, and per-key usage reporting.
- **Keep `ui.policies` in the database.** A policy defined in
  `config/config.yaml` is file-owned, so the UI cannot edit it (`409 conflict`).
  The database copy is editable in the UI but has no shell-free recovery; the
  procedure is in [docs/self-service.md](docs/self-service.md).
- **`$` escaping depends on the plane.** Resources saved through the UI are
  stored verbatim with no environment expansion — paste `$2y$...` as-is. The
  config *file* is env-expanded — use `$$2y$$...` there.
- `config.adminAddr` (default `localhost:15000`) always bypasses `ui.policies`,
  but it is loopback-only and NaN exposes only port `4000`, so it is not
  reachable from the internet.

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

1. **Secure the UI** (Settings → UI) and **enable strict Virtual API Key auth**
   (LLM → Virtual API Keys → *Enable API key auth* → `Strict`). Both are
   required before sharing the URL or setting `NAN_API_KEY`; see
   [Security model](#security-model).
2. The baseline `config/config.yaml` pre-configures the `NaN` provider
   (`https://api.nan.builders/v1`, reading `NAN_API_KEY` at runtime) and the
   `NaN/*` and `*` models, so you can mint virtual API keys and start sending
   requests right away. Edit `config/config.yaml` in your fork to change those
   defaults, or add extra LLM providers/models, MCP targets, and routes in the
   UI (`/ui` → LLM / MCP). Because storage mode is `hybrid`, UI-managed
   resources are written to `/data/agentgateway.db` and survive restarts and
   redeploys — back that file up before deleting the app.
3. If you expect other people, decide between **their own instance**
   ([docs/self-service.md](docs/self-service.md)) and **virtual API keys**
   (LLM → Virtual API Keys). Sharing the UI credential gives away admin.

## Upgrade agentgateway

Change the `ARG` in the `Dockerfile` and push, then redeploy the app in NaN.
Resources stored in the database carry over **only if the app really mounts its
persistent volume** — verify with `Settings → UI` after the deploy: if the UI
stops asking for a password, the volume was replaced and the database is gone.
That is also what happens if the app was created without *Persistent storage*:
`/data` is then container-local and every redeploy starts from an empty
database.

Persistent storage is chosen in **Advanced options of the New App form**. The
post-creation settings panel edits branch, Dockerfile, port, and resources only,
so an app that was created without it has to be **recreated** to get one. Add it
to the new app, then recreate with the same app name in the same Space to keep
the same `<app>-<space>.apps.nan.builders` URL.

```dockerfile
ARG AGENTGATEWAY_VERSION=v1.7.0
```

Check <https://github.com/agentgateway/agentgateway/releases> for the tag. The
wrapper needs no changes: 1.7.0 keeps the binary at `/app/agentgateway` and
builds against the same glibc-dynamic runtime. The binary now requires
`GLIBC_2.39`, and `wolfi-base:latest` ships 2.44 — do not pin an older base.

### Upgrading 1.6 → 1.7

- **First start migrates the request-log database.** New analytics columns are
  added and backfilled. Quick on SQLite; on a large Postgres allow time and do
  not interrupt it.
- **MCP session IDs are now always encrypted.** The key is generated on first
  start and stored in the database (the `/etc` config is read-only), so there is
  nothing to configure. MCP sessions opened before the upgrade are rejected and
  clients start new ones. Set `config.session.key: disabled` only if you
  deliberately want unencrypted sessions.
- **Settings is a top-level page now**, and every form has a raw YAML mode that
  preserves fields the form does not model. UI edits no longer drop
  hand-written settings.
- **Prompt guards inspect tool output by default**, and error responses no
  longer include internal detail (check the logs instead). Neither affects this
  baseline config.

## References

- `config/config.yaml` — baseline config (storage `hybrid`, DB URL from env, UI on 4000).
- `docs/self-service.md` — deploying your own instance, enabling auth, and lockout recovery.
- `scripts/htpasswd.sh` — generates a Basic Auth line for the UI (and the escaped form for the file).
- `scripts/generate-config.sh` — one command for every copy-paste YAML block (auth policy, provider, model, full config).
- `docker-entrypoint.sh` — /data ownership fix + privilege drop.
- `db/` — fallback PostgreSQL image (only needed if you prefer Postgres).
- `debug/` — connectivity probe app for in-Space DNS/TCP troubleshooting.
