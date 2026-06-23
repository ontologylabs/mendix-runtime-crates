# Mendix 8 Runtime Crate — model-agnostic, app-agnostic, version-pinned.
#
# Image: ontologylabs/mendix-runtime:8
#        ontologylabs/mendix-runtime:8.18.35.97 (immutable)
#
# Contract:
#   * Bake: JRE 11 + Mendix 8.x runtime + m2ee admin scripts
#   * NEVER bake: any application's model / javasource / theme / userlib
#   * Bind-mount the unzipped MDA at /opt/mendix/app
#   * Bind-mount writable file storage at /opt/mendix/data
#   * Configure via env (DATABASE_ENDPOINT, ADMIN_PASSWORD, MXRUNTIME_*)
#   * One image per Mendix v8.x — reusable across every app at that version
#
# Why a "crate":
#   The CF-buildpack image bakes the model, so every reload spawns a new
#   image and orphans the previous one (785 MB dangling each time). This
#   crate inverts that: model is bind-mounted, image is stable, reload =
#   `docker compose restart` with zero rebuild and zero dangling images.
#
# Provenance:
#   * Built from the official Mendix CDN runtime tarball:
#     https://cdn.mendix.com/runtime/mendix-${MENDIX_VERSION}.tar.gz
#   * Java: Eclipse Temurin 11 — Mendix 8.18 LTS is certified on Java 8 and
#     Java 11. Java 11 is chosen here (Mendix Cloud's late-MX8 default; it runs
#     Java-8 bytecode fine). For an app that pins Java 8, rebuild on
#     eclipse-temurin:8-jre-jammy via --build-arg.
#   * Boot mechanism: m2ee admin protocol over HTTP (port 8090) — the same
#     protocol Mendix Cloud uses internally.

FROM --platform=linux/amd64 eclipse-temurin:11-jre-jammy

ARG MENDIX_VERSION=8.18.35.97
ARG RUNTIME_CDN_BASE=https://cdn.mendix.com/runtime
ARG USER_UID=1001

LABEL ai.ayios.purpose="Mendix 8 runtime crate (model-agnostic)"
LABEL ai.ayios.crate="mendix-8"
LABEL ai.ayios.mendix-version="${MENDIX_VERSION}"
LABEL maintainer="hardy@agileworks.co.za"

# Layer 1 — curl only. Stable across rebuilds. Lets the runtime tarball
# download (~341 MB) sit in its own layer that doesn't invalidate when
# unrelated apt deps change.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Layer 2 — Mendix runtime tarball. ~341 MB download, ~700 MB extracted.
# Cached unless MENDIX_VERSION or RUNTIME_CDN_BASE changes.
#
# Tarball top-level is `${VERSION}/`, so extracting at /opt/mendix/runtimes/
# produces the conventional CF-buildpack layout:
#     /opt/mendix/runtimes/${MENDIX_VERSION}/runtime/launcher/runtimelauncher.jar
#     /opt/mendix/runtimes/${MENDIX_VERSION}/runtime/mxclientsystem
# Identical to what the official cf-mendix-buildpack stages — m2ee +
# Mendix monitoring tools work without modification.
#
# Forward-compatible: future patch releases bake into the same image as
# additional subdirs under /opt/mendix/runtimes/, and start.sh resolves
# the right one per deployed MDA's metadata.json.
RUN set -eux; \
    mkdir -p /opt/mendix/runtimes /opt/mendix/app /opt/mendix/data; \
    echo "Downloading Mendix runtime ${MENDIX_VERSION} from ${RUNTIME_CDN_BASE}..."; \
    curl -fsSL "${RUNTIME_CDN_BASE}/mendix-${MENDIX_VERSION}.tar.gz" \
        -o /tmp/mxruntime.tar.gz; \
    echo "Extracting..."; \
    tar -xzf /tmp/mxruntime.tar.gz -C /opt/mendix/runtimes; \
    rm /tmp/mxruntime.tar.gz; \
    test -f "/opt/mendix/runtimes/${MENDIX_VERSION}/runtime/launcher/runtimelauncher.jar" || \
        (echo "FATAL: runtimelauncher.jar not found at expected path:" && \
         echo "  /opt/mendix/runtimes/${MENDIX_VERSION}/runtime/launcher/runtimelauncher.jar" && \
         echo "Tarball top-level may have changed. Inspecting:" && \
         find /opt/mendix/runtimes -maxdepth 4 -type d && exit 1); \
    echo "Mendix ${MENDIX_VERSION} runtime ready at /opt/mendix/runtimes/${MENDIX_VERSION}/"

# Layer 3 — secondary apt deps. Changes more often than the runtime tarball
# (e.g. flipping JSON parser between python3 and jq). Kept separate so
# tarball download cache survives ordinary churn.
#   fontconfig + libfreetype6 — Mendix charting / PDF rendering
#   libgomp1 — required by some native libs Mendix loads
#   jq — JSON parsing in start.sh (metadata.json + m2ee result responses).
#       Avoid python3 here: Ubuntu's --no-install-recommends + python3
#       resolves to python3-minimal which lacks the `json` stdlib module.
RUN apt-get update && apt-get install -y --no-install-recommends \
        fontconfig \
        libfreetype6 \
        libgomp1 \
        jq \
    && rm -rf /var/lib/apt/lists/*

# Crate scripts
COPY start.sh /opt/mendix/start.sh
RUN chmod +x /opt/mendix/start.sh

# Permissions for non-root user
RUN chown -R ${USER_UID}:0 /opt/mendix && chmod -R g=u /opt/mendix

USER ${USER_UID}

# Bind-mount targets.
# - /opt/mendix/app   → operator bind-mounts the unzipped MDA contents
#                       (model/, web/, native/, theme/, userlib/, etc.)
# - /opt/mendix/data  → writable file storage / DB-backed file documents
VOLUME ["/opt/mendix/app", "/opt/mendix/data"]

WORKDIR /opt/mendix/app

EXPOSE 8080 8090

# Default env values — operator overrides via docker-compose / docker run.
# An empty ADMIN_PASSWORD is rejected by start.sh; operator MUST set this.
ENV ADMIN_PASSWORD="" \
    DATABASE_ENDPOINT="" \
    MXRUNTIME_HttpHeaders="[]" \
    MX_LOG_LEVEL="i" \
    ADMIN_PORT=8090 \
    RUNTIME_PORT=8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD curl -fsS "http://localhost:8080/" >/dev/null || exit 1

ENTRYPOINT ["/opt/mendix/start.sh"]
