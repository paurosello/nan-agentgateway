ARG AGENTGATEWAY_VERSION=v1.6.0
FROM cr.agentgateway.dev/agentgateway:${AGENTGATEWAY_VERSION}

# Baseline config. The UI writes changes to Postgres (storage mode: hybrid),
# never to this file, so it can stay owned by root and read-only for the
# runtime user (65532 in the upstream image).
COPY config/config.yaml /etc/agentgateway/config.yaml

# Proxy + UI + config API all share the gateway port.
EXPOSE 4000

ENTRYPOINT ["/app/agentgateway"]
CMD ["-f", "/etc/agentgateway/config.yaml"]
