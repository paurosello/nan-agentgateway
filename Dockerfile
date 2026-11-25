ARG AGENTGATEWAY_VERSION=v1.7.0

# The upstream runtime is Chainguard's glibc-dynamic (Wolfi-based, distroless,
# uid 65532, binary at /app/agentgateway): no shell, so nothing can be installed,
# chowned or wrapped on top of it. Take the binary from it and put it into a Wolfi
# base of the same family, which lets us run a small entrypoint that fixes
# persistent-volume ownership and then drops privileges.
#
# The binary is glibc-dynamic. 1.7.0 needs GLIBC_2.39; wolfi-base:latest ships
# 2.44. Do not pin an old wolfi-base digest, or the image will fail at startup
# with "version `GLIBC_2.39' not found".
FROM cr.agentgateway.dev/agentgateway:${AGENTGATEWAY_VERSION} AS upstream

FROM cgr.dev/chainguard/wolfi-base:latest

RUN apk add --no-cache su-exec ca-certificates-bundle curl jq

COPY --from=upstream /app/agentgateway /app/agentgateway

# Baseline config: read-only in hybrid storage mode, UI/API writes go to the DB.
COPY config/config.yaml /etc/agentgateway/config.yaml
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh \
 && mkdir -p /data \
 && chown 65532:65532 /data

# Default: SQLite on NaN's persistent volume (always mounted at /data). Keep
# replicas at 1 while on SQLite. Override with a postgres:// or postgresql:// URL
# to use Postgres instead — no rebuild needed.
ENV DATABASE_URL=sqlite:///data/agentgateway.db

# Match the upstream image's environment: explicit trust store, and the flag that
# makes the binary treat itself as running in the official container.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    AGENTGATEWAY_ENV=container

# Proxy + UI + config API all share the gateway port.
EXPOSE 4000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["-f", "/etc/agentgateway/config.yaml"]
