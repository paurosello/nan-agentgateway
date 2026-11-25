#!/usr/bin/env bash
# Generate copy-paste-ready YAML for the agentgateway UI.
#
#   ./scripts/generate-config.sh
#
# Prompts for a password (never on the command line, never in shell history),
# hashes it with htpasswd, and prints the exact blocks each UI editor expects:
#
#   1. UI access policy  -> Settings > UI > UI access policies > Basic auth > raw
#   2. Provider          -> LLM > Providers > Add provider > raw
#   3. Model             -> LLM > Models > Add model > raw
#   4. config/config.yaml -> for Git, with `$` doubled for file mode
#
# The difference in (1) vs (4) matters: database-backed resources are stored
# verbatim, the config file is environment-expanded. Getting it backwards is the
# usual reason Basic Auth rejects every password.
set -euo pipefail

user="pau"
realm="nan-agentgateway"
model="NaN/*"
base_url="https://api.nan.builders"
env_var="NAN_API_KEY"
port="4000"
url=""
out=""

usage() {
	cat <<'EOF'
Generate copy-paste-ready YAML for the agentgateway UI.

  ./scripts/generate-config.sh

Prompts for a password (never on the command line, never in shell history),
hashes it with htpasswd, and prints the exact blocks each UI editor expects:

  1. UI access policy   Settings > UI > UI access policies > Basic auth > raw
  2. Provider           LLM > Providers > Add provider > raw
  3. Model              LLM > Models > Add model > raw
  4. config/config.yaml for Git, with $ doubled for file mode

Blocks 1 and 4 differ on purpose: database-backed resources are stored verbatim,
the config file is environment-expanded. Getting it backwards is the usual
reason Basic Auth rejects every password.

Options:
  -u, --user NAME       username for the htpasswd line   (default: pau)
  -r, --realm NAME      realm in the challenge           (default: nan-agentgateway)
  -m, --model PATTERN   model pattern to expose          (default: NaN/*)
  -b, --base-url URL    upstream base URL                (default: https://api.nan.builders)
  -e, --env-var NAME    env var holding upstream key     (default: NAN_API_KEY)
  -p, --port PORT       port in the full config file     (default: 4000)
  -U, --url URL         gateway URL used in the curl hints
  -o, --out DIR         also write the blocks as files into DIR
  -h, --help            this text

Password: prompted twice on the terminal, or taken from AGW_PASSWORD.
EOF
}

need() { [ $# -ge 2 ] || { echo "$1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
	-u | --user)
		need "$1" "$2"
		user="$2"
		shift 2
		;;
	-r | --realm)
		need "$1" "$2"
		realm="$2"
		shift 2
		;;
	-m | --model)
		need "$1" "$2"
		model="$2"
		shift 2
		;;
	-b | --base-url)
		need "$1" "$2"
		base_url="$2"
		shift 2
		;;
	-e | --env-var)
		need "$1" "$2"
		env_var="$2"
		shift 2
		;;
	-p | --port)
		need "$1" "$2"
		port="$2"
		shift 2
		;;
	-U | --url)
		need "$1" "$2"
		url="$2"
		shift 2
		;;
	-o | --out)
		need "$1" "$2"
		out="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "unknown option: $1 (try --help)" >&2
		exit 2
		;;
	esac
done

if command -v htpasswd >/dev/null 2>&1; then
	HTPASSWD=htpasswd
elif [ -x /usr/sbin/htpasswd ]; then
	HTPASSWD=/usr/sbin/htpasswd
else
	echo "htpasswd not found: install apache2-utils, or use 'openssl passwd -apr1'" >&2
	exit 1
fi

if [ -n "${AGW_PASSWORD:-}" ]; then
	pw="$AGW_PASSWORD"
else
	read -r -s -p "Password for ${user}: " pw
	echo
	read -r -s -p "Repeat password: " pw2
	echo
	[ "$pw" = "$pw2" ] || {
		echo "passwords do not match" >&2
		exit 1
	}
fi
[ -n "$pw" ] || {
	echo "empty password" >&2
	exit 1
}

htline="$("$HTPASSWD" -nbB -C 10 "$user" "$pw")"
escaped="$(printf '%s\n' "$htline" | sed 's/\$/$$/g')"

# --- 1. UI access policy (raw value pasted into the policy drawer) ------------
ui_policy="$(
	cat <<EOF
mode: strict
realm: ${realm}
htpasswd: |
  ${htline}
EOF
)"

# --- 2. Provider -------------------------------------------------------------
provider="$(
	cat <<EOF
name: NaN
provider:
  custom:
    formats:
      - type: completions
params:
  baseUrl: ${base_url}
  apiKey: \${${env_var}}
EOF
)"

# --- 3. Model ----------------------------------------------------------------
prefix="${model%/\*}"
model_yaml="$(
	cat <<EOF
name: ${model}
provider:
  reference: NaN
transformation:
  model: 'llmRequest.model.stripPrefix("${prefix}/")'
EOF
)"

# --- 4. Full config file (GitOps / file mode) -------------------------------
# shellcheck disable=SC2016 # dollar-brace must stay literal
file_config="$(
	cat <<EOF
# yaml-language-server: \$schema=https://agentgateway.dev/schema/config
config:
  storage:
    mode: hybrid
  database:
    url: \${DATABASE_URL}

gateways:
  default:
    port: ${port}

llm: {}
mcp:
  targets: []
routes: []

ui:
  gateways: default
  policies:
    basicAuth:
      mode: strict
      realm: ${realm}
      htpasswd: |
        ${escaped}
EOF
)"

hint="${url:-https://<app>-<space>.apps.nan.builders}"

if [ -t 1 ]; then
	bold="$(printf '\033[1m')"
	reset="$(printf '\033[0m')"
else
	bold=""
	reset=""
fi

emit() {
	label="$1"
	file="$2"
	body="$3"
	printf '\n%s=== %s%s\n\n%s\n' "$bold" "$label" "$reset" "$body"
	if [ -n "$out" ]; then
		mkdir -p "$out"
		printf '%s\n' "$body" >"$out/$file"
	fi
}

echo
echo "Generated for user '${user}'. Copy each block into the place named above it."
emit "1) Settings > UI > UI access policies > Basic auth > raw (<>) mode" "ui-basic-auth.yaml" "$ui_policy"
emit "2) LLM > Providers > Add provider > raw (<>) mode" "provider.yaml" "$provider"
emit "3) LLM > Models > Add model > raw (<>) mode" "model.yaml" "$model_yaml"
emit "4) config/config.yaml (GitOps; do not paste this into the Raw Configuration page in hybrid mode - Save is disabled there)" "config.yaml" "$file_config"

printf '\n%s=== Check%s\n\n' "$bold" "$reset"
cat <<EOF
  curl -s -o /dev/null -w 'ui=%{http_code}\\n' ${hint}/ui
  curl -s -o /dev/null -w 'ui=%{http_code}\\n' -u '${user}:<password>' ${hint}/ui
  curl -s -o /dev/null -w 'api=%{http_code}\\n' ${hint}/api/config
EOF
cat <<'EOF'

Expected: 401, 200, 401.
  first  200 = the policy did not save
  second 401 = the $$-escaped line was pasted into the UI, or the password and
               hash do not match (verify: htpasswd -vb <(generated) <user>)
  third  401 = correct; /api is protected together with /ui

Virtual keys (LLM > Virtual API Keys) are better created in the UI: it stores
only the hash of each key. The gateway-level apiKey policy covers LLM traffic,
not /ui or /api.
EOF
if [ -n "$out" ]; then
	echo "Files written to ${out}/"
fi

