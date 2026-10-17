# Diagnostic image — deploy as a SEPARATE NaN app (worker mode, no HTTP port)
# pointing at this Dockerfile path (debug/Dockerfile), in the same Space as the
# agentgateway app. Env: DB_HOST, DB_PORT. Read the app logs for the results.
FROM alpine:3.20

RUN apk add --no-cache bind-tools netcat-openbsd openssl

COPY debug/probe.sh /probe.sh
RUN chmod +x /probe.sh

CMD ["/probe.sh"]
