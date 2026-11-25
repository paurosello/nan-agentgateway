#!/bin/sh
# Entry point for the NaN packaging of agentgateway.
#
# NaN mounts persistent storage root-owned at /data, while the upstream
# agentgateway image runs as uid 65532 and therefore cannot create its SQLite
# file there ("unable to open database file", sqlite code 14). To work in both
# worlds this container starts as root, takes ownership of the SQLite directory
# on the persistent volume, then drops to 65532 before starting the gateway.
#
# If anything else (e.g. Kubernetes runAsNonRoot) starts the container as a
# non-root user already, that step is skipped and the gateway is exec'd as is.
set -eu

APP_UID=65532
APP_GID=65532

# Default NAN_API_KEY to empty so the pre-configured NaN provider in
# config/config.yaml still boots cleanly before the user sets their key.
export NAN_API_KEY="${NAN_API_KEY:-}"

if [ "$(id -u)" = "0" ]; then
  url="${DATABASE_URL:-}"
  case "$url" in
    postgres://*|postgresql://*)
      ;; # Postgres owns its own permissions; nothing to do here.
    sqlite:*)
      dbpath="${url#sqlite://}"
      dbpath="${dbpath#sqlite:}"
      dbpath="${dbpath%%\?*}"
      dbpath="${dbpath#/}"
      dbdir="/$(dirname "$dbpath")"
      echo "[entrypoint] sqlite database: /${dbpath} (dir ${dbdir})"
      mkdir -p "$dbdir"
      chown -R "$APP_UID:$APP_GID" "$dbdir"
      ;;
  esac
  exec su-exec "$APP_UID:$APP_GID" /app/agentgateway "$@"
fi

echo "[entrypoint] already running as uid $(id -u); starting gateway directly"
exec /app/agentgateway "$@"
