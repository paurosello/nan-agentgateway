#!/bin/sh
# Entry point for the NaN packaging of agentgateway.
#
# 1. Defaults NAN_API_KEY to empty so the pre-configured NaN provider boots
#    cleanly before the user sets their key.
# 2. If NAN_API_KEY is set (and NAN_DISCOVER_MODELS != false), fetches
#    NAN_MODELS_URL (default https://api.nan.builders/v1/models) and injects
#    each discovered model into llm.models[] in a runtime copy of config.yaml,
#    so individual models show up in /v1/models, Playground, and Virtual API
#    Key allowed-models pickers. Any failure falls back cleanly to the baseline
#    config (NaN/* and *).
# 3. NaN mounts persistent storage root-owned at /data, while the upstream
#    agentgateway image runs as uid 65532 and therefore cannot create its SQLite
#    file there ("unable to open database file", sqlite code 14). When started
#    as root, take ownership of the SQLite directory then drop to 65532.
set -eu

APP_UID=65532
APP_GID=65532

# Default NAN_API_KEY to empty so the pre-configured NaN provider in
# config/config.yaml still boots cleanly before the user sets their key.
export NAN_API_KEY="${NAN_API_KEY:-}"

MARKER="# @NAN_DISCOVERED_MODELS@"
RUNTIME_CFG="/tmp/agentgateway-config.yaml"

discover_models() {
  cfg_path="$1"
  [ "${NAN_DISCOVER_MODELS:-true}" != "false" ] || {
    echo "[entrypoint] model discovery disabled (NAN_DISCOVER_MODELS=false)"
    return 1
  }
  [ -n "$NAN_API_KEY" ] || {
    echo "[entrypoint] model discovery skipped (NAN_API_KEY unset)"
    return 1
  }
  [ -f "$cfg_path" ] && grep -qF "$MARKER" "$cfg_path" || return 1

  models_url="${NAN_MODELS_URL:-https://api.nan.builders/v1/models}"
  raw_json="$(mktemp /tmp/nan-models.XXXXXX)"
  snippet="$(mktemp /tmp/nan-snippet.XXXXXX)"

  if ! curl -fsS --connect-timeout 3 --max-time 8 \
      -H "Authorization: Bearer ${NAN_API_KEY}" \
      "$models_url" > "$raw_json" 2>/dev/null; then
    echo "[entrypoint] warning: failed to fetch ${models_url}; using baseline models"
    rm -f "$raw_json" "$snippet"
    return 1
  fi

  # Only register chat and embedding models (skip audio/TTS/STT/image entries
  # like whisper or kokoro so they do not clutter chat pickers; * still routes
  # anything directly if needed).
  jq_filter='[.data[]? | select(.mode == null or .mode == "chat" or .mode == "embedding") | .id | select(type == "string" and length > 0 and . != "*" and . != "NaN/*")] | unique'

  count="$(jq -r "${jq_filter} | length" "$raw_json" 2>/dev/null || echo 0)"
  if [ -z "$count" ] || [ "$count" = "0" ]; then
    echo "[entrypoint] warning: no models returned by ${models_url}; using baseline models"
    rm -f "$raw_json" "$snippet"
    return 1
  fi

  # Escape '$' as '$$' because agentgateway runs pre-YAML env expansion on the file.
  if ! jq -r "${jq_filter} | .[] | gsub(\"\\\\\$\"; \"\$\$\") | \"    - name: \(tojson)\n      provider:\n        reference: NaN\"" \
      "$raw_json" > "$snippet" 2>/dev/null; then
    echo "[entrypoint] warning: failed to parse ${models_url}; using baseline models"
    rm -f "$raw_json" "$snippet"
    return 1
  fi

  : > "$RUNTIME_CFG"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *"$MARKER"*) cat "$snippet" >> "$RUNTIME_CFG" ;;
      *) printf '%s\n' "$line" >> "$RUNTIME_CFG" ;;
    esac
  done < "$cfg_path"
  chmod 0644 "$RUNTIME_CFG"
  rm -f "$raw_json" "$snippet"
  echo "[entrypoint] discovered ${count} models from ${models_url}"
  return 0
}

# Find -f / --file in "$@" and swap in RUNTIME_CFG if discovery succeeds.
cfg_arg=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-f" ] || [ "$prev" = "--file" ]; then
    cfg_arg="$arg"
    break
  fi
  prev="$arg"
done

if [ -n "$cfg_arg" ] && discover_models "$cfg_arg"; then
  # Rebuild positional arguments with cfg_arg replaced by RUNTIME_CFG.
  replaced=0
  prev=""
  i=0
  argc=$#
  while [ "$i" -lt "$argc" ]; do
    arg="$1"
    shift
    i=$((i + 1))
    if [ "$replaced" = "0" ] && { [ "$prev" = "-f" ] || [ "$prev" = "--file" ]; }; then
      set -- "$@" "$RUNTIME_CFG"
      replaced=1
    else
      set -- "$@" "$arg"
    fi
    prev="$arg"
  done
fi

if [ "$(id -u)" = "0" ]; then
  url="${DATABASE_URL:-}"
  case "$url" in
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
