# Deploy your own gateway

This repository is a template for **one gateway per person**. Each deployment
gets its own public URL, its own UI, its own SQLite database on its own volume,
and its own credentials. Nothing is shared between deployments, so you can
change anything you like without affecting anyone else.

If you only need an API key for someone else's gateway, you do not need this
guide — ask them for a virtual key.

- [1. Deploy](#1-deploy)
- [2. Lock the UI first](#2-lock-the-ui-first)
- [3. Add a model](#3-add-a-model)
- [4. Invite people with keys, not with the UI password](#4-invite-people-with-keys-not-with-the-ui-password)
- [Backups, upgrades, and recovery](#backups-upgrades-and-recovery)

## 1. Deploy

In [NaN Cloud](https://cloud.nan.builders/spaces), open or create a Space, then
**New App**:

| Field | Value |
|---|---|
| Repository | `paurosello/nan-agentgateway` (authorize it for the NaN GitHub App) |
| Branch | `main` |
| Dockerfile | `Dockerfile` |
| App name | anything, e.g. `my-gateway` (it becomes part of the URL) |
| Expose over HTTP | on, port **4000** |
| Persistent storage | **on** (required; NaN mounts it at `/data`) |
| Replicas | **1** (SQLite must not be shared) |
| Resources | `500m` / `512Mi` is enough |
| Environment | `NAN_API_KEY` = your NaN API key (optional now, used in step 3) |

Wait for `Running`, then open:

```
https://<app>-<space>.apps.nan.builders/ui
```

> **Storage is a creation-time choice.** Persistent storage can only be chosen
> in the New App form. The app settings panel edits branch, Dockerfile, port, and
> resources, not storage. If you deployed without it, delete the app and create
> it again with the same name in the same Space — the URL stays the same — then
> re-add your configuration.

> **Config-only customization:** deploying this repo directly is fine. If you
> also want to change the image, entrypoint, or baseline config, fork first and
> point NaN at your fork.

## 2. Lock the UI first

The UI is the **admin plane**. It can read and rewrite the entire gateway
configuration, including provider API keys, and it can turn authentication off
again. Until you add an auth policy, anyone who finds the URL is a full admin.
The home page shows a matching warning banner.

Generate a credential line:

```sh
./scripts/htpasswd.sh alice
```

Then in the UI: **Settings → UI → UI access policies → Add → Basic auth** (the
home page banner's *Configure UI policies* button links to the same page):

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
*file* needs `$$` escaping.

Prefer single sign-on? The same page offers OIDC (`oidc`), JWT, and external
authorization. OIDC needs an OIDC-capable provider (Google, Okta, Auth0,
Keycloak — GitHub is OAuth2 only) plus a client ID/secret and an absolute
callback URL on your app's host. On 1.7, set `credentials: sessionOrBearer` so
the same policy also accepts bearer ID tokens from CLI clients.

## 3. Add a model

The provider key stays out of the UI and out of the database: set the
`NAN_API_KEY` environment variable on the app, then reference it.

**LLM → Providers → Add provider**, open the raw (`<>`) toggle, and use:

```yaml
name: NaN
provider:
  custom:
    formats:
      - type: completions
params:
  baseUrl: https://api.nan.builders
  apiKey: ${NAN_API_KEY}
```

**LLM → Models → Add model**, raw toggle:

```yaml
name: NaN/*
provider:
  reference: NaN
transformation:
  model: 'llmRequest.model.stripPrefix("NaN/")'
```

Every form has that raw toggle, so pasted YAML like this is always accepted, and
fields the form does not model survive a save.

Clients then call `POST /v1/chat/completions` with `"model": "NaN/<model>"`.
`params.apiKey` is the one field that hybrid mode still expands from the
environment, which is why the key never has to be stored anywhere readable.

Without a working upstream key the gateway forwards requests unauthenticated
and `api.nan.builders` answers with a 404 or `model_not_found` — that is the
symptom to look for if completions fail.

## 4. Invite people with keys, not with the UI password

Anyone with the UI credential can read your provider key from `/api/config` and
remove your auth policy. For other people, mint keys instead:

**LLM → Virtual API Keys → Enable API key auth → `Strict` → New key**

Per key you can set:

- a name and `metadata` (e.g. `user: alice`),
- a rolling **budget** (tokens or USD) that blocks with `429`,
- **allowed models**, so a key can only call what it should,
- the key value itself, or let the UI generate one.

Keys are stored hashed, usage and cost are attributed per key in
**Analytics / Logs**, and revoking one key does not touch anyone else. Users
send:

```sh
curl https://<app>-<space>.apps.nan.builders/v1/chat/completions \
  -H "Authorization: Bearer vk-alice-..." \
  -H "content-type: application/json" \
  -d '{"model":"NaN/<model>","messages":[{"role":"user","content":"hi"}]}'
```

Note that the gateway-level `apiKey` policy applies to the LLM and MCP traffic
on the gateway, not to `/ui` and `/api`; those are covered by `ui.policies` from
step 2. Keep both on.

## Backups, upgrades, and recovery

- **State** lives in `/data/agentgateway.db*` on the persistent volume. That
  includes everything you created in the UI: providers, models, virtual keys,
  routes, MCP targets, and the auth policy. Back the volume up before deleting
  the app. If the UI stops asking for a password after a redeploy, the app is
  not mounting its volume — check **Advanced options → Persistent storage** in
  Nan; without it `/data` is container-local and every redeploy starts empty.
- **Upgrades**: change `ARG AGENTGATEWAY_VERSION` in the `Dockerfile`, push,
  redeploy. Database resources carry over. The first start on 1.7 migrates the
  request-log database (new analytics columns); let it finish.
- **Locked out of the UI** (wrong password, bad policy): there is no shell and
  the unauthenticated admin listener on `:15000` is loopback-only, so recover by
  pointing the app at a fresh database:
  `DATABASE_URL=sqlite:///data/recover.db` → redeploy → the UI opens again.
  The file baseline is untouched, but the resources in the old database
  (models, keys, policies) are not loaded. Keep your provider/model definitions
  somewhere you can paste them back, and set the original `DATABASE_URL` again
  once you have a working policy.
- **Stay on one replica.** Two processes on one SQLite file corrupt it. Switch
  to Postgres (see the main README) before scaling out.

### Why `ui.policies` is not in `config/config.yaml`

A policy written to the config file is **file-owned**: hybrid mode can only
overlay new resources, so the UI rejects edits to it with a `409 conflict`.
Keeping it in the database is what makes "enable auth from the UI" work. The
cost is the recovery procedure above. If you would rather have a Git-revertible
auth policy than a UI-editable one, move the `basicAuth` block into the `ui:`
section of `config/config.yaml` (with `$$` escaping) and accept that the policy
page becomes read-only in the UI.
