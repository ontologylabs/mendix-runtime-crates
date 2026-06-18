# Mendix 9 Runtime Crate

> A model-agnostic, app-agnostic, version-pinned Docker image for running
> any Mendix 9.x application. Bind-mount your unzipped MDA, set a few env
> vars, get a working Mendix runtime. Zero rebuilds, zero dangling images.

## Why this exists

The official `cf-mendix-buildpack` Docker pattern bakes the application
model directly into the image. Every model change spawns a new image and
orphans the previous one — typically ~785 MB of dangling layers per
reload. For an iterative dev/test loop that runs reload many times per
day, this consumes tens of GB of disk in a single working session.

This crate inverts the pattern:

| | CF-buildpack image | This crate |
|---|---|---|
| Mendix runtime files | baked | baked |
| JRE | baked | baked |
| Application model | **baked** | **bind-mounted** |
| Reload mechanism | `docker build --no-cache` | `docker compose restart` |
| Disk cost per reload | ~785 MB (dangling) | 0 |
| Image-per-Mendix-version | many (one per app commit) | 1 |
| Reusable across apps | no | yes |

Same Mendix version → same image. Multiple apps at the same version → one
image, multiple bind-mounts.

## Image tags

| Tag | What it pins | When to use |
|---|---|---|
| `ontologylabs/mendix-runtime:9.24.20.33307` | Exact version (immutable) | Production, repeatable builds |
| `ontologylabs/mendix-runtime:9.24` | Latest 9.24 patch in this crate | Pinned minor line |
| `ontologylabs/mendix-runtime:9` | Latest 9.x in this crate's release stream | Dev, demo, easy upgrades |

Related crates:

* `ontologylabs/mendix-runtime:11.x` — Mendix 11 (see `../mendix-11`)
* `ontologylabs/mendix-runtime:10.x` — Mendix 10 (see `../mendix-10`)

## Build

```bash
cd "$(git rev-parse --show-toplevel)"/delivery/crates/mendix-9   # or: cd <delivery-root>/crates/mendix-9
docker build \
    --platform linux/amd64 \
    --build-arg MENDIX_VERSION=9.24.20.33307 \
    -t ontologylabs/mendix-runtime:9.24.20.33307 \
    -t ontologylabs/mendix-runtime:9.24 \
    -t ontologylabs/mendix-runtime:9 \
    .
```

The base image is `eclipse-temurin:11-jre-jammy`. **Mendix 9.24 requires
JDK 11** — JDK 21 is incompatible (the 9.x toolchain's bundled gradle 7.6.3
throws `Unsupported class file major version 65`). Mendix 9 runtime files
are downloaded from `https://cdn.mendix.com/runtime/mendix-${VERSION}.tar.gz`
during build.

## Run

### docker run (single-shot)

```bash
docker run -d \
    --name figwarehouse-runtime \
    -p 8080:8080 \
    -p 8090:8090 \
    -v /path/to/unzipped/mda:/opt/mendix/app:ro \
    -v figwarehouse-data:/opt/mendix/data \
    -e DATABASE_ENDPOINT="postgres://mendix:mendix@db:5432/mendix" \
    -e ADMIN_PASSWORD="strong-password-here" \
    -e DEVELOPMENT_MODE="true" \
    --link postgres:db \
    ontologylabs/mendix-runtime:9.24.20.33307
```

### docker compose (recommended)

See `tests/docker-compose.smoke.yml` for a runnable example.

## Required environment

| Variable | Purpose | Example |
|---|---|---|
| `ADMIN_PASSWORD` | m2ee admin protocol password (also rejects weak runtime passwords) | `MyStrongPass2026!` |
| `DATABASE_ENDPOINT` | PostgreSQL URL (parsed for host/port/user/pass/db) | `postgres://mendix:mendix@postgres:5432/mendix` |

## Optional environment

| Variable | Default | Purpose |
|---|---|---|
| `DEVELOPMENT_MODE` | `false` | If `true`, force DTAPMode=D (bypasses project-security checks like `CheckFormsAndMicroflows`) |
| `DTAPMode` | `D` | One of `D`/`A`/`P` |
| `ADMIN_PORT` | `8090` | m2ee admin protocol HTTP port |
| `RUNTIME_PORT` | `8080` | Mendix client HTTP port |
| `MX_LOG_LEVEL` | `i` | One of `t`/`d`/`i`/`w`/`e` |
| `MXRUNTIME_HttpHeaders` | `[]` | JSON array of `{"Name":"...","Value":"..."}` for CSP / custom headers |
| `MICROFLOW_CONSTANTS` | `{}` | JSON object of `{"Module.Constant":"value"}` |
| `JAVA_OPTS` | `-Xmx1g -Xms512m -Dfile.encoding=UTF-8` | JVM flags |
| `DB_HOST` `DB_PORT` `DB_NAME` `DB_USER` `DB_PASS` | parsed from `DATABASE_ENDPOINT` if set | DB connection (used only if `DATABASE_ENDPOINT` is unset) |

## Bind-mount contract

| Container path | Type | Required | Purpose |
|---|---|---|---|
| `/opt/mendix/app` | volume / bind | **yes** | Unzipped MDA contents (must contain `model/metadata.json`) |
| `/opt/mendix/data` | volume / bind | recommended | Writable file storage (file documents, model uploads) |

The MDA is what `unzip your.mda -d /path/...` produces — a directory with
`model/`, `web/`, `userlib/`, `theme/`, `native/`, `sass/`, `tmp/` at top
level.

## Ports

| Port | Purpose |
|---|---|
| 8080 | Mendix client (HTTP) |
| 8090 | m2ee admin protocol — JSON-RPC over HTTP, password = `ADMIN_PASSWORD`, base64-encoded in `X-M2EE-Authentication` header |

## Health

```bash
curl -fsSI http://localhost:8080/    # 200 OK once runtime is up
```

The container's `HEALTHCHECK` polls `http://localhost:8080/` every 30 s.

## Security notes

* Runs as UID 1001 (non-root, OpenShift-compatible).
* `ADMIN_PASSWORD` must be set explicitly — the runtime rejects weak passwords
  like `1` or `password` with a null-pointer-exception in `PasswordStrengthVerifier`.
* In production, mount the MDA `:ro` so the container cannot mutate it.

## Testing

`tests/smoke-test.sh` brings up postgres + this image with a known-good MDA,
hits `/`, and tears down. CI-able.

## Provenance

Built from the official Mendix CDN runtime tarball. No upstream Mendix code
is forked or modified. JRE is upstream Eclipse Temurin. Boot mechanism
(`runtimelauncher.jar` + m2ee admin protocol) is the same protocol Mendix
Cloud uses internally. Each built image records its CDN source URL, Mendix
version, crate version, and image digest in `provenance.yaml`.

## Versioning

This crate (the Dockerfile + start.sh + supporting files) is versioned
independently of the Mendix runtime. See `CHANGELOG.md`.

## License

Apache 2.0 for the crate scaffolding (Dockerfile, start.sh, README, tests).
The Mendix runtime files baked into the image are subject to Mendix's own
license — see https://www.mendix.com/terms-of-use/ .
