#!/usr/bin/env bash
# Smoke test for the Mendix 8 runtime crate.
#
# Brings up postgres + the crate against an MDA placed at $1 (or
# ./tests/mda/). Polls http://localhost:8080/ for HTTP 200, then tears
# down. Exits 0 on pass, non-zero on fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CRATE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.smoke.yml"
MDA_SOURCE="${1:-${SCRIPT_DIR}/mda}"

if [ ! -f "${MDA_SOURCE}/model/metadata.json" ]; then
    echo "[FATAL] No MDA at ${MDA_SOURCE}/model/metadata.json"
    echo "        Pass an unzipped MDA path as the first argument, e.g.:"
    echo "          $0 ${CRATE_DIR}/../../docker/mendix-buildpack/project"
    exit 78
fi

# If the MDA isn't already at ./tests/mda/, symlink it so docker-compose
# can pick up the relative path.
if [ "${MDA_SOURCE}" != "${SCRIPT_DIR}/mda" ]; then
    rm -rf "${SCRIPT_DIR}/mda"
    ln -s "${MDA_SOURCE}" "${SCRIPT_DIR}/mda"
fi

PROJECT_NAME="mendix-crate-smoke"

trap 'echo "Tearing down..."; docker compose -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" down -v 2>/dev/null || true' EXIT

echo "=== Smoke test: bringing up postgres + mendix-runtime ==="
docker compose -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" up -d

# Large apps under amd64 emulation need well over 180 s for first-boot DDL
# sync. Override with SMOKE_TIMEOUT=<seconds> if needed.
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-420}"
echo "=== Polling http://localhost:8080/ (timeout ${SMOKE_TIMEOUT} s) ==="
START=$(date +%s)
HEALTHY=0
while [ $(($(date +%s) - START)) -lt "${SMOKE_TIMEOUT}" ]; do
    if curl -fsS -o /dev/null -w "%{http_code}" "http://localhost:8080/" 2>/dev/null | grep -q "200"; then
        HEALTHY=1
        break
    fi
    sleep 5
done

if [ "${HEALTHY}" = "1" ]; then
    echo "=== PASS — runtime healthy at http://localhost:8080/ ==="
    exit 0
fi

echo "=== FAIL — runtime never responded HTTP 200 within 180 s ==="
echo "=== Last 50 lines of runtime logs: ==="
docker compose -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" logs --tail 50 mendix-runtime
exit 1
