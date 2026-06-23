# Changelog — Mendix 7 Build Crate

## [0.1.0] — 2026-06-23

Initial release. The build (mxbuild + mx) companion to the mendix-7 runtime crate.

* `Dockerfile`: model-agnostic; JDK 8 base (`eclipse-temurin:8-jdk-jammy`);
  downloads the Mendix 7 build toolchain from the official CDN at build
  (`mxbuild-${MENDIX_VERSION}.tar.gz`); never commits a Mendix binary
  (recipe-pull, D-DOCKER-LIB-001/002). apt deps for the .NET/Mono toolchain:
  `libgdiplus libicu70 libssl3 sqlite3`.
* `build.sh`: `build` / `check` / `version` dispatch. Auto-injects
  `--java-home` / `--java-exe-path` / `--gradle-home` / `--loose-version-check`
  and defaults `--output=/workspace/<App>.mda`. `mx check` exit codes normalised
  to the CI convention (0 clean / 1 errors / 2 warnings). Derived from the
  production AIDE aide-mxtools entrypoint.
* Pre-creates `$HOME/.local/share/Mendix` for the MX 7 `.NET` mxbuild whitelist
  FailFast (same fix as aide-mxtools).
* Default Mendix version: 7.23.8.58888 (override via `--build-arg MENDIX_VERSION`).

### Verification status
* CDN source `mxbuild-7.23.8.58888.tar.gz`: **HTTP 200 verified (2026-06-23)**.
* Image build + `mx version` / MDA smoke: **pending** — recorded honestly in
  `provenance.yaml` (`smoke_verified: pending`). The mxbuild invocation itself is
  the production-proven aide-mxtools path; the remaining gate is a release build.

### Why
Lets a Docker-only environment (CI, a contributor without Studio Pro) compile and
validate a Mendix 7 app, producing the `.mda` the runtime crate runs.
