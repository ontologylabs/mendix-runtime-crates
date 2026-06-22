#!/usr/bin/env bash
# bootstrap-container-engine.sh — OS-aware, idempotent setup of a headless,
# free, Docker-API-compatible container engine. Replaces Docker Desktop.
#
#   macOS / Linux  ->  Colima (Lima-based headless docker)
#   Windows        ->  Podman (WSL2-backed, rootless; `docker` shim)
#
# The baseline is an ABSTRACTION — "a headless, free, Docker-compatible engine".
# These crates call only the plain `docker` CLI, so once this script reports
# `docker info` green, `docker build` / `docker compose` and the crate smoke
# tests run unchanged on any of the engines above.
#
# Idempotent: safe to re-run. Verifies `docker info` (+ buildx, compose) at the
# end and exits non-zero if the engine is not actually usable. Vendor this file
# into your own repo and extend it locally as needed.
set -euo pipefail

# ---------------------------------------------------------------------------
# output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''; C_RST=''
fi
log()  { printf '%s[engine]%s %s\n' "$C_DIM" "$C_RST" "$*"; }
ok()   { printf '%s[ ok  ]%s %s\n' "$C_OK"  "$C_RST" "$*"; }
warn() { printf '%s[warn ]%s %s\n' "$C_WARN" "$C_RST" "$*" >&2; }
die()  { printf '%s[fail ]%s %s\n' "$C_ERR" "$C_RST" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
detect_os() {
  local s
  s="$(uname -s 2>/dev/null || echo unknown)"
  case "$s" in
    Darwin) echo macos ;;
    Linux)
      # WSL presents as Linux but the *host* is Windows; the in-WSL engine is
      # still a Linux engine, so treat WSL as Linux here. The Windows branch is
      # for native Windows shells (Git-Bash / MSYS) driving Podman.
      echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *)
      [ "${OS:-}" = "Windows_NT" ] && { echo windows; return; }
      echo "unknown:$s" ;;
  esac
}

# ---------------------------------------------------------------------------
# shared: strip Docker Desktop's credsStore (breaks headless engines —
# the `docker-credential-desktop` helper is absent without Desktop).
# ---------------------------------------------------------------------------
strip_creds_store() {
  local cfg="${HOME}/.docker/config.json"
  [ -f "$cfg" ] || return 0
  grep -q '"credsStore"[[:space:]]*:[[:space:]]*"desktop"' "$cfg" 2>/dev/null || return 0
  log "removing Docker Desktop credsStore from ${cfg} (breaks headless auth)"
  if have python3; then
    python3 - "$cfg" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    cfg = json.load(f)
if cfg.get("credsStore") == "desktop":
    cfg.pop("credsStore", None)
    with open(p, "w") as f:
        json.dump(cfg, f, indent=2)
    print("  credsStore removed")
PY
  else
    warn "python3 absent; edit ${cfg} by hand and delete the \"credsStore\": \"desktop\" line"
  fi
}

