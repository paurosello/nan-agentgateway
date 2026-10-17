#!/bin/sh
# Connectivity probe for NaN Cloud: run as a second app in the same Space as
# the gateway (worker mode, no HTTP port) and read the logs.
#   DB_HOST=agentgateway-db-pg-rw.space-drondin-pau.svc.cluster.local
#   DB_PORT=5432
set -u

HOST="${DB_HOST:?set DB_HOST env var}"
PORT="${DB_PORT:-5432}"

echo "=== probe start: ${HOST}:${PORT} ==="
date -u

echo "--- /etc/resolv.conf ---"
cat /etc/resolv.conf

echo "--- nslookup ---"
nslookup "$HOST" 2>&1 || echo "NSLOOKUP_FAILED"

echo "--- A / AAAA ---"
dig +short A "$HOST" 2>&1 || true
dig +short AAAA "$HOST" 2>&1 || true

echo "--- tcp connect (5s) ---"
if nc -z -v -w 5 "$HOST" "$PORT" 2>&1; then
  echo "TCP_OK"
else
  echo "TCP_FAIL"
fi

echo "--- tls handshake (8s) ---"
timeout 8 openssl s_client -connect "${HOST}:${PORT}" -brief </dev/null 2>&1 | head -20 || echo "TLS_FAIL"

echo "=== probe done ==="
# Stay alive so the platform keeps the logs of this single run.
sleep 3600
