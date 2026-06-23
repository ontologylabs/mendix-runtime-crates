# Changelog — Mendix 8 Runtime Crate

## [0.1.0] — 2026-06-23

Initial release. Replicates the mendix-9 runtime crate pattern for Mendix 8.x.

* `Dockerfile`: model-agnostic; downloads the Mendix 8 runtime from the official
  CDN at build (`mendix-${MENDIX_VERSION}.tar.gz`); bind-mount target at
  `/opt/mendix/app`; no Mendix binary committed (recipe-pull, D-DOCKER-LIB-001/002).
* **Java 11 base** (`eclipse-temurin:11-jre-jammy`): Mendix 8.18 LTS is certified
  on Java 8 and Java 11; Java 11 is chosen (Mendix Cloud's late-MX8 default; runs
  Java-8 bytecode). Rebuild on Temurin 8 via `--build-arg` for a Java-8-pinned app.
* `start.sh`: m2ee admin protocol entrypoint with DB-wait, DDL-sync retry,
  DEVELOPMENT_MODE bypass; auto-builds `MicroflowConstants` from the deployed
  model's `metadata.json` defaults (operator `MICROFLOW_CONSTANTS` env overrides).
  Identical boot path to the mendix-9/10/11 crates.
* Default Mendix version: **8.18.35.97** (the final 8.18 LTS patch; override via
  `--build-arg MENDIX_VERSION`).

### Verification status (2026-06-23)
* CDN source `mendix-8.18.35.97.tar.gz`: **HTTP 200 verified**.
* Image build + MDA smoke: **pending** — no MX8 fixture app in the corpus yet;
  recorded honestly in `provenance.yaml` (`smoke_verified: pending`). The boot
  path is shared, verbatim, with the smoke-verified mendix-9 runtime crate.

### Mendix 8 support
* MX8 is **out of standard Mendix support**. The default `8.18.35.97` is still
  CDN-hosted, so it builds with no extra steps. Older MX8 patches are not all on
  the CDN (e.g. `8.18.21.4259` → 404) — for those, see
  [`PORTAL-DOWNLOAD.md`](PORTAL-DOWNLOAD.md).

### Why
Replaces the dangling-image-per-reload anti-pattern of the CF-buildpack runtime
image for Mendix 8.x apps, and completes the 7–11 version coverage. See
`README.md` § "Why this exists".