# ---------------------------------------------------------------------------
# macOS — Colima
# ---------------------------------------------------------------------------
setup_macos() {
  have brew || die "Homebrew required on macOS. Install: https://brew.sh then re-run."

  local pkg
  for pkg in colima docker docker-buildx docker-compose; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      ok "$pkg already installed"
    else
      log "brew install $pkg"
      brew install "$pkg"
    fi
  done

  # buildx/compose are CLI plugins; link them into the docker cli-plugins dir so
  # `docker buildx` / `docker compose` resolve without Docker Desktop.
  local plugdir="${HOME}/.docker/cli-plugins"
  mkdir -p "$plugdir"
  local bx cp brewpfx
  brewpfx="$(brew --prefix)"
  bx="${brewpfx}/opt/docker-buildx/bin/docker-buildx"
  cp="${brewpfx}/opt/docker-compose/bin/docker-compose"
  [ -x "$bx" ] && ln -sf "$bx" "${plugdir}/docker-buildx"
  [ -x "$cp" ] && ln -sf "$cp" "${plugdir}/docker-compose"

  strip_creds_store

  # Autostart check. brew colorizes 'started' under a TTY, which would defeat a
  # plain whitespace anchor — strip ANSI, then match the status field exactly.
  colima_service_started() {
    local esc; esc=$(printf '\033')
    brew services list 2>/dev/null \
      | sed "s/${esc}\[[0-9;]*m//g" \
      | awk '$1=="colima" && $2=="started"{f=1} END{exit !f}'
  }

  if colima status >/dev/null 2>&1; then
    ok "Colima already running"
    if colima_service_started; then
      ok "Colima enrolled in brew services (autostart)"
    else
      # Up via a manual `colima start` — launchd can't take ownership of a held
      # VM (bootstrap error 5). Don't stop a running engine; just inform.
      warn "autostart not configured: a manually-started Colima holds the VM."
      warn "  one-time fix (engine restarts): colima stop && brew services start colima"
    fi
  else
    # Down — start THROUGH brew services so the same step also enrols autostart
    # (no manual/launchd ownership conflict). Fall back to a direct start.
    log "starting Colima via brew services (starts + enrols autostart)"
    if brew services start colima >/dev/null 2>&1 && colima_service_started; then
      ok "Colima started and enrolled in brew services (autostart)"
    else
      log "brew services start unavailable — starting Colima directly"
      colima start
      warn "autostart not configured. For boot autostart: colima stop && brew services start colima"
    fi
  fi

  docker context use colima >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Linux — prefer an already-working native dockerd; else Colima via brew.
# (Native Docker Engine is the sane headless engine on Linux; Colima adds a VM
# layer that is only worth it for parity with macOS. We don't force a VM here.)
# ---------------------------------------------------------------------------
setup_linux() {
  strip_creds_store
  if docker info >/dev/null 2>&1; then
    ok "native docker engine already usable on Linux"
    return 0
  fi
  if have colima; then
    colima status >/dev/null 2>&1 || { log "starting Colima"; colima start; }
    return 0
  fi
  warn "no usable docker engine found. Install one of:"
  warn "  - Docker Engine (CE):  https://docs.docker.com/engine/install/  (recommended on Linux)"
  warn "  - Colima:              brew install colima docker  (if you want macOS parity)"
  die  "re-run this script once a Linux docker engine is installed."
}

# ---------------------------------------------------------------------------
# Windows — Podman (WSL2-backed, rootless). Run from Git-Bash / MSYS.
# Cannot be fully validated from a non-Windows host; this guides + best-effort
# automates via winget when present.
# ---------------------------------------------------------------------------
setup_windows() {
  log "Windows engine = Podman (WSL2-backed, rootless)."
  if have podman; then
    ok "podman present"
  elif have winget; then
    log "winget install RedHat.Podman"
    winget install -e --id RedHat.Podman || warn "winget install failed; install Podman Desktop manually: https://podman.io"
  else
    warn "Podman not found and winget unavailable."
    warn "Install Podman Desktop (https://podman.io) or run in PowerShell: winget install RedHat.Podman"
    die  "re-run this script after Podman is installed."
  fi

  # Initialise + start a Podman machine (the WSL2 backend) if not yet running.
  if podman machine list --format '{{.Running}}' 2>/dev/null | grep -qi true; then
    ok "podman machine running"
  else
    podman machine inspect >/dev/null 2>&1 || { log "podman machine init"; podman machine init || true; }
    log "podman machine start"
    podman machine start || warn "could not start podman machine; start it from Podman Desktop"
  fi

  cat <<'EOF'
[engine] To make `docker ...` commands work against Podman, add to your shell profile:
           alias docker=podman
         and (PowerShell, for tools that read the var):
           podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}'
           $env:DOCKER_HOST = "npipe:////./pipe/docker_engine"   # or the Podman socket
         Compose: `podman compose ...` (podman-compose) is the drop-in for `docker compose`.
EOF
}

# ---------------------------------------------------------------------------
# verification gate — the engine must actually be usable
# ---------------------------------------------------------------------------
verify() {
  have docker || { warn "docker CLI not on PATH (Windows/Podman: use \`podman\` or set the alias)"; return 0; }
  log "verifying engine (docker info)..."
  if ! docker info >/dev/null 2>&1; then
    die "docker info failed — the engine is installed but not reachable. Check the engine is started."
  fi
  local summary
  summary="$(docker info --format '{{.ServerVersion}} / {{.OperatingSystem}} / {{.Architecture}}' 2>/dev/null || echo '?')"
  ok "engine reachable: ${summary}"
  if docker buildx version >/dev/null 2>&1; then ok "buildx: $(docker buildx version 2>/dev/null | head -1)"; else warn "docker buildx missing (multi-arch builds unavailable)"; fi
  if docker compose version >/dev/null 2>&1; then ok "compose: $(docker compose version 2>/dev/null | head -1)"; else warn "docker compose missing (compose smoke tests unavailable)"; fi
}

# ---------------------------------------------------------------------------
main() {
  local os; os="$(detect_os)"
  log "detected OS: ${os}"
  case "$os" in
    macos)   setup_macos ;;
    linux)   setup_linux ;;
    windows) setup_windows ;;
    *)       die "unsupported/unknown OS: ${os}. Supported: macOS, Linux, Windows." ;;
  esac
  verify
  ok "container engine baseline ready."
}
main "$@"
