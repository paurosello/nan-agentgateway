# nan-agentgateway

Your own [agentgateway](https://agentgateway.dev) (v1.7.0, OSS) on [NaN Cloud](https://cloud.nan.builders/spaces) — pre-wired for the NaN Inference API (`api.nan.builders`).

Deploy it in 2 minutes, lock the UI, and mint **Virtual API Keys** with **NaN credit budgets**, model restrictions, per-key analytics, and a shared **MCP server gateway**.

![Analytics showing NaN model spend in credits (1 credit = $1)](docs/images/analytics.png)

## What works out of the box

- **Pre-configured `NaN` provider** (`https://api.nan.builders/v1`), reading `NAN_API_KEY` from the container environment (never stored in the DB or leaked by `/api/config`).
- **Auto-discovered models**: fetches your available chat & embedding models from `/v1/models` on startup (with `NaN/*` and `*` fallbacks).
- **1:1 NaN credit cost tracking**: [config/model-catalog.json](config/model-catalog.json) maps **1 NaN credit = $1**, so Analytics and Virtual API Key USD budgets track your 7,000-credit pool directly.
- **Drop-in client support**: works with OpenAI Chat Completions, Embeddings, Anthropic `/v1/messages` (Claude Code), and OpenAI `/v1/responses` (Codex) — even for clients that omit `/v1` in their base URL.
- **SQLite on `/data`** (hybrid mode): UI changes survive restarts and redeploys without an external database.

---

## Quick start

### 1. Fork & deploy on NaN Cloud

Fork this repo (so you can tweak [config/config.yaml](config/config.yaml) or [config/model-catalog.json](config/model-catalog.json) anytime), then in [NaN Cloud](https://cloud.nan.builders/spaces) go to **Space → New App**:

| Setting | Value |
|---|---|
| Repository | your fork of `paurosello/nan-agentgateway` (branch `main`, `Dockerfile`) |
| Expose over HTTP | **On**, port **`4000`** |
| Persistent storage | **On** (required — creation-time option, mounted at `/data`) |
| Replicas | **`1`** (SQLite must not be shared across replicas) |
| Resources | `500m` / `512Mi` |
| Environment | `NAN_API_KEY` = your NaN API key *(tip: add it after step 3, or lock auth right away)* |

Wait for `Running`, then open `https://<app>-<space>.apps.nan.builders/ui`.

### 2. Lock the UI first

The UI is the admin plane — lock it before sharing the URL. Generate a Basic Auth line locally:

```sh
./scripts/htpasswd.sh <your-username>
```

Then in the UI: **Settings → UI → Basic auth**:
- **Mode:** `Strict`
- **Realm:** anything (e.g. `my-gateway`)
- **htpasswd:** paste the generated `<user>:$2y$...` line as-is and save.

### 3. Enable Virtual API Keys & mint a key

Never share your UI password or raw `NAN_API_KEY` with tools or teammates — give each app or person a virtual key instead:

**LLM → Virtual API Keys → Settings → Mode: `Strict` → `+ New key`**

![Virtual API Keys with credit budgets and model restrictions](docs/images/virtual-keys.png)

Optionally attach a **USD budget** (mapped 1:1 to NaN credits, e.g. `$500` = 500 credits) and **allowed models**.

### 4. Point your AI clients at your gateway

Use your gateway URL and the virtual key you just created (`agw_sk_...`):

```sh
curl https://<app>-<space>.apps.nan.builders/v1/chat/completions \
  -H "Authorization: Bearer agw_sk_..." \
  -H "content-type: application/json" \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"hi"}]}'
```

- **opencode / Cursor / OpenAI SDK:** Base URL `https://<app>-<space>.apps.nan.builders/v1`, API key `agw_sk_...`
- **Claude Code (Anthropic Messages):** `ANTHROPIC_BASE_URL=https://<app>-<space>.apps.nan.builders`, `ANTHROPIC_API_KEY=agw_sk_...`
- **MCP clients:** `https://<app>-<space>.apps.nan.builders/mcp`

---

## Guides

| Guide | What it covers |
|---|---|
| [Budgets, Virtual Keys & NaN Credits](docs/budgets-and-keys.md) | 1 credit = $1 catalog, setting per-key credit caps (`429`), flash-only keys, metadata & Analytics |
| [Adding MCP Servers](docs/mcp.md) | Adding remote Streamable HTTP / SSE MCP servers, upstream auth, Tool Playground, and client setup |
| [Full Self-Service & Operations Guide](docs/self-service.md) | OIDC/Basic auth details, Postgres, upgrading agentgateway, backups, troubleshooting & lockout recovery |
