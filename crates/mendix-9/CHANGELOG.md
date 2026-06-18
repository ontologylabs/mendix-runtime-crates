# Changelog — Mendix 9 Runtime Crate

## [0.1.0] — 2026-06-18

Initial release. Replicates the mendix-11 crate pattern for Mendix 9.x
(DOCKER-LIB-01).

* Dockerfile: model-agnostic; downloads the Mendix 9.24 runtime from the
  official CDN at build (`mendix-${MENDIX_VERSION}.tar.gz`); bind-mount target
  at `/opt/mendix/app`; mxbuild never baked (recipe-pull model, D-DOCKER-LIB-001).
* **JDK 11, not 21**: Mendix 9.24 is incompatible with JDK 21 (its bundled
  gradle 7.6.3 throws `Unsupported class file major version 65`). Base image
  `eclipse-temurin:11-jre-jammy`.
* `start.sh`: m2ee admin protocol entrypoint with DB-wait, DDL-sync retry,
  DEVELOPMENT_MODE bypass. **Auto-builds `MicroflowConstants` from the deployed
  model's `metadata.json` defaults** — the MX9 runtime does NOT auto-apply model
  defaults when the field is absent (verified on FigWarehouse: omitting it
  yields "Could not find value for constant 'MoneyworksDatabase.Devkey'").
  Operator `MICROFLOW_CONSTANTS` env overrides.
* Default Mendix version: 9.24.20.33307 (override via `--build-arg MENDIX_VERSION`).
* Image size: ~846 MB. Image digest `sha256:c89844a0…` (see `provenance.yaml`).
* Verified fixture (2026-06-18):
  * **FigWarehouse** (native mobile app, model RuntimeVersion 9.24.20.33307):
    HTTP 200, runtime healthy. Booted with 10 model-default constants
    auto-supplied (incl. the nested-JSON `GPubSub.EnabledSubscriptions`).

### Notes
* `HttpHeaders` config key logs "Unknown configuration setting" — harmless
  (no custom headers wired by default), same as MX10/11.
* Smoke poll timeout is configurable via `SMOKE_TIMEOUT` (default 420 s); large
  apps under amd64 emulation exceed the original hard-coded 180 s.

### Why
Replaces the dangling-image-per-reload anti-pattern of the CF-buildpack runtime
image for Mendix 9.x apps. See `README.md` § "Why this exists".
