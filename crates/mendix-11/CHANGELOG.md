# Changelog — Mendix 11 Runtime Crate

## [0.1.0] — 2026-05-06

Initial release.

* New `crates/mendix-11/` directory in the delivery distribution
* Dockerfile: model-agnostic, downloads Mendix 11.x runtime from CDN at build,
  bind-mount target at `/opt/mendix/app`. Cache-friendly layering — apt deps
  changes don't invalidate the 341 MB tarball download.
* `start.sh`: m2ee admin protocol entrypoint with DB-wait, DDL-sync retry,
  configurable HTTP headers, DEVELOPMENT_MODE bypass. Pure shell + jq, no Python.
* Default Mendix version: 11.6.4 (override via `--build-arg MENDIX_VERSION=...`)
* Forward-compatible: future patch versions bake into the same image as
  additional `/opt/mendix/runtimes/<version>/` subdirs; start.sh resolves the
  right one per deployed MDA's metadata.json.
* Image size: ~785 MB (deduplicated layer storage)
* Verified fixtures (2026-05-06):
  * **Claudius** (certification reference app): 24 s boot, HTTP 200,
    REST API live with real data, Phase 3 schema preserved across container swap
  * **ExpenseWorks-main** (independent fresh v11.6.4 app): 15 s boot,
    HTTP 200, runtime started cleanly. Same crate image, different ProjectID,
    isolated postgres — confirms the crate is genuinely "any v11 app".
* `build-server.sh` integration:
  * `crate-build [version]` — build the crate image (idempotent — skips if cached)
  * `crate-reload` — switch existing compose stack onto the crate (no docker build)
  * `crate-versions` — list built crate images
* Compose integration: `docker-compose.yml` extended with optional bind-mount
  + parameterized container ports. Buildpack flow (legacy) unchanged; crate
  flow opts in via env vars set by `crate-reload`.

### Result vs. legacy buildpack image
| | CF-buildpack | This crate |
|---|---|---|
| Disk per reload | ~785 MB dangling | 0 |
| Reload mechanism | `docker build --no-cache` | `compose restart` |
| Reload time | 4-8 min | ~10-30 s |
| Reusable across apps | no | yes |
| Dangling images after 10 reloads | ~7.5 GB | 0 |

### Known issues
* Mendix 11.6.4 logs `"Unknown configuration setting 'HttpHeaders'"` at
  startup. The default empty `[]` is harmless (no custom headers wired) but
  custom CSP setups need the right v11 config-key name (TODO: verify
  `HttpResponseHeaders` or similar; tracked as a follow-up).

### Why
Replaces the dangling-image-per-reload anti-pattern of the CF-buildpack
runtime image. See `README.md` § "Why this exists".
