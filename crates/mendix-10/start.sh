#!/bin/bash
# Mendix 10 Runtime Crate — entrypoint
#
# Boot sequence:
#   1. Validate inputs (DB endpoint reachable, ADMIN_PASSWORD set, MDA mounted).
#   2. Launch runtimelauncher.jar (the JVM) — it opens admin port 8090 first.
#   3. Wait for admin port to become healthy.
#   4. Drive m2ee admin protocol: configure logging → app container → DB +
#      runtime config → start.
#   5. If start returns non-zero (e.g. DDL sync needed on first run), execute
#      execute_ddl_commands and retry start.
#
# Trap SIGTERM/SIGINT to forward to the JVM for clean shutdown.

set -euo pipefail

APP_DIR="/opt/mendix/app"
RUNTIMES_DIR="/opt/mendix/runtimes"
DATA_DIR="/opt/mendix/data"
ADMIN_PORT="${ADMIN_PORT:-8090}"
RUNTIME_PORT="${RUNTIME_PORT:-8080}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
MX_LOG_LEVEL="${MX_LOG_LEVEL:-i}"

echo "============================================================"
echo "  Mendix 10 Runtime Crate"
echo "  ontologylabs/mendix-runtime"
echo "  App: ${APP_DIR}    Runtimes: ${RUNTIMES_DIR}"
echo "============================================================"

# --- Input validation (fail loudly with actionable messages) -----------------

if [ -z "${ADMIN_PASSWORD}" ]; then
    echo "[FATAL] ADMIN_PASSWORD env var is unset or empty."
    echo "        Set it via docker-compose env or `docker run -e ADMIN_PASSWORD=...`"
    echo "        (The Mendix runtime rejects weak passwords like '1' or 'password')"
    exit 78
fi

if [ ! -f "${APP_DIR}/model/metadata.json" ]; then
    echo "[FATAL] No MDA model found at ${APP_DIR}/model/metadata.json"
    echo "        The crate expects an unzipped MDA bind-mounted at ${APP_DIR}."
    echo "        On the host: unzip your.mda -d /path/to/project/ &&"
    echo "                     docker run -v /path/to/project:/opt/mendix/app ..."
    exit 78
fi

DEPLOYED_VERSION=$(jq -r '.RuntimeVersion // "unknown"' \
    "${APP_DIR}/model/metadata.json" 2>/dev/null || echo "unknown")

# List the Mendix runtime versions baked into this crate. The expected layout is
# /opt/mendix/runtimes/<version>/runtime/launcher/runtimelauncher.jar — one
# subdirectory per supported version. The crate ships with at least one.
BAKED_VERSIONS=$(ls "${RUNTIMES_DIR}/" 2>/dev/null | sort -V)
echo "Deployed model RuntimeVersion: ${DEPLOYED_VERSION}"
echo "Crate baked versions:          $(echo "${BAKED_VERSIONS}" | tr '\n' ' ')"

# Resolve the runtime path. Strict match first; then fall back to a same-major
# match if the deployed patch isn't baked (Mendix runtime is patch-stable
# within a major across small ranges).
RUNTIME_DIR=""
if [ -d "${RUNTIMES_DIR}/${DEPLOYED_VERSION}/runtime" ]; then
    RUNTIME_DIR="${RUNTIMES_DIR}/${DEPLOYED_VERSION}/runtime"
    RESOLVED_VERSION="${DEPLOYED_VERSION}"
else
    DEPLOYED_MAJOR="${DEPLOYED_VERSION%%.*}"
    for v in ${BAKED_VERSIONS}; do
        if [ "${v%%.*}" = "${DEPLOYED_MAJOR}" ]; then
            RUNTIME_DIR="${RUNTIMES_DIR}/${v}/runtime"
            RESOLVED_VERSION="${v}"
            echo "[WARN] Exact runtime ${DEPLOYED_VERSION} not baked. Falling back to same-major ${v}."
            break
        fi
    done
fi

if [ -z "${RUNTIME_DIR}" ] || [ ! -f "${RUNTIME_DIR}/launcher/runtimelauncher.jar" ]; then
    echo "[FATAL] No baked Mendix runtime matches deployed model version ${DEPLOYED_VERSION}."
    echo "        Baked versions: $(echo "${BAKED_VERSIONS}" | tr '\n' ' ')"
    echo "        Either rebuild the crate with --build-arg MENDIX_VERSION=${DEPLOYED_VERSION}"
    echo "        or bake additional versions into the crate image."
    exit 78
