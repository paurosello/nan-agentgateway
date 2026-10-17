#!/bin/sh
# Connectivity probe for NaN Cloud: run as a second app in the same Space as
# the gateway (worker mode, no HTTP port) and read the logs.
#
#   DB_HOSTS  comma-separated list of host:port targets to test
#             default: $DB_HOST:$DB_PORT,phsv.space-drondin-pau.svc.cluster.local:4000
#
# The second default target is the gateway app itself: if it answers on its
# HTTP port, then app Services really are named <app>.<space>.svc.cluster.local
# and the database app follows the same pattern.
set -u

DEFAULT_HOSTS="${DB_HOST:-agentgateway-db-pg-rw.space-drondin-pau.svc.cluster.local}:${DB_PORT:-5432},phsv.space-drondin-pau.svc.cluster.local:4000"
HOSTS="${DB_HOSTS:-$DEFAULT_HOSTS}"

echo "=== probe start ==="
date -u
echo "--- whoami / hostname ---"
id 2>/dev/null || true
echo "hostname: $(hostname 2>/dev/null)"
cat /etc/hostname 2>/dev/null || true

echo "--- platform env (filtered) ---"
env | grep -iE '^(KUBERNETES|NAN|APP|SERVICE|POD|HOST|SPACE|DB|PG)' | sed 's/\(PASSWORD\|SECRET\|TOKEN\)=.*/\1=<redacted>/' | sort

echo "--- /etc/resolv.conf ---"
cat /etc/resolv.conf

echo "--- targets ---"
echo "$HOSTS" | tr ',' '\n' | while IFS= read -r target; do
  [ -z "$target" ] && continue
  t_host=${target%%:*}
  t_port=${target##*:}
  [ "$t_port" = "$t_host" ] && t_port=5432
  echo "### ${t_host}:${t_port}"

  echo "-- resolve --"
  dig +short A "$t_host" 2>/dev/null | head -3 || true

  echo "-- tcp (5s) --"
  if nc -z -v -w 5 "$t_host" "$t_port" 2>&1; then
    echo "TCP_OK ${t_host}:${t_port}"
  else
    echo "TCP_FAIL ${t_host}:${t_port}"
  fi

  echo "-- tls (8s) --"
  timeout 8 openssl s_client -connect "${t_host}:${t_port}" -brief </dev/null 2>&1 | head -6 || echo "TLS_FAIL"
  echo
done

echo "=== probe done ==="
# Stay alive so the platform keeps the logs of this single run.
sleep 3600
