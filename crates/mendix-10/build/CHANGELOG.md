# Changelog — Mendix 10 Build Crate

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

### Added — Mendix 10.24.22.113362 to the supported set

No recipe change was needed: nothing in the Dockerfile is version-specific beyond
`MENDIX_VERSION`. `docker build --build-arg MENDIX_VERSION=10.24.22.113362` produced a working
image in **2m26s** on one 40-core Linux host (Docker 29.6.1, overlayfs), of which almost all is
the **847 MB** CDN pull; `/opt/mxtools` is 1.6 GB in the finished image.

⚠ **This is the first row in this crate whose `image_smoke` actually PRODUCED AN `.mda`.** A real
~7,000-file MX 10.24.22 line-of-business project — not the vendor template — compiled end to end
to an 84 MB / 1,774-entry `.mda`, three times. Three run times on the same host and project,
stated as what they are (one host, one day, one project — an order of magnitude, not a promise):
**2m05s, 2m10s, 1m53s**.

⚠ **The second run was NOT faster than the first, and that is a property of mxbuild rather than a
measurement failure.** Its own first steps are *"Cleaning app bundle log file… Cleaning web
deployment directory…"* — it discards the deployment directory every run, so there is **no
warm-build cache to plan around**. The only cold cost worth caching is the image, once per
Mendix version.

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

Initial release. The build (mxbuild + mx) companion to the mendix-10 runtime crate.

* `Dockerfile`: model-agnostic; JDK 21 base (`eclipse-temurin:21-jdk-jammy`);
  downloads the Mendix 10 build toolchain from the official CDN at build
  (`mxbuild-${MENDIX_VERSION}.tar.gz`); never commits a Mendix binary
  (recipe-pull, D-DOCKER-LIB-001/002). apt deps for the .NET/Mono toolchain:
  `libgdiplus libicu70 libssl3 sqlite3`.
* `build.sh`: `build` / `check` / `version` dispatch. Auto-injects
  `--java-home` / `--java-exe-path` / `--gradle-home` / `--loose-version-check`
  and defaults `--output=/workspace/<App>.mda`. `mx check` exit codes normalised
  to the CI convention (0 clean / 1 errors / 2 warnings). Derived from the
  production AIDE aide-mxtools entrypoint.
* Pre-creates `$HOME/.local/share/Mendix` for the MX 10 `.NET` mxbuild whitelist
  FailFast (same fix as aide-mxtools).
* Default Mendix version: 10.24.13.86719 (override via `--build-arg MENDIX_VERSION`).

### Verification status
* CDN source `mxbuild-10.24.13.86719.tar.gz`: **HTTP 200 verified (2026-06-23)**.
* Image build + `mx version` / MDA smoke: **pending** — recorded honestly in
  `provenance.yaml` (`smoke_verified: pending`). The mxbuild invocation itself is
  the production-proven aide-mxtools path; the remaining gate is a release build.

### Why
Lets a Docker-only environment (CI, a contributor without Studio Pro) compile and
validate a Mendix 10 app, producing the `.mda` the runtime crate runs.
