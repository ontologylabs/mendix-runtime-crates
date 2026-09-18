# Changelog — Mendix 9 Build Crate

## [0.1.3] — 2026-09-18

### Verified — this crate's FIRST `.mda`-producing smoke on Mendix 9, at a newer patch

* The Edubond V2 fixture (matching this crate's own runtime-crate `planned:` entry,
  `crates/mendix-9/versions.yaml`) at Mendix `9.24.36.73625` - a real, full-content project
  (javasource 1,677 files / theme 197 / widgets 52 / userlib 301) - compiled end to end:
  `BUILD SUCCEEDED`, a 180 MB / 4,020-entry `.mda`, 124s wall. Verified as a real zip archive
  containing `model/model.mdp`, zip integrity checked (`testzip()` clean), not just a non-zero
  exit. See `versions.yaml` for the full measurement.
* This closes the `[0.1.2]` entry's "not yet closed" for the *build* half of this major — the
  prior row's 9.24.20.33307 attempt (against a locally incomplete project) stands unchanged,
  beside this one, not over it: two different projects, two different verdicts, same crate.
* **Found only by enumerating the checkout rather than globbing for "the" `.mpr`.** This project's
  own directory carries three `.mpr` files, two of them zero bytes (`App.mpr`, a
  space-named `Edubond V2.mpr`). `find … -name '*.mpr' | head -1` picks a decoy and reads as an
  unusable, content-empty checkout — this is exactly what made this same checkout look empty on
  first inspection this pass, before it was enumerated by content rather than by name. Staged a
  clean copy that excludes both decoys before handing it to `scripts/ops/mxbuild-oracle.sh`, so
  the oracle's own `find … | head -1` could not repeat the mistake.

## [0.1.2] — 2026-09-18

### Documented — `mx check` confirmed available; first live `image_smoke` attempt, not yet closed

* **`check` is present on this major** — verified via `docker run --entrypoint
  /opt/mxtools/modeler/mx <image> --help`: `check`, `convert`, `create-project`,
  `update-widgets`, `collect-native-deps`, `show-version` are all listed. This is the first
  major (7 → 9) where `check` actually exists in the CDN toolchain; see the mendix-7/mendix-8
  changelogs for where it does not.
* **First live `image_smoke` attempt, not yet closed.** The compile ran against a project whose
  `theme/`, `resources/` and `javasource/` directories were all locally empty. mxbuild reported
  a real verdict — 1,336+ cascading errors (its own display cap), a mix of missing pluggable
  widgets and "Design property X is not supported by your theme" for every styled element with
  no theme to check against — not a toolchain or mount defect (the bind-mount sentinel proof
  passed first). See `versions.yaml` for the full account.

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

Initial release. The build (mxbuild + mx) companion to the mendix-9 runtime crate.

* `Dockerfile`: model-agnostic; JDK 11 base (`eclipse-temurin:11-jdk-jammy`);
  downloads the Mendix 9 build toolchain from the official CDN at build
  (`mxbuild-${MENDIX_VERSION}.tar.gz`); never commits a Mendix binary
  (recipe-pull, D-DOCKER-LIB-001/002). apt deps for the .NET/Mono toolchain:
  `libgdiplus libicu70 libssl3 sqlite3`.
* `build.sh`: `build` / `check` / `version` dispatch. Auto-injects
  `--java-home` / `--java-exe-path` / `--gradle-home` / `--loose-version-check`
  and defaults `--output=/workspace/<App>.mda`. `mx check` exit codes normalised
  to the CI convention (0 clean / 1 errors / 2 warnings). Derived from the
  production AIDE aide-mxtools entrypoint.
* Pre-creates `$HOME/.local/share/Mendix` for the MX 9 `.NET` mxbuild whitelist
  FailFast (same fix as aide-mxtools).
* Default Mendix version: 9.24.20.33307 (override via `--build-arg MENDIX_VERSION`).

### Verification status
* CDN source `mxbuild-9.24.20.33307.tar.gz`: **HTTP 200 verified (2026-06-23)**.
* Image build + `mx version` / MDA smoke: **pending** — recorded honestly in
  `provenance.yaml` (`smoke_verified: pending`). The mxbuild invocation itself is
  the production-proven aide-mxtools path; the remaining gate is a release build.

### Why
Lets a Docker-only environment (CI, a contributor without Studio Pro) compile and
validate a Mendix 9 app, producing the `.mda` the runtime crate runs.
