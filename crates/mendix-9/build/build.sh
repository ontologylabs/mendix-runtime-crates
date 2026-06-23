#!/bin/bash
# Mendix Build Crate — entrypoint. Dispatches to mxbuild / mx from the toolchain
# baked at /opt/mxtools/modeler (pulled from the Mendix CDN at image build).
#
# Commands:
#   build   <mpr-path> [mxbuild-options]   Compile an .mpr → .mda
#   check   <mpr-path> [mx-check-options]  Run `mx check` (CI-normalised exit)
#   version                                Print the mx toolchain version
#   --help                                 Usage
#
# Mount:  -v <project-dir>:/workspace   (the dir containing your App.mpr)
# Output: build writes <App>.mda into /workspace next to the .mpr.
#
# Derived from the AIDE aide-mxtools entrypoint (production-proven mxbuild
# invocation) — same find-tool + auto-inject(--java-home/--gradle-home/
# --loose-version-check) logic, retargeted at the baked /opt/mxtools/modeler.

set -euo pipefail

MXTOOLS_DIR="/opt/mxtools"

# Defensive: re-create the Mendix settings dir under whatever HOME resolves to.
# The image bakes these for HOME=/root; this covers a runtime `--user`/`-e HOME=`
# override. MX 11's .NET mxbuild FailFast-rejects creating these; harmless elsewhere. Idempotent.
mkdir -p "${HOME:-/root}/.local/share/Mendix" \
         "${HOME:-/root}/.config/Mendix" \
         "${HOME:-/root}/.cache/Mendix" 2>/dev/null || true

# find_tool <name> — locate mxbuild/mx in the baked toolchain. Strict candidates
# first (the `modeler/` layout the CDN tarball extracts to), then a glob fallback
# so a future tarball-layout change degrades gracefully instead of failing hard.
find_tool() {
    local tool_name="$1"
    for candidate in \
        "${MXTOOLS_DIR}/modeler/${tool_name}" \
        "${MXTOOLS_DIR}/${tool_name}" \
        "${MXTOOLS_DIR}/runtime/${tool_name}" \
        "${MXTOOLS_DIR}/tools/${tool_name}"; do
        if [ -x "$candidate" ]; then echo "$candidate"; return 0; fi
    done
    local found
    found=$(find "${MXTOOLS_DIR}" -name "${tool_name}" -type f -executable 2>/dev/null | head -1)
    [ -n "$found" ] && { echo "$found"; return 0; }
    return 1
}

case "${1:-}" in
    build)
        shift
        [ $# -ge 1 ] || { echo "Usage: build <mpr-path> [mxbuild-options]" >&2; exit 1; }
        MXBUILD_BIN=$(find_tool "mxbuild") || { echo "ERROR: mxbuild not found under ${MXTOOLS_DIR}" >&2; exit 1; }
        echo "Using: ${MXBUILD_BIN}" >&2

        # Auto-inject the toolchain paths mxbuild needs, unless the caller set them.
        EXTRA_ARGS=()
        HAS_JAVA_HOME=false; HAS_GRADLE_HOME=false; HAS_LOOSE=false; HAS_OUTPUT=false
        for arg in "$@"; do
            case "$arg" in
                --java-home=*)   HAS_JAVA_HOME=true ;;
                --gradle-home=*) HAS_GRADLE_HOME=true ;;
                --loose-version-check) HAS_LOOSE=true ;;
                --output=*|--output) HAS_OUTPUT=true ;;
            esac
        done
        if [ "$HAS_JAVA_HOME" = false ] && [ -n "${JAVA_HOME:-}" ]; then
            EXTRA_ARGS+=(--java-home="${JAVA_HOME}" --java-exe-path="${JAVA_HOME}/bin/java")
        fi
        if [ "$HAS_GRADLE_HOME" = false ]; then
            for g in "${MXTOOLS_DIR}/modeler/tools/gradle" "${MXTOOLS_DIR}/tools/gradle"; do
                [ -d "$g" ] && { EXTRA_ARGS+=(--gradle-home="$g"); break; }
            done
        fi
        # Tolerate patch-version drift between the toolchain and the model
        # (SDK commits may bump the model's product version).
        [ "$HAS_LOOSE" = false ] && EXTRA_ARGS+=(--loose-version-check)

        # Default the output beside the .mpr in /workspace if the caller didn't
        # pass --output. mpr-path is the first positional after `build`.
        if [ "$HAS_OUTPUT" = false ]; then
            MPR_PATH="$1"
            MPR_BASE="$(basename "${MPR_PATH%.mpr}")"
            EXTRA_ARGS+=(--output="/workspace/${MPR_BASE}.mda")
        fi

        exec "$MXBUILD_BIN" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" "$@"
        ;;

    check)
        shift
        [ $# -ge 1 ] || { echo "Usage: check <mpr-path> [mx-check-options]" >&2; exit 1; }
        MX_BIN=$(find_tool "mx") || { echo "ERROR: mx not found under ${MXTOOLS_DIR}" >&2; exit 1; }
        echo "Using: ${MX_BIN}" >&2
        # mx check returns an OR'd bitmask: 1=errors, 2=warnings, 4=deprecations.
        # Normalise to the CI convention: 0=clean, 1=errors, 2=warnings-only.
        set +e
        "$MX_BIN" check "$@"
        MX_EXIT=$?
        set -e
        if   [ $((MX_EXIT & 1)) -ne 0 ]; then exit 1
        elif [ $((MX_EXIT & 2)) -ne 0 ]; then exit 2
        else exit 0
        fi
        ;;

    version)
        # mx has no toolchain --version flag; the pinned version is the image's
        # MENDIX_VERSION. (mx show-* verbs report an *app's* version, not the toolchain's.)
        echo "Mendix build crate — toolchain version ${MENDIX_VERSION:-unknown} (mxbuild + mx)"
        ;;

    --help|help|"")
        cat <<'USAGE'
Mendix Build Crate — mxbuild + mx in a version-pinned container

Commands:
  build   <mpr-path> [options]   Compile an .mpr → .mda (output → /workspace)
  check   <mpr-path> [options]   Run mx check (exit 0=clean, 1=errors, 2=warnings)
  version                        Show the mx toolchain version

Mount:
  -v <project-dir>:/workspace    Directory containing your App.mpr

Examples:
  docker run --rm -v "$PWD":/workspace ontologylabs/mendix-mxbuild:9 build /workspace/App.mpr
  docker run --rm -v "$PWD":/workspace ontologylabs/mendix-mxbuild:9 check /workspace/App.mpr
USAGE
        ;;

    *)
        echo "Unknown command: ${1:-}" >&2
        echo "Run with --help for usage." >&2
        exit 1
        ;;
esac
