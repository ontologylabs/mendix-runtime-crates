#!/usr/bin/env bash
# Smoke test for the Mendix 11 build crate.
#
# Compiles a Mendix 11 project (.mpr) into an .mda using the build-crate image,
# then asserts the .mda was produced. Exits 0 on pass, non-zero on fail.
#
# Usage:   ./smoke-test.sh /path/to/project/App.mpr
#
# You supply the licensed .mpr — none is committed to this repo (guard.sh blocks
# .mpr/.mda/.tar.gz patterns; D-DOCKER-LIB-002). The image's mxbuild toolchain is
# pulled from the Mendix CDN at `docker build`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MENDIX_VERSION="${MENDIX_VERSION:-11.6.4}"
IMAGE="${BUILD_IMAGE:-ontologylabs/mendix-mxbuild:${MENDIX_VERSION}}"

MPR_PATH="${1:-}"
if [ -z "${MPR_PATH}" ] || [ ! -f "${MPR_PATH}" ]; then
    echo "[FATAL] Pass the path to a Mendix 11 .mpr as the first argument."
    echo "        e.g. $0 /path/to/MyApp/MyApp.mpr"
    exit 78
fi

# Colima mounts only \$HOME into the VM; a project outside \$HOME is invisible to
# the container. Warn rather than silently mount an empty dir.
case "${MPR_PATH}" in
    "${HOME}"/*) : ;;
    *) echo "[WARN] ${MPR_PATH} is not under \$HOME — on Colima it may be invisible to the container." ;;
esac

PROJECT_DIR="$(cd "$(dirname "${MPR_PATH}")" && pwd)"
MPR_NAME="$(basename "${MPR_PATH}")"
MDA_NAME="$(basename "${MPR_NAME%.mpr}").mda"

# Build the image if absent.
if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "=== Building image ${IMAGE} (mxbuild pulled from CDN) ==="
    docker build --platform linux/amd64 \
        --build-arg MENDIX_VERSION="${MENDIX_VERSION}" \
        -t "${IMAGE}" "${BUILD_DIR}"
fi

echo "=== Compiling ${MPR_NAME} → ${MDA_NAME} ==="
rm -f "${PROJECT_DIR}/${MDA_NAME}"
docker run --rm --platform linux/amd64 \
    -v "${PROJECT_DIR}:/workspace" \
    "${IMAGE}" \
    build "/workspace/${MPR_NAME}"

if [ -f "${PROJECT_DIR}/${MDA_NAME}" ]; then
    SIZE=$(du -h "${PROJECT_DIR}/${MDA_NAME}" | cut -f1)
    echo "=== PASS — ${MDA_NAME} produced (${SIZE}) ==="
    exit 0
fi

echo "=== FAIL — ${MDA_NAME} was not produced. Inspect mxbuild output above. ==="
exit 1
