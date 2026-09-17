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
# override. MX 11 mxbuild (.NET) FailFast-rejects creating these itself. Idempotent.
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

# ── MAJOR-VERSION GUARD (added 2026-09-17) ───────────────────────────────────────────────
# WHY. This crate's safety model is "one image per Mendix MAJOR": the JDK, the apt deps and
# the toolchain are all chosen for that major, and NOTHING in the container checked that the
# .mpr you handed it belongs to the same one. Because `build` also auto-injects
# `--loose-version-check` (which exists to tolerate PATCH drift, not a major jump), feeding an
# MX 7 project to the mendix-10 image compiled it against JDK 21 **silently** and failed, if at
# all, somewhere far downstream with no mention of Java.
#
# A silent substitution is the failure worth refusing: a build that ran against the wrong
# toolchain and produced *something* costs more than one that stopped and said why.
#
# WHAT IT DOES NOT DO. It does not second-guess the PATCH version — that is exactly what
# `--loose-version-check` is for, and an SDK commit legitimately bumps a model's product
# version. It only refuses a MAJOR mismatch, and `MXBUILD_ALLOW_MAJOR_MISMATCH=1` makes a
# deliberate cross-major experiment possible as an explicit act.
#
# WHAT IT DOES WHEN IT CANNOT MEASURE. It WARNS and proceeds. An unreadable `.mpr` is a
# different failure and mxbuild itself will report it properly; refusing here would convert a
# clear downstream error into a confusing upstream one.
mpr_major() {
    # Echo the .mpr's Mendix MAJOR version, or nothing when it cannot be read.
    local mpr="${1:-}" v=""
    command -v sqlite3 >/dev/null 2>&1 || return 0
    [ -f "$mpr" ] || return 0
    v="$(sqlite3 "$mpr" 'SELECT _ProductVersion FROM _MetaData' 2>/dev/null || true)"
    [ -n "$v" ] || return 0
    printf '%s' "${v%%.*}"
}

assert_major_match() {
    local mpr="${1:-}"
    local img_major="${MENDIX_VERSION%%.*}"
    local proj_major
    proj_major="$(mpr_major "$mpr")"
    [ -n "$img_major" ] || return 0
    if [ -z "$proj_major" ]; then
        echo "WARNING: could not read _ProductVersion from '${mpr}' (no sqlite3, missing file," \
             "or not a Mendix .mpr). Proceeding with this image's Mendix ${img_major} toolchain" \
             "UNCHECKED. If the build fails on a Java or model-format error, that is why." >&2
        return 0
    fi
    if [ "$proj_major" = "$img_major" ]; then
        return 0
    fi
    if [ "${MXBUILD_ALLOW_MAJOR_MISMATCH:-0}" = "1" ]; then
        echo "WARNING: project is Mendix ${proj_major}, this image carries the Mendix" \
             "${img_major} toolchain (${MENDIX_VERSION}). Proceeding because" \
             "MXBUILD_ALLOW_MAJOR_MISMATCH=1 was set deliberately." >&2
        return 0
    fi
    echo "ERROR: MAJOR VERSION MISMATCH. The project is Mendix ${proj_major}; this image" >&2
    echo "       carries the Mendix ${img_major} build toolchain (${MENDIX_VERSION})." >&2
    echo "       Use the matching image — ontologylabs/mendix-mxbuild:${proj_major} — or an" >&2
    echo "       exact tag for your project's version. Compiling across a major would pick the" >&2
    echo "       wrong JDK and the wrong model format, and --loose-version-check (injected for" >&2
    echo "       PATCH drift) would not stop it." >&2
    echo "       Deliberate cross-major experiment: set MXBUILD_ALLOW_MAJOR_MISMATCH=1." >&2
    exit 3
}

