---
name: container-build
description: Set up and use a headless, free, Docker-compatible container engine (Colima on macOS/Linux, Podman on Windows) instead of Docker Desktop, then build and run the Mendix runtime crates on it. Use when a machine needs a working `docker` engine, when `docker info` fails or keychain/credsStore errors block image pulls, when building the crate images (incl. linux/amd64 on Apple Silicon), or when running a crate's docker-compose smoke test.
---

# Container Build — headless engine for the Mendix runtime crates

These crates call only the plain `docker` CLI (`docker build` / `docker run` / `docker compose`), so
they run on **any** Docker-API-compatible engine — no Docker Desktop required.

## The engine, per OS

| OS | Engine | Bring-up |
|----|--------|----------|
| macOS / Linux | **Colima** (Lima-based headless docker) | `scripts/devops/bootstrap-container-engine.sh` → `colima start` |
| Windows | **Podman** (WSL2-backed, rootless; `alias docker=podman`) | `scripts/devops/bootstrap-container-engine.sh` (Git-Bash) |

## One-command bring-up (idempotent)

```bash
./scripts/devops/bootstrap-container-engine.sh
```
Detects OS; installs + starts the engine; removes Docker Desktop's `credsStore`; verifies
`docker info` (+ buildx, compose). Safe to re-run.

## Build + smoke-test a crate

```bash
cd crates/mendix-11
docker build --platform linux/amd64 --build-arg MENDIX_VERSION=11.6.4 \
    -t ontologylabs/mendix-runtime:11.6.4 .          # runtime pulled from cdn.mendix.com at build
./tests/smoke-test.sh /path/to/unzipped/mda          # brings up postgres + runtime, polls :8080
```

## Gotchas

- **Docker Desktop `credsStore` breaks headless pulls.** A leftover `"credsStore": "desktop"` (or
  `"osxkeychain"` on a headless/SSH box) in `~/.docker/config.json` makes `docker run` pulls fail with
  *"credentials ... keychain cannot be accessed"*. The bootstrap removes the `desktop` helper; anonymous
  public pulls then need no creds. **buildx/buildkit pulls bypass credsStore**, so `docker build` can
  succeed while `docker run` fails — that's the tell.
- **`--platform linux/amd64` on Apple Silicon** runs under QEMU emulation (correct, slower). For fast
  native amd64 builds, run on an x86_64 host or use a remote `docker buildx` builder pointed at one.
- **Colima restart drops a named buildkit builder** — recreate it with `docker buildx create` if a
  `buildx build --builder <name>` suddenly fails.
- **Autostart vs a manually-started Colima.** `brew services start colima` can't take ownership while a
  hand-started `colima` holds the VM (launchd error 5). The engine is still usable; for boot autostart,
  one-time: `colima stop && brew services start colima`.
- **Windows/Podman.** Use `alias docker=podman` and `podman compose ...`; validate a crate's smoke test
  on Podman before relying on it (compose + `docker.sock` paths have edge cases).
