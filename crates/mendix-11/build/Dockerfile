# Mendix 11 Build Crate — model-agnostic mxbuild + mx toolchain (recipe-pull).
#
# Image: ontologylabs/mendix-mxbuild:11
#        ontologylabs/mendix-mxbuild:11.6.4 (immutable)
#
# Contract:
#   * Bake: JDK 21 + the Mendix 11.x build toolchain (mxbuild + mx), pulled from
#     the official Mendix CDN at `docker build` time.
#   * NEVER commit a Mendix binary to the repo. The toolchain tarball is curl'd
#     from cdn.mendix.com on the licensed user's own machine — exactly like the
#     runtime crate downloads the runtime tarball (D-DOCKER-LIB-001 recipe-pull;
#     D-DOCKER-LIB-002 no-binaries guard). You bring the licensed toolchain; we
#     bring the build recipe.
#   * Bind-mount the project directory (containing the `.mpr`) at /workspace.
#   * Compile : `docker run -v <proj>:/workspace ... build /workspace/App.mpr`
#               → writes App.mda next to the .mpr in /workspace.
#   * Validate: `docker run -v <proj>:/workspace ... check /workspace/App.mpr`
#               → `mx check` with CI-normalised exit codes (0 clean / 1 error / 2 warn).
#
# Why a "build crate" (companion to the runtime crate):
#   The AIDE pipeline drives mxbuild via a bind-mounted Studio Pro modeler
#   (the aide-mxtools image). This crate makes the toolchain self-contained and
#   version-pinned: one image per Mendix major, the matching mxbuild fetched
#   from the CDN at build, so a contributor with only Docker can compile any app
#   at that version without a local Studio Pro install. Runtime crate runs the
#   app; build crate produces the .mda the runtime crate runs.
#
# Provenance:
#   * mxbuild + mx from https://cdn.mendix.com/runtime/mxbuild-${MENDIX_VERSION}.tar.gz
#   * Tarball top-level is `modeler/` → modeler/mxbuild, modeler/mx,
#     modeler/tools/gradle (verified against the AIDE build-server cache layout).
#   * Java: Eclipse Temurin 21 JDK — Mendix 11 compiles Java actions at release 21.
#     A full JDK (not JRE) is required: mxbuild invokes javac to compile the
#     app's javasource and Java actions.

FROM --platform=linux/amd64 eclipse-temurin:21-jdk-jammy

ARG MENDIX_VERSION=11.6.4
ARG MXBUILD_CDN_BASE=https://cdn.mendix.com/runtime

LABEL ai.ayios.purpose="Mendix 11 build crate (mxbuild + mx, model-agnostic)"
LABEL ai.ayios.crate="mendix-11/build"
LABEL ai.ayios.mendix-version="${MENDIX_VERSION}"
LABEL maintainer="hardy@agileworks.co.za"

# Layer 1 — apt deps for the mxbuild toolchain. mxbuild is a .NET/Mono program:
#   libgdiplus — System.Drawing (image/PDF generation during build)
#   libicu70   — globalization/ICU (jammy ships ICU 70)
#   libssl3    — TLS for any build-time fetch
#   sqlite3    — read the .mpr (modern Mendix projects are SQLite databases)
#   curl       — pull the toolchain tarball
# Stable layer; survives churn in the heavier toolchain layer below.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        libgdiplus \
        libicu70 \
        libssl3 \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Layer 2 — Mendix build toolchain tarball (mxbuild + mx). ~300-500 MB download.
# Recipe-pull: curl'd from the CDN at build, never committed. Cached unless
# MENDIX_VERSION or MXBUILD_CDN_BASE changes.
#
# Tarball top-level is `modeler/`, so extracting at /opt/mxtools produces the
# same layout the AIDE build-server caches and mounts at /opt/mxtools:
#     /opt/mxtools/modeler/mxbuild
#     /opt/mxtools/modeler/mx
#     /opt/mxtools/modeler/tools/gradle
RUN set -eux; \
    mkdir -p /opt/mxtools /workspace; \
    echo "Downloading Mendix build toolchain ${MENDIX_VERSION} from ${MXBUILD_CDN_BASE}..."; \
    curl -fsSL "${MXBUILD_CDN_BASE}/mxbuild-${MENDIX_VERSION}.tar.gz" -o /tmp/mxbuild.tar.gz; \
    echo "Extracting..."; \
    tar -xzf /tmp/mxbuild.tar.gz -C /opt/mxtools; \
    rm /tmp/mxbuild.tar.gz; \
    test -f /opt/mxtools/modeler/mxbuild || { \
        echo "FATAL: modeler/mxbuild not found at expected path /opt/mxtools/modeler/mxbuild."; \
        echo "Tarball top-level may have changed. Inspecting:"; \
        find /opt/mxtools -maxdepth 3 -type f -name 'mx*'; \
        exit 1; \
    }; \
    chmod +x /opt/mxtools/modeler/mxbuild /opt/mxtools/modeler/mx 2>/dev/null || true; \
    echo "Mendix ${MENDIX_VERSION} build toolchain ready at /opt/mxtools/modeler/"

# MX 11 mxbuild (.NET) creates its modeler settings under
# $HOME/.local/share/Mendix via GetFolderPath(LocalApplicationData). In a fresh
# container that directory does not exist, and mxbuild's WhitelistAware
# filesystem FailFast-rejects *creating* it ("UnauthorizedAccessException …
# EnsurePathSafety") before the build starts. Pre-create it for HOME=/root so
# mxbuild writes its settings without tripping the create-time whitelist check.
# (Empirically proven in the AIDE aide-mxtools image.)
RUN mkdir -p /root/.local/share/Mendix /root/.config/Mendix /root/.cache/Mendix

# Crate entrypoint.
COPY build.sh /opt/mxtools/build.sh
RUN chmod +x /opt/mxtools/build.sh

# Runs as root by design — an ephemeral, single-shot build container (not a
# long-running service). Root avoids the bind-mount uid-mismatch that would
# otherwise block writing the produced .mda back into the operator's mounted
# /workspace. On a Linux host where root-owned output is undesirable, pass
# `--user $(id -u)`; build.sh defensively re-creates the Mendix settings dir
# under whatever $HOME resolves to.
ENV JAVA_HOME=/opt/java/openjdk \
    MENDIX_VERSION=${MENDIX_VERSION}

VOLUME ["/workspace"]
WORKDIR /workspace

ENTRYPOINT ["/opt/mxtools/build.sh"]
CMD ["--help"]