fi

echo "Resolved runtime: ${RUNTIME_DIR}"

# m2ee admin protocol expects MX_INSTALL_PATH to point at the runtime root
# (the dir containing `runtime/`). The launcher reads MX_INSTALL_PATH to
# locate runtime classes, mxclientsystem assets, and the launcher's own jar.
export MX_INSTALL_PATH="${RUNTIMES_DIR}/${RESOLVED_VERSION}"
export M2EE_ADMIN_PORT="${ADMIN_PORT}"
export M2EE_ADMIN_PASS="${ADMIN_PASSWORD}"

# Writable dirs the runtime expects under APP_DIR. We ensure these exist on
# the bind-mounted volume, but writes here only persist if the operator
# bind-mounts a real writable host path or a docker volume.
mkdir -p "${APP_DIR}/data/database" \
         "${APP_DIR}/data/files" \
         "${APP_DIR}/data/tmp" \
         "${APP_DIR}/data/model-upload" \
         2>/dev/null || true

# --- Database wait -----------------------------------------------------------

DB_HOST_DEFAULT="postgres"
DB_PORT_DEFAULT="5432"

if [ -n "${DATABASE_ENDPOINT:-}" ]; then
    # Parse postgres://user:pass@host:port/db into vars we'll use below.
    # Parse postgres://[user[:pass]@]host[:port][/db] in pure shell. The
    # regex-based form below is sufficient for the canonical postgres URL
    # shape; we fall back to defaults for any field that doesn't match.
    # No external JSON/URL parser needed — keeps the crate dependency-free
    # beyond curl + jq.
    URL="${DATABASE_ENDPOINT#*://}"            # strip scheme
    URL_USERINFO=""
    if [[ "${URL}" == *"@"* ]]; then
        URL_USERINFO="${URL%%@*}"
        URL="${URL#*@}"
    fi
    URL_HOSTPORT="${URL%%/*}"
    URL_PATH=""
    [[ "${URL}" == */* ]] && URL_PATH="${URL#*/}"

    DB_HOST="${URL_HOSTPORT%%:*}"
    if [[ "${URL_HOSTPORT}" == *:* ]]; then
        DB_PORT="${URL_HOSTPORT##*:}"
    else
        DB_PORT="${DB_PORT_DEFAULT}"
    fi
    DB_NAME="${URL_PATH%%[?&]*}"
    [ -z "${DB_NAME}" ] && DB_NAME="mendix"

    if [ -n "${URL_USERINFO}" ]; then
        DB_USER="${URL_USERINFO%%:*}"
        if [[ "${URL_USERINFO}" == *:* ]]; then
            DB_PASS="${URL_USERINFO#*:}"
        else
            DB_PASS="mendix"
        fi
    else
        DB_USER="mendix"
        DB_PASS="mendix"
    fi
    [ -z "${DB_HOST}" ] && DB_HOST="${DB_HOST_DEFAULT}"
else
    DB_HOST="${DB_HOST:-${DB_HOST_DEFAULT}}"
    DB_PORT="${DB_PORT:-${DB_PORT_DEFAULT}}"
    DB_NAME="${DB_NAME:-mendix}"
    DB_USER="${DB_USER:-mendix}"
    DB_PASS="${DB_PASS:-mendix}"
fi

echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}..."
DB_READY=0
for _ in $(seq 1 60); do
    if timeout 2 bash -c "echo > /dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then
        DB_READY=1
        break
    fi
    sleep 2
done
if [ "${DB_READY}" != "1" ]; then
    echo "[FATAL] PostgreSQL did not become reachable at ${DB_HOST}:${DB_PORT} after 120s."
    exit 75
fi
echo "PostgreSQL ready."

# --- Launch runtimelauncher.jar ---------------------------------------------

# Java options can be overridden via JAVA_OPTS; sane defaults for dev/demo.
JAVA_OPTS="${JAVA_OPTS:--Xmx1g -Xms512m -Dfile.encoding=UTF-8}"

echo "Starting JVM (m2ee admin port ${ADMIN_PORT}, app port ${RUNTIME_PORT})..."
# shellcheck disable=SC2086
java ${JAVA_OPTS} \
    -jar "${RUNTIME_DIR}/launcher/runtimelauncher.jar" \
    "${APP_DIR}" &
JVM_PID=$!

