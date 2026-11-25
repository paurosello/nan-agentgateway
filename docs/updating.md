# Keeping Your Fork Up to Date

NaN Cloud deploys from your own fork of `paurosello/nan-agentgateway`. Upstream updates bring newer `agentgateway` versions, refreshed NaN credit rates in `config/model-catalog.json`, and setup improvements.

## Option 1: Sync on GitHub (1 click)

If you haven't modified files in your fork:

1. Open your fork on GitHub (`https://github.com/<you>/nan-agentgateway`).
2. Click **Sync fork → Update branch**.

NaN Cloud automatically redeploys your app when `main` is updated.

## Option 2: Sync with Git CLI

If you customized `config/config.yaml` or `config/model-catalog.json` (or GitHub reports a merge conflict):

```sh
# One-time setup:
git remote add upstream https://github.com/paurosello/nan-agentgateway.git

# Whenever you want to pull updates:
git fetch upstream
git checkout main
git merge upstream/main
# (resolve any conflicts in your custom config, if prompted)
git push origin main
```

NaN Cloud automatically redeploys once `main` is pushed.

## What survives a redeploy

- Everything configured in the UI — **UI auth policy, Virtual API Keys, budgets, extra providers/models, MCP servers, logs, and Analytics** — lives in `/data/agentgateway.db` on your persistent volume and carries over automatically.
- **Quick sanity check after redeploy:** open `/ui` — it should still prompt for your UI password. If it opens without asking for a password, the app was created without **Persistent storage** enabled (see [docs/self-service.md](self-service.md#1-deploy)).
- **Checking what changed before syncing:** review the commit log at `https://github.com/paurosello/nan-agentgateway/commits/main` for any breaking notes or config changes.
