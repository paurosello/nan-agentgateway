# nan-agentgateway

Standalone [agentgateway](https://agentgateway.dev) (OSS, Apache-2.0) packaged for
[NaN Cloud](https://nan.builders/docs/apps): one HTTP port, Postgres-backed, UI
enabled.

The image is just the official `cr.agentgateway.dev/agentgateway` image plus a
baseline `config/config.yaml`. There is no custom build step, so upgrades are a
one-line change.

## What it runs

| | |
|---|---|
| Image | `cr.agentgateway.dev/agentgateway:v1.6.0` (multi-arch) |
| Port | `4000` — proxy, config API, and UI |
| UI | `https://<app-domain>/ui` |
| Storage | `hybrid` — baseline from `config/config.yaml`, UI/API writes in Postgres |
| Database | PostgreSQL via `DATABASE_URL` (required) |

## Deploy on NaN Cloud

1. **Space → New App**, pick this repo (`paurosello/nan-agentgateway`), branch
   `main`, Dockerfile path `Dockerfile`.
2. Check **Expose over HTTP** and set the port to **4000**.
3. Add the environment variable:

   ```
   DATABASE_URL=postgres://USER:PASSWORD@HOST:5432/DBNAME
   ```

   Point it at the existing Postgres app. The user needs `CREATE TABLE`
   rights on that database — agentgateway creates its schema on first start
   (analytics, logs, API keys, UI-managed config).
4. Deploy, then open `https://<app-domain>/ui`.

If `DATABASE_URL` is missing or unset, the container exits at startup with
`error looking key 'DATABASE_URL' up: environment variable not found`. That is
intentional; a gateway without a database cannot persist the UI config.

> The built-in admin listener (default `localhost:15000`) is loopback-only
> inside the container and is not published. Everything you need is on `/ui`
> at port 4000, which this config attaches to the `default` gateway.

## After the first start

The baseline config defines no LLM providers, models, MCP targets, or routes.
Add them in the UI (`/ui` → LLM / MCP). Because storage mode is `hybrid`, those
resources are written to Postgres, not to the config file, so they survive
restarts and redeploys.

To change something the database cannot hold (ports, `config.*` section such as
storage mode or the database URL), edit `config/config.yaml` and redeploy.

## Upgrade agentgateway

Change the `ARG` in the `Dockerfile` and push:

```dockerfile
ARG AGENTGATEWAY_VERSION=v1.6.0
```

Check <https://github.com/agentgateway/agentgateway/releases> for the tag, then
redeploy the app in NaN. Resource definitions stored in Postgres carry over.

## Run it locally

```sh
docker build -t nan-agentgateway .
docker run --rm -p 4000:4000 \
  -e DATABASE_URL='postgres://user:pass@host:5432/agentgateway' \
  nan-agentgateway
# UI: http://localhost:4000/ui
```

Validate a config change without starting the gateway:

```sh
docker run --rm -e DATABASE_URL='postgres://u:p@h:5432/d' \
  --entrypoint /app/agentgateway nan-agentgateway \
  -f /etc/agentgateway/config.yaml --validate-only
```

## Files

```
Dockerfile              thin wrapper over the upstream image
config/config.yaml      baseline gateway config (port 4000, hybrid storage)
```
