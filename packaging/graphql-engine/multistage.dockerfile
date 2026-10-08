# Multi-stage build of graphql-engine (v2), runnable on linux/arm64 or linux/amd64.
#
# Build context must be the repository root:
#   docker buildx build --platform linux/arm64 \
#     -f packaging/graphql-engine/multistage.dockerfile -t my-hge:v2 .

ARG UBUNTU_IMAGE=ubuntu:noble-20260911
# Fallback only; build.sh overrides this with the release matching the checkout.
ARG CONSOLE_ASSETS_IMAGE=hasura/graphql-engine:v2.51.0

###############################################################################
# Stage 0: console assets from an official release image (ARG must be global to be used in FROM)
###############################################################################
FROM ${CONSOLE_ASSETS_IMAGE} AS console

###############################################################################
# Stage 1: compile graphql-engine
###############################################################################
FROM ${UBUNTU_IMAGE} AS builder

ARG GHC_VERSION=9.14.1
ARG CABAL_VERSION=3.16.1.0

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive \
    BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
    BOOTSTRAP_HASKELL_MINIMAL=1 \
    GHCUP_INSTALL_BASE_PREFIX=/opt \
    PATH=/opt/.ghcup/bin:/root/.cabal/bin:$PATH

# Keep these in sync with the runtime libs in graphql-engine-base/ubuntu.dockerfile.
# The upgrade mirrors the runtime stage, so both link/run against the same libc and libs.
RUN set -ex; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
      build-essential curl ca-certificates git pkg-config xz-utils \
      libgmp-dev libffi-dev libncurses-dev zlib1g-dev libnuma-dev \
      libpq-dev libssl-dev libkrb5-dev unixodbc-dev libsqlite3-dev \
      libtinfo-dev; \
    rm -rf /var/lib/apt/lists/*

RUN set -ex; \
    curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh; \
    ghcup install ghc "${GHC_VERSION}" --set; \
    ghcup install cabal "${CABAL_VERSION}" --set; \
    ghc --version; cabal --version

WORKDIR /src

COPY . .

# cabal.project defaults to jobs=$ncpus and an unbounded ghc -j, which can exceed
# the memory available to Docker (GHC gets OOM-killed on this package). Lower
# BUILD_JOBS if it still dies, raise it if you have plenty of RAM (~2GB per job).
ARG BUILD_JOBS=4
# server/CURRENT_VERSION is gitignored and baked into the binary at compile time
# (Hasura.Server.Version). A non-semver value is treated as a dev build.
ARG HGE_VERSION=v2-greyfinch
RUN set -ex; \
    echo "${HGE_VERSION}" > server/CURRENT_VERSION; \
    cabal update; \
    cabal build exe:graphql-engine \
      --project-file=cabal.project \
      -f optimize-hasura \
      --jobs=${BUILD_JOBS} \
      --ghc-options="-j${BUILD_JOBS}"; \
    mkdir -p /out; \
    cp "$(cabal list-bin exe:graphql-engine -f optimize-hasura)" /out/graphql-engine; \
    strip --strip-unneeded /out/graphql-engine

###############################################################################
# Stage 2: runtime
###############################################################################
FROM ${UBUNTU_IMAGE} AS base
# Mirrors packaging/graphql-engine-base/ubuntu.dockerfile, minus the MSSQL ODBC drivers (Postgres only).
ARG TARGETPLATFORM
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 OPENSSL_FORCE_FIPS_MODE=0 DEBIAN_FRONTEND=noninteractive

RUN set -ex; \
    groupadd -g 1001 hasura; \
    useradd -m -u 1001 -g hasura hasura; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl libkrb5-3 libpq5 libnuma1 unixodbc netcat-traditional; \
    rm -f /etc/ssl/private/ssl-cert-snakeoil.key /etc/ssl/certs/ssl-cert-snakeoil.pem; \
    apt-get -y auto-remove; \
    apt-get -y clean; \
    rm -rf /var/lib/apt/lists/* /usr/share/doc/ /usr/share/man/ /usr/share/locale/

# pg_dump is used by the /v1alpha1/pg_dump API. Remove this block if you don't need it.
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends gnupg2 lsb-release postgresql-common; \
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y; \
    apt-get install -y --no-install-recommends postgresql-client-18; \
    find /usr/bin -name 'pg*' -not -path '/usr/bin/pg_dump' -delete; \
    apt-get -y remove gnupg2; \
    apt-get -y auto-remove; \
    apt-get -y clean; \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/graphql-engine /bin/graphql-engine

# Console UI: static assets, taken from the official image of the matching release
# (the console is built from frontend/ in a separate pipeline). Set
# HASURA_GRAPHQL_CONSOLE_ASSETS_DIR=/srv/console-assets at runtime to serve them.
COPY --from=console /srv/console-assets /srv/console-assets

ENV HGE_BINARY=graphql-engine
EXPOSE 8080
# JSON form (signals reach the server) that still honors HGE_BINARY; exec replaces the shell.
CMD ["sh", "-c", "exec \"${HGE_BINARY}\" serve"]
