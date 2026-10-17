# Fallback PostgreSQL for the agentgateway app.
#
# Deploy this as a separate NaN app (worker mode, no HTTP port) in the same
# Space as the gateway, with a persistent volume mounted at
# /var/lib/postgresql/data. Then point the gateway's DATABASE_URL at this app's
# service hostname on port 5432.
#
# NaN builds with the Dockerfile's own directory as the build context, so paths
# here are relative to db/:
#   docker build -f db/Dockerfile db/
#
# Required env:
#   POSTGRES_PASSWORD   (any strong string; also used in DATABASE_URL)
# Defaults (override if you like):
#   POSTGRES_USER=agentgateway
#   POSTGRES_DB=agentgateway
FROM postgres:17-alpine

# Keep the cluster in a subdirectory of the mount point so a volume that
# already contains files (e.g. lost+found) does not block initdb.
ENV PGDATA=/var/lib/postgresql/data/pgdata

# First-boot only: runs once, when PGDATA is empty.
COPY init.sql /docker-entrypoint-initdb.d/10-agentgateway.sql

# The entrypoint listens on all interfaces; 5432 is the default.
EXPOSE 5432

HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=5 \
  CMD pg_isready -U "${POSTGRES_USER:-agentgateway}" -d "${POSTGRES_DB:-agentgateway}" || exit 1
