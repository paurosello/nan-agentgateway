#!/bin/sh
# Connectivity probe for NaN Cloud: run as a second app in the same Space as
# the gateway (worker mode, no HTTP port) and read the logs.
#
#   DB_HOSTS  optional, comma-separated host:port targets to test
#             default: $DB_HOST:$DB_PORT plus the gateway app on :4000
#
# Besides the explicit targets, this queries the Kubernetes API with the pod's
# service account to list Services / Endpoints / Pods in the namespace, so the
# real service naming shows up even if it differs from the app name.
set -u

NS="${POD_NAMESPACE:-space-drondin-pau}"
DEFAULT_HOSTS="${DB_HOST:-agentgateway-db.space-drondin-pau.svc.cluster.local}:${DB_PORT:-5432},phsv.space-drondin-pau.svc.cluster.local:4000"
HOSTS="${DB_HOSTS:-$DEFAULT_HOSTS}"

echo "=== probe start ==="
date -u
echo "hostname: $(hostname 2>/dev/null)"

echo "--- platform env (filtered) ---"
env | grep -iE '^(KUBERNETES|NAN|APP|SERVICE|POD|HOST|SPACE|DB|PG)' | sed 's/\(PASSWORD\|SECRET\|TOKEN\)=.*/\1=<redacted>/' | sort

echo "--- /etc/resolv.conf ---"
cat /etc/resolv.conf

SA=/var/run/secrets/kubernetes.io/serviceaccount
if [ -f "$SA/token" ]; then
  echo "--- k8s api: namespace ${NS} ---"
  for res in services endpoints pods; do
    code=$(curl -s --cacert "$SA/ca.crt" \
      -H "Authorization: Bearer $(cat "$SA/token")" \
      "https://kubernetes.default.svc/api/v1/namespaces/${NS}/${res}" \
      -o "/tmp/${res}.json" -w '%{http_code}')
    echo "### ${res} -> HTTP ${code}"
    if [ "$res" = services ] && [ "$code" = 200 ]; then
      jq -r '.items[]? | "SVC \(.metadata.name)  ip=\(.spec.clusterIP // "-")  type=\(.spec.type)  ports=\([.spec.ports[]? | "\(.port)->\(.targetPort)"] | join(","))"' /tmp/services.json 2>/dev/null \
        || head -c 600 /tmp/services.json
    elif [ "$res" = endpoints ] && [ "$code" = 200 ]; then
      jq -r '.items[]? | "EP \(.metadata.name)  ready=\([.subsets[]?.addresses[]?.ip] | join(","))"' /tmp/endpoints.json 2>/dev/null \
        || head -c 400 /tmp/endpoints.json
    elif [ "$res" = pods ] && [ "$code" = 200 ]; then
      jq -r '.items[]? | "POD \(.metadata.name)  phase=\(.status.phase)"' /tmp/pods.json 2>/dev/null \
        || head -c 400 /tmp/pods.json
    else
      head -c 300 "/tmp/${res}.json" 2>/dev/null; echo
    fi
  done
else
  echo "--- no service account token mounted ---"
fi

echo "--- explicit targets ---"
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