trap "echo 'Shutting down...'; kill ${JVM_PID} 2>/dev/null; wait ${JVM_PID} 2>/dev/null; exit 0" SIGTERM SIGINT

# --- Wait for admin port -----------------------------------------------------

AUTH_B64=$(echo -n "${ADMIN_PASSWORD}" | base64)

m2ee() {
    # JSON-RPC-ish over HTTP to the m2ee admin port. Body is
    # {"action":"<name>","params":<json>}. Returns the raw response body.
    curl -s "http://[::1]:${ADMIN_PORT}/" \
        -H "Content-Type: application/json" \
        -H "X-M2EE-Authentication: ${AUTH_B64}" \
        -d "{\"action\":\"$1\",\"params\":$2}"
}

ADMIN_READY=0
for _ in $(seq 1 60); do
    if curl -sf "http://[::1]:${ADMIN_PORT}/" \
        -H "Content-Type: application/json" \
        -H "X-M2EE-Authentication: ${AUTH_B64}" \
        -d '{"action":"runtime_status","params":{}}' >/dev/null 2>&1; then
        ADMIN_READY=1
        break
    fi
    if ! kill -0 ${JVM_PID} 2>/dev/null; then
        echo "[FATAL] JVM exited before admin port came up. Check logs above."
        exit 70
    fi
    sleep 2
done
if [ "${ADMIN_READY}" != "1" ]; then
    echo "[FATAL] m2ee admin port ${ADMIN_PORT} did not respond after 120s."
    kill ${JVM_PID} 2>/dev/null || true
    exit 71
fi
echo "Admin port ready."

# --- Configure + start via m2ee --------------------------------------------

JDBC="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"
HTTP_HEADERS="${MXRUNTIME_HttpHeaders:-[]}"
DTAP_MODE="${DTAPMode:-D}"

# MICROFLOW_CONSTANTS — JSON object of {"Module.Constant": "value"} that
# overrides defaults baked into the model. Empty (or unset) means we DO
# NOT send a MicroflowConstants update, so the runtime falls back to the
# model's defaultValue for each constant. Sending an empty object {} in
# update_configuration would clobber those defaults — verified empirically
# (Claudius `FeedbackModule.LocalStorageKey` returned "Could not find
# value for constant" with `MicroflowConstants:{}`).
#
# Resolution order:
#   1. Operator-supplied MICROFLOW_CONSTANTS env (validated JSON) — highest
#      precedence; lets operators override any value.
#   2. Otherwise, build the constants map from the deployed model's OWN default
#      values (metadata.json Constants[].DefaultValue). The MX runtime does NOT
#      auto-apply model defaults when MicroflowConstants is absent — that is the
#      cf-buildpack's job. Verified on MX9 (FigWarehouse): omitting the field
#      yields "Could not find value for constant 'MoneyworksDatabase.Devkey'"
#      even though the model declares a default. Building from metadata makes
#      the crate self-sufficient (it boots any app whose constants have model
#      defaults, with zero operator config). Values are the string forms Mendix
#      stores; the runtime coerces each per its declared type.
CONSTANTS_OPTIONAL_FIELD=""
CONSTANTS_JSON=""
if [ -n "${MICROFLOW_CONSTANTS:-}" ] && [ "${MICROFLOW_CONSTANTS}" != "{}" ]; then
    # Validate JSON shape before sending — bad JSON would fail
    # update_configuration silently and produce confusing downstream errors.
    if echo "${MICROFLOW_CONSTANTS}" | jq -e . >/dev/null 2>&1; then
        CONSTANTS_JSON="${MICROFLOW_CONSTANTS}"
        echo "Applying operator-supplied MICROFLOW_CONSTANTS overrides."
    else
        echo "[WARN] MICROFLOW_CONSTANTS is set but not valid JSON. Falling back to model defaults."
    fi
fi
if [ -z "${CONSTANTS_JSON}" ] && [ -f "${APP_DIR}/model/metadata.json" ]; then
    CONSTANTS_JSON=$(jq -c '[.Constants[]? | select(.DefaultValue != null) | {(.Name): (.DefaultValue|tostring)}] | add // {}' \
        "${APP_DIR}/model/metadata.json" 2>/dev/null || echo "{}")
    NCONST=$(echo "${CONSTANTS_JSON}" | jq 'length' 2>/dev/null || echo 0)
    [ "${NCONST:-0}" -gt 0 ] && echo "Applying ${NCONST} model-default constant value(s) from metadata.json."
