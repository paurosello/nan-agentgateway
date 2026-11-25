#!/usr/bin/env bash
# Generate one htpasswd line for agentgateway Basic Auth.
#
#   ./scripts/htpasswd.sh alice
#
# Two outputs: the raw line for the UI (DB-backed resources are stored exactly
# as entered, with no environment expansion), and the escaped line for
# config/config.yaml (the file is env-expanded, so `$` must be `$$`).
set -euo pipefail

user="${1:-}"
if [ -z "$user" ]; then
  echo "usage: $0 <username>" >&2
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

read -r -s -p "Password for ${user}: " pw
echo
read -r -s -p "Repeat password: " pw2
echo
if [ "$pw" != "$pw2" ]; then
  echo "passwords do not match" >&2
  exit 1
fi

line="$(gen "$user" "$pw")"

echo
echo "For the UI (Settings -> UI -> UI access policies -> Basic auth). Paste as-is:"
echo "  $line"
echo
echo "For config/config.yaml. Every \$ doubled:"
printf '  '
printf '%s\n' "$line" | sed 's/\$/$$/g'
echo
echo "Check locally:  echo '$line' > /tmp/u && htpasswd -vb /tmp/u '$user' '<password>'"
