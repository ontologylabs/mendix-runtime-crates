# Changelog — Mendix 10 Runtime Crate

## [0.1.0] — 2026-06-18

Initial release. Replicates the mendix-11 crate pattern for Mendix 10.x
(DOCKER-LIB-01).

* Dockerfile: model-agnostic; downloads the Mendix 10.24 runtime from the
  official CDN at build (`mendix-${MENDIX_VERSION}.tar.gz`); bind-mount target
  at `/opt/mendix/app`; mxbuild never baked (recipe-pull model, D-DOCKER-LIB-001).
* **JDK 21**: Mendix 10.24 LTS supports JDK 21. Base image
  `eclipse-temurin:21-jre-jammy` (same as mendix-11).
* `start.sh`: m2ee admin protocol entrypoint with DB-wait, DDL-sync retry,
  DEVELOPMENT_MODE bypass. Auto-builds `MicroflowConstants` from the deployed
  model's `metadata.json` defaults (operator `MICROFLOW_CONSTANTS` env overrides).
* Default Mendix version: 10.24.13.86719 (override via `--build-arg MENDIX_VERSION`).
* Image size: ~1.14 GB. Image digest `sha256:d5f96dcd…` (see `provenance.yaml`).
* Verified fixture (2026-06-18):
  * **AdviserMarketplace / EFG** (large production app, model RuntimeVersion
    10.24.13.86719): HTTP 200, runtime healthy. Booted with **91** model-default
    constants auto-supplied and **9,647** DDL synchronization commands executed
    on first run. Run under amd64 emulation with `SMOKE_TIMEOUT=1200`.

### Notes
* `HttpHeaders` config key logs "Unknown configuration setting" — harmless
  (no custom headers wired by default), same as MX9/11.
* Smoke poll timeout is configurable via `SMOKE_TIMEOUT` (default 420 s). Large
  production apps under amd64 emulation (e.g. EFG, ~10 min first-boot DDL)
  exceed both the original hard-coded 180 s and the 420 s default — pass a
  larger value.

### Why
Replaces the dangling-image-per-reload anti-pattern of the CF-buildpack runtime
image for Mendix 10.x apps. See `README.md` § "Why this exists".
