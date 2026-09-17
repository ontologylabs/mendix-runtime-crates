# Changelog — Mendix 7 Build Crate

## [0.1.1] — 2026-09-17

### Fixed — `build.sh` refuses a MAJOR-version mismatch instead of silently compiling against
### the wrong toolchain

This crate's safety model is *one image per Mendix MAJOR* — the JDK, the apt dependencies and
the toolchain are all chosen for that major. Nothing in the container checked that the `.mpr`
you handed it belonged to the same one, and `build` also auto-injects `--loose-version-check`
(which exists to tolerate PATCH drift, not a major jump). So handing an MX 7 project to the
`mendix-10` image compiled it against JDK 21 **silently**, and failed — if at all — far
downstream with no mention of Java.

* `build` and `check` now read the `.mpr`'s own `_ProductVersion` (via the `sqlite3` already in
  the image) and **exit 3** naming both versions and the image you should have used, when the
  MAJORS differ.
* **PATCH and minor drift inside the major are NOT refused** — that is what
  `--loose-version-check` is deliberately for, and an SDK commit legitimately bumps a model's
  product version.
* **An unreadable or absent `.mpr` WARNS and proceeds.** Refusing there would convert a clear
  downstream mxbuild error into a confusing upstream one.
* `MXBUILD_ALLOW_MAJOR_MISMATCH=1` permits a deliberate cross-major experiment, as an explicit
  act rather than an accident.

### Added — the guard ships its own fixture

`docker run --rm <image> selftest` runs the guard against planted inputs **inside the image**,
with no project, no network and no CDN. A guard that has never refused a fabricated input is not
a guard, so the fixture plants the cases it must REFUSE (every other major, swept — not one
hand-picked example) *and* the cases it must ADMIT (a matching major — the mirror control, run
FIRST so a refusal below cannot be measuring the fixture; patch drift; the explicit override;
and both unmeasurable shapes). Exit 0 = PASS, 1 = FAIL.

Measured 2026-09-17 on the `mendix-10` image at 10.24.22.113362: **10 arms, all PASS**, and a
real project build through the guarded entrypoint was unaffected (`BUILD SUCCEEDED`, 1m53s).

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