fi
if [ -n "${CONSTANTS_JSON}" ] && [ "${CONSTANTS_JSON}" != "{}" ] && [ "${CONSTANTS_JSON}" != "null" ]; then
    CONSTANTS_OPTIONAL_FIELD=",\"MicroflowConstants\":${CONSTANTS_JSON}"
fi

# Optional development-mode bypass — set DEVELOPMENT_MODE=true to relax
# project-security checks (CheckFormsAndMicroflows / CheckEverything).
# Mendix 11 with strict project security refuses to load under DTAP=A/P
# unless DEVELOPMENT_MODE is explicitly set.
if [ "${DEVELOPMENT_MODE:-false}" = "true" ]; then
    DTAP_MODE="D"
fi

# 1. Logging — wire a console subscriber at INFO so JVM logs appear on stdout.
m2ee create_log_subscriber \
    '{"name":"ConsoleSubscriber","type":"console","autosubscribe":"INFO"}' >/dev/null
m2ee start_logging '{}' >/dev/null

# 2. App container — bind to the runtime port on all addresses.
m2ee update_appcontainer_configuration \
    "{\"runtime_port\":${RUNTIME_PORT},\"runtime_listen_addresses\":\"*\"}" >/dev/null

# 3. Full configuration — DB, paths, optional constants, custom HTTP headers.
# MicroflowConstants is omitted entirely if MICROFLOW_CONSTANTS is unset or
# empty — see CONSTANTS_OPTIONAL_FIELD construction above.
m2ee update_configuration "{\
\"DatabaseType\":\"POSTGRESQL\",\
\"DatabaseJdbcUrl\":\"${JDBC}\",\
\"DatabaseHost\":\"${DB_HOST}:${DB_PORT}\",\
\"DatabaseName\":\"${DB_NAME}\",\
\"DatabaseUserName\":\"${DB_USER}\",\
\"DatabasePassword\":\"${DB_PASS}\",\
\"DTAPMode\":\"${DTAP_MODE}\",\
\"ScheduledEventExecution\":\"NONE\",\
\"EnableFileDocumentCaching\":false,\
\"BasePath\":\"${APP_DIR}\",\
\"MxClientSystemPath\":\"${RUNTIME_DIR}/mxclientsystem\",\
\"RuntimePath\":\"${RUNTIME_DIR}\"${CONSTANTS_OPTIONAL_FIELD},\
\"HttpHeaders\":${HTTP_HEADERS}\
}" >/dev/null

# 4. Start. autocreatedb=true creates schema on first run; subsequent starts
# return code=0 unless schema needs DDL (e.g. after model change adds an
# entity). On non-zero we run execute_ddl_commands and retry.
echo "Starting Mendix runtime..."
m2ee start '{"autocreatedb":true}' >/tmp/start_result.json 2>/dev/null
CODE=$(jq -r '.result // 99' /tmp/start_result.json 2>/dev/null || echo "99")

if [ "${CODE}" != "0" ]; then
    echo "Initial start returned code=${CODE}. Running DDL sync and retrying..."
    m2ee execute_ddl_commands '{}' >/tmp/ddl_result.json 2>/dev/null || true
    DDL_RESULT=$(cat /tmp/ddl_result.json 2>/dev/null || echo '{}')
    echo "DDL: ${DDL_RESULT}"
    m2ee start '{"autocreatedb":true}' >/tmp/start_result.json 2>/dev/null
    CODE=$(jq -r '.result // 99' /tmp/start_result.json 2>/dev/null || echo "99")
fi

if [ "${CODE}" = "0" ]; then
    echo "============================================================"
    echo "  RUNTIME READY"
    echo "  App:   http://0.0.0.0:${RUNTIME_PORT}/"
    echo "  Admin: http://0.0.0.0:${ADMIN_PORT}/  (m2ee protocol)"
    echo "============================================================"
else
    REASON=$(jq -r '
        (.feedback.startup_metrics.reason // .message // "unknown")
    ' /tmp/start_result.json 2>/dev/null || echo "unknown")
    echo "[ERROR] Mendix start failed (code=${CODE}): ${REASON}"
    echo "[ERROR] Inspect /tmp/start_result.json inside the container for full payload."
fi

# Block on the JVM. SIGTERM/SIGINT trap (above) forwards to the JVM.
wait ${JVM_PID}
