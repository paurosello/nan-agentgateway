ARG AGENTGATEWAY_VERSION=v1.6.0

# Upstream image is Wolfi-based and distroless: no shell, so nothing can be
# installed, chowned or wrapped on top of it. Take the binary from it and put it
# into a Wolfi base of the same glibc family, which lets us run a small
# entrypoint that fixes persistent-volume ownership and then drops privileges.
FROM cr.agentgateway.dev/agentgateway:${AGENTGATEWAY_VERSION} AS upstream

FROM cgr.dev/chainguard/wolfi-base:latest

RUN apk add --no-cache su-exec ca-certificates-bundle

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

# Proxy + UI + config API all share the gateway port.
EXPOSE 4000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["-f", "/etc/agentgateway/config.yaml"]
