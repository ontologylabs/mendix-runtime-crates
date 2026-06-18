# Changelog — Mendix 7 Runtime Crate

## [0.1.0] — 2026-06-18

Initial release. Replicates the mendix-11 crate pattern for Mendix 7.x
(DOCKER-LIB-01). Oldest supported major.

* Dockerfile: model-agnostic; downloads the Mendix 7.23 runtime from the
  official CDN at build (`mendix-${MENDIX_VERSION}.tar.gz`); bind-mount target
  at `/opt/mendix/app`; mxbuild never baked (recipe-pull model, D-DOCKER-LIB-001).
* **JDK 8**: Mendix 7.x targets Java 8. Base image `eclipse-temurin:8-jre-jammy`.
* **Boot-path parity confirmed**: the build-time assertion
  `test -f .../7.23.8.58888/runtime/launcher/runtimelauncher.jar` passes — MX7
  (2017-era) uses the same `runtimelauncher.jar` + m2ee admin protocol as
  MX9/10/11, so `start.sh` is unchanged across majors.
* `start.sh`: m2ee admin protocol entrypoint with DB-wait, DDL-sync retry,
  DEVELOPMENT_MODE bypass. Auto-builds `MicroflowConstants` from the deployed
  model's `metadata.json` defaults (operator `MICROFLOW_CONSTANTS` env overrides).
* Default Mendix version: 7.23.8.58888 (override via `--build-arg MENDIX_VERSION`).
* Image size: ~582 MB (smallest of the crate family — JDK 8 + MX7 runtime).
  Image digest `sha256:a5b4a6cb…` (see `provenance.yaml`).
* Verified fixture (2026-06-18):
  * **MoneyWorksPortal** (model RuntimeVersion 7.23.8.58888): HTTP 200, runtime
    healthy. Model-default constants auto-supplied.

### Notes
* `HttpHeaders` config key is not recognised on MX7 — the default empty `[]`
  logs "Unknown configuration setting" and is harmlessly ignored.
* Smoke poll timeout is configurable via `SMOKE_TIMEOUT` (default 420 s).

### Why
Replaces the dangling-image-per-reload anti-pattern of the CF-buildpack runtime
image for Mendix 7.x apps. See `README.md` § "Why this exists".