case "${1:-}" in
    build)
        shift
        [ $# -ge 1 ] || { echo "Usage: build <mpr-path> [mxbuild-options]" >&2; exit 1; }
        assert_major_match "$1"
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
        assert_major_match "$1"
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


    selftest)
        # ⚠ THE GUARD'S OWN FIXTURE. A guard that has never refused a fabricated input is not a
        # guard — so this plants one of each case, INCLUDING the ones it must admit, and runs
        # entirely inside the image with no project, no network and no CDN.
        #   docker run --rm ontologylabs/mendix-mxbuild:<tag> selftest
        command -v sqlite3 >/dev/null 2>&1 || { echo "selftest needs sqlite3" >&2; exit 1; }
        d="$(mktemp -d)"; fails=0
        plant() {  # plant <name> <product-version>
            rm -f "${d}/$1.mpr"
            sqlite3 "${d}/$1.mpr" \
                "CREATE TABLE _MetaData (_ProductVersion TEXT); \
                 INSERT INTO _MetaData VALUES ('$2');"
        }
        ck() { if [ "$1" = "yes" ]; then echo "  ok   $2"; else echo "  FAIL $2"; fails=$((fails+1)); fi; }
        img_major="${MENDIX_VERSION%%.*}"
        echo "=== build.sh major-version guard — self-test (image major ${img_major}) ==="

        # MIRROR FIRST — a MATCHING project is ADMITTED. If this fails, every refusal below is
        # measuring the fixture rather than the guard.
        plant match "${img_major}.99.99.99999"
        if ( assert_major_match "${d}/match.mpr" ) >/dev/null 2>&1; then r=yes; else r=no; fi
        ck "$r" "MIRROR: a project of this image's own major is ADMITTED"

        # REFUSED — every other major, swept, not one hand-picked example.
        for m in 7 8 9 10 11 12; do
            [ "$m" = "$img_major" ] && continue
            plant "m${m}" "${m}.1.2.3"
            if ( assert_major_match "${d}/m${m}.mpr" ) >/dev/null 2>&1; then r=no; else r=yes; fi
            ck "$r" "REFUSED: a Mendix ${m} project is refused by the Mendix ${img_major} image"
        done

        # ADMITTED — PATCH drift within the major is NOT the guard's business; refusing it
        # would break the --loose-version-check contract this crate deliberately offers.
        plant patch "${img_major}.0.0.1"
        if ( assert_major_match "${d}/patch.mpr" ) >/dev/null 2>&1; then r=yes; else r=no; fi
        ck "$r" "ADMITTED: patch/minor drift inside the major is not refused"

        # ADMITTED WITH A WARNING — a deliberate cross-major experiment.
        other=7; [ "$img_major" = "7" ] && other=11
        plant other "${other}.1.2.3"
        if ( MXBUILD_ALLOW_MAJOR_MISMATCH=1 assert_major_match "${d}/other.mpr" ) >/dev/null 2>&1
        then r=yes; else r=no; fi
        ck "$r" "ADMITTED: MXBUILD_ALLOW_MAJOR_MISMATCH=1 permits a deliberate cross-major run"

        # ADMITTED WITH A WARNING — unmeasurable input. WARN, never a hard refusal the guard
        # cannot justify: mxbuild reports a corrupt .mpr far better than this can.
        if ( assert_major_match "${d}/does-not-exist.mpr" ) >/dev/null 2>&1; then r=yes; else r=no; fi
        ck "$r" "ADMITTED: an unreadable/absent .mpr WARNS and proceeds"
        : > "${d}/empty.mpr"
        if ( assert_major_match "${d}/empty.mpr" ) >/dev/null 2>&1; then r=yes; else r=no; fi
        ck "$r" "ADMITTED: a file that is not a Mendix .mpr WARNS and proceeds"

        rm -rf "$d"
        if [ "$fails" -gt 0 ]; then echo "=== FAIL (${fails}) ==="; exit 1; fi
        echo "=== PASS ==="
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
  selftest                       Run the major-version guard's own fixture

Mount:
  -v <project-dir>:/workspace    Directory containing your App.mpr

Examples:
  docker run --rm -v "$PWD":/workspace ontologylabs/mendix-mxbuild:11 build /workspace/App.mpr
  docker run --rm -v "$PWD":/workspace ontologylabs/mendix-mxbuild:11 check /workspace/App.mpr
USAGE
        ;;

    *)
        echo "Unknown command: ${1:-}" >&2
        echo "Run with --help for usage." >&2
        exit 1
        ;;
esac
