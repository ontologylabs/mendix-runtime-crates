# Changelog — Mendix 11 Build Crate

## [0.1.0] — 2026-06-23

Initial release. The build (mxbuild + mx) companion to the mendix-11 runtime crate.

* `Dockerfile`: model-agnostic; JDK 21 base (`eclipse-temurin:21-jdk-jammy`);
  downloads the Mendix 11 build toolchain from the official CDN at build
  (`mxbuild-${MENDIX_VERSION}.tar.gz`); never commits a Mendix binary
  (recipe-pull, D-DOCKER-LIB-001/002). apt deps for the .NET/Mono toolchain:
  `libgdiplus libicu70 libssl3 sqlite3`.
* `build.sh`: `build` / `check` / `version` dispatch. Auto-injects
  `--java-home` / `--java-exe-path` / `--gradle-home` / `--loose-version-check`
  and defaults `--output=/workspace/<App>.mda`. `mx check` exit codes normalised
  to the CI convention (0 clean / 1 errors / 2 warnings). Derived from the
  production AIDE aide-mxtools entrypoint.
* Pre-creates `$HOME/.local/share/Mendix` for the MX 11 `.NET` mxbuild whitelist
  FailFast (same fix as aide-mxtools).
* Default Mendix version: 11.6.4 (override via `--build-arg MENDIX_VERSION`).

### Verification status (2026-06-23)
* CDN source `mxbuild-11.6.4.tar.gz`: **HTTP 200 verified**.
* **Image build verified**: builds clean (exit 0, ~650 MB, linux/amd64 under
  Colima); the recipe-pull curl of the toolchain from the CDN succeeds;
  `modeler/{mxbuild,mx,tools/gradle}` resolve at `/opt/mxtools/modeler`;
  `build.sh` runs (`version` → `11.6.4`, unknown-command errors); the `mx`
  binary executes under emulation.
* **Full MDA compile smoke: pending** — a real `.mpr → .mda` build needs a
  licensed MX11 project; recorded honestly in `provenance.yaml`
  (`smoke_verified: pending`). The mxbuild invocation is the production-proven
  aide-mxtools path.

### Why
Lets a Docker-only environment (CI, a contributor without Studio Pro) compile and
validate a Mendix 11 app, producing the `.mda` the runtime crate runs.
