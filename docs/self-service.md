# Deploy your own gateway

This repository is a template for **one gateway per person**. Each deployment
gets its own public URL, its own UI, its own SQLite database on its own volume,
and its own credentials. Nothing is shared between deployments, so you can
change anything you like without affecting anyone else.

If you only need an API key for someone else's gateway, you do not need this
guide — ask them for a virtual key.

- [1. Deploy](#1-deploy)
- [2. Lock the UI first](#2-lock-the-ui-first)
- [3. Enable virtual API keys (and invite people)](#3-enable-virtual-api-keys-and-invite-people)
- [Pre-configured provider and models](#pre-configured-provider-and-models)
- [Backups, upgrades, and recovery](#backups-upgrades-and-recovery)

## 1. Deploy

Fork `paurosello/nan-agentgateway` if you want to customize the default provider
or models in `config/config.yaml` (or deploy it directly as-is). In
[NaN Cloud](https://cloud.nan.builders/spaces), open or create a Space, then
**New App**:

| Field | Value |
|---|---|
| Repository | your fork of `paurosello/nan-agentgateway` (or `paurosello/nan-agentgateway` directly; authorize it for the NaN GitHub App) |
| Branch | `main` |
| Dockerfile | `Dockerfile` |
| App name | anything, e.g. `my-gateway` (it becomes part of the URL) |
| Expose over HTTP | on, port **4000** |
| Persistent storage | **on** (required; NaN mounts it at `/data`) |
| Replicas | **1** (SQLite must not be shared) |
| Resources | `500m` / `512Mi` is enough |
| Environment | `NAN_API_KEY` = your NaN API key (recommended to add **after** locking auth in steps 2–3, or lock both immediately after deploy) |

Wait for `Running`, then open:

```
https://<app>-<space>.apps.nan.builders/ui
```

> **Lock auth before (or right after) setting `NAN_API_KEY`.** The `NaN`
> provider and `NaN/*` / `*` models are pre-configured in `config/config.yaml`,
> so as soon as `NAN_API_KEY` is set, `/v1/chat/completions` is live. Enable
> both UI auth (step 2) and strict Virtual API Key auth (step 3) before sharing
> the URL — or deploy without `NAN_API_KEY` first, enable both policies, and
> add `NAN_API_KEY` afterward.

> **Storage is a creation-time choice.** Persistent storage can only be chosen
> in the New App form. The app settings panel edits branch, Dockerfile, port, and
> resources, not storage. If you deployed without it, delete the app and create
> it again with the same name in the same Space — the URL stays the same — then
> re-add your configuration.

## 2. Lock the UI first

The UI is the **admin plane**. It can read and rewrite the entire gateway
configuration, including provider API keys, and it can turn authentication off
again. Until you add an auth policy, anyone who finds the URL is a full admin.
The home page shows a matching warning banner.

Generate a credential line:

```sh
./scripts/generate-config.sh            # everything below, hashed and filled in
./scripts/htpasswd.sh alice             # only the credential line
```

`generate-config.sh` prompts for the password and prints copy-paste blocks for
this policy (plus optional provider/model and full config-file templates) —
already in the form each editor expects. Then in the UI: **Settings → UI → UI
access policies → Basic auth** (the home page banner's *Configure UI
policies* button links to the same page):

![Settings UI access policies](images/ui-auth.png)

| Field | Value |
|---|---|
| `mode` | `Strict` — `Optional` still lets anonymous requests through |
| `realm` | anything, e.g. `my-gateway` |
| `htpasswd` | the `alice:$2y$...` lines, one per user |

Save, then verify from a terminal:

```sh
H=https://<app>-<space>.apps.nan.builders
curl -s -o /dev/null -w 'ui      %{http_code}\n' $H/ui                    # 401
curl -s -o /dev/null -w 'api     %{http_code}\n' $H/api/config            # 401
curl -s -o /dev/null -w 'with pw %{http_code}\n' -u alice:'<pw>' $H/ui    # 200
```

The policy is stored in the database (`ui.policy`), so it survives restarts and
redeploys. Paste the line **exactly as generated**: resources saved through the
UI are never environment-expanded, so `$2y$...` stays as-is. Only the config
*file* needs `$$` escaping — and getting that wrong is loud, not silent: a raw
`$2y$...` in `config/config.yaml` stops the gateway from starting with
`error looking key '2y' up: environment variable not found`.

Prefer single sign-on? The same page offers OIDC (`oidc`), JWT, and external
authorization. OIDC needs an OIDC-capable provider (Google, Okta, Auth0,
Keycloak — GitHub is OAuth2 only) plus a client ID/secret and an absolute
callback URL on your app's host. On 1.7, set `credentials: sessionOrBearer` so
the same policy also accepts bearer ID tokens from CLI clients.

## 3. Enable virtual API keys (and invite people)

The `NaN` provider and `NaN/*` / `*` models are already pre-configured in
`config/config.yaml`, so you do not need to add them in the UI. Lock down
`/v1/*` and mint keys for yourself or other people:

**LLM → Virtual API Keys → Enable API key auth → `Strict` → New key**

Per key you can set:

- a name and `metadata` (e.g. `user: alice`),
- a rolling **budget** (tokens or USD) that blocks with `429`,
- **allowed models**, so a key can only call what it should,
- the key value itself, or let the UI generate one.

If you did not set `NAN_API_KEY` at deploy time, add it to the app's environment
variables now and redeploy. Anyone with the UI credential can change your config
and remove your auth policy, so never share the UI password — hand out virtual
keys instead.

Keys are stored hashed, usage and cost are attributed per key in
**Analytics / Logs**, and revoking one key does not touch anyone else. Clients
can send either bare model names (`*`) or `NaN/<model>` (`NaN/*`):

```sh
curl https://<app>-<space>.apps.nan.builders/v1/chat/completions \
  -H "Authorization: Bearer vk-alice-..." \
  -H "content-type: application/json" \
  -d '{"model":"<model>","messages":[{"role":"user","content":"hi"}]}'
```

Note that the gateway-level `apiKey` policy applies to the LLM and MCP traffic
on the gateway, not to `/ui` and `/api`; those are covered by `ui.policies` from
step 2. Keep both on.

## Pre-configured provider and models

`config/config.yaml` ships with:

- **Provider `NaN`**: `custom` (`completions` and `embeddings` formats —
  agentgateway also translates Anthropic `/v1/messages` and OpenAI
  `/v1/responses` to `completions` automatically), `baseUrl: https://api.nan.builders/v1`,
  and `apiKey: "${NAN_API_KEY}"`. The image defaults `NAN_API_KEY=""` so the
  gateway still boots when it is unset, and `/api/config` returns the
  unexpanded `${NAN_API_KEY}` reference rather than the raw secret.
- **Discovered models**: on startup, when `NAN_API_KEY` is set,
  `docker-entrypoint.sh` queries `https://api.nan.builders/v1/models` and
  injects every chat/embedding model available to your key into `llm.models[]`
  (filtering out audio/TTS/STT entries like `whisper` so they do not clutter
  chat pickers) so they appear in `GET /v1/models`, `GET /models`, the UI
  Playground, and Virtual API Key allowed-models pickers. Redeploy/restart to
  refresh after NaN adds new models. Set `NAN_DISCOVER_MODELS=false` to disable
  (or `NAN_MODELS_URL` to override the URL). Any fetch failure falls back
  cleanly to `NaN/*` and `*`.
- **Model `NaN/*`**: strips the `NaN/` prefix and forwards to `NaN`.
- **Model `*`**: catch-all that forwards bare model names straight to `NaN`
  (including newly added models before the next restart).
- **Credit cost catalog** (`config/model-catalog.json`): maps NaN's per-1M-token
  credit rates (`input`, `cacheRead`, `output`, `cacheWrite`) at **1 credit = $1**,
  so Analytics costs and Virtual API Key USD budgets map directly to your NaN
  credit pool (e.g. a `$500` key budget caps that key at 500 credits out of
  7,000). Edit `config/model-catalog.json` in your fork if NaN updates rates.
- **Non-`/v1` path rewrites**: internally rewrites `/chat/completions`,
  `/responses`, `/messages`, and `/embeddings` to `/v1/...` so clients whose
  base URL omits `/v1` still record full Analytics, tokens, and budgets instead
  of falling back to passthrough.

Because these live in `config/config.yaml`, they are **file-owned** (read-only
in the UI):

- To change or remove the defaults (for example, drop `*` or point at a
  different upstream), edit `config/config.yaml` in your fork and redeploy.
- To add **extra** providers or models alongside `NaN`, add them in the UI
  (**LLM → Providers / Models**); hybrid mode merges DB resources over the file
  baseline, and more specific model patterns take precedence over `*`.
- Upgrading an existing instance that already added `NaN` or `NaN/*` in SQLite?
  Delete the DB copies before redeploying so they do not collide with the
  file-owned entries.

`baseUrl` must end in `/v1`. Provider endpoint paths are appended to it, so
`https://api.nan.builders` becomes `https://api.nan.builders/chat/completions`
(which NaN answers with `404 Not found.`), while
`https://api.nan.builders/v1` becomes the correct `/v1/chat/completions`.

Telling the failures apart:

| Response | Cause |
|---|---|
| `404 Model not found` with `code: model_not_found` | No `llm.models` entry matches |
| `404 Not found.` from upstream | `baseUrl` is missing `/v1` |
| `401 Invalid API key.` from upstream | `NAN_API_KEY` is unset or empty, so `params.apiKey` expands to nothing |
| `401 authentication failed` | The gateway rejected the client key: not a valid virtual key, or `apiKey` is `strict` and no key was sent |

## Backups, upgrades, and recovery

- **State** lives in `/data/agentgateway.db*` on the persistent volume. That
  includes everything you created in the UI: extra providers/models, virtual
  keys, routes, MCP targets, and the auth policies. Back the volume up before
  deleting the app. If the UI stops asking for a password after a redeploy, the
  app is not mounting its volume — check **Advanced options → Persistent
  storage** in NaN; without it `/data` is container-local and every redeploy
  starts empty.
- **Upgrades**: change `ARG AGENTGATEWAY_VERSION` in the `Dockerfile`, push,
  redeploy. Database resources carry over. The first start on 1.7 migrates the
  request-log database (new analytics columns); let it finish.
- **Locked out of the UI** (wrong password, bad policy): there is no shell and
  the unauthenticated admin listener on `:15000` is loopback-only, so recover by
  pointing the app at a fresh database:
  `DATABASE_URL=sqlite:///data/recover.db` → redeploy → the UI opens again.
  The file baseline (including the `NaN` provider and `NaN/*` / `*` models) is
  untouched, while the resources in the old database (extra models, keys,
  policies) are not loaded. Set the original `DATABASE_URL` again once you have
  a working policy.
- **Stay on one replica.** Two processes on one SQLite file corrupt it. Switch
  to Postgres (below) before scaling out.

## Switching to Postgres

The same image works with Postgres — override the env var and bump replicas if
needed:

```
DATABASE_URL=postgres://USER:***@HOST:5432/DBNAME
```

The database user needs `CREATE TABLE` rights so agentgateway can create its
schema on first start. `db/` contains a plain PostgreSQL 17 image you can deploy
as a worker app in the same Space (`POSTGRES_PASSWORD`,
`POSTGRES_USER=agentgateway`, `POSTGRES_DB=agentgateway`, persistent storage
enabled at `/data`). If scaling to multiple replicas, also set a shared
`SESSION_KEY` environment variable so MCP session encryption keys match across
pods.

### Why `docker-entrypoint.sh` exists

The upstream image (`cr.agentgateway.dev/agentgateway:v1.7.0`) is distroless
and runs as uid `65532`, while NaN Cloud mounts `/data` root-owned (causing
SQLite error code 14). Wrapping the binary in `wolfi-base` lets
`docker-entrypoint.sh` fix `/data` ownership, auto-discover NaN models from
`/v1/models`, and drop privileges via `su-exec` before exec'ing `agentgateway`.

### Related guides

- [Budgets, Virtual API Keys & NaN Credits](budgets-and-keys.md)
- [Adding MCP Servers](mcp.md)

### Why `ui.policies` is not in `config/config.yaml`

A policy written to the config file is **file-owned**: hybrid mode can only
overlay new resources, so the UI rejects edits to it with a `409 conflict`.
Keeping it in the database is what makes "enable auth from the UI" work. The
cost is the recovery procedure above. If you would rather have a Git-revertible
auth policy than a UI-editable one, move the `basicAuth` block into the `ui:`
section of `config/config.yaml` (with `$$` escaping) and accept that the policy
page becomes read-only in the UI.
