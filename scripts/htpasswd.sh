#!/usr/bin/env bash
# Generate ready-to-paste Basic Auth YAML for agentgateway UI:
# Settings -> UI -> Basic auth -> raw (<>) mode.
#
#   ./scripts/htpasswd.sh <username> [realm]
set -euo pipefail

user="${1:-}"
realm="${2:-nan-agentgateway}"
if [ -z "$user" ]; then
  echo "usage: $0 <username> [realm]" >&2
  exit 2
fi

if command -v htpasswd >/dev/null 2>&1; then
  gen() { htpasswd -nbB -C 10 "$1" "$2"; }
elif [ -x /usr/sbin/htpasswd ]; then
  gen() { /usr/sbin/htpasswd -nbB -C 10 "$1" "$2"; }
else
  echo "htpasswd not found. Install apache2-utils (Linux) or use:" >&2
  echo "  openssl passwd -apr1 '<password>'   # then prefix with <user>:" >&2
  exit 1
fi

if [ -n "${AGW_PASSWORD:-}" ]; then
  pw="$AGW_PASSWORD"
else
  read -r -s -p "Password for ${user}: " pw
  echo >&2
  read -r -s -p "Repeat password: " pw2
  echo >&2
  if [ "$pw" != "$pw2" ]; then
    echo "passwords do not match" >&2
    exit 1
  fi
fi
[ -n "$pw" ] || {
  echo "empty password" >&2
  exit 1
}

line="$(gen "$user" "$pw")"

cat <<EOF
# Paste into Settings -> UI -> Basic auth -> raw (<>) mode:
mode: strict
realm: ${realm}
htpasswd: |
  ${line}
EOF
