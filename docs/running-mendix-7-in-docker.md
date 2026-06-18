# Running Mendix 7 in Docker

**Mendix 7.23** shipped in 2017 and runs on **Java 8**. It is long out of mainstream support, but plenty of organisations still maintain production Mendix 7 apps — and getting one to *run locally* for testing, debugging, CI, or a migration spike is painful: the official tooling assumes Studio Pro on Windows, the cloud buildpack bakes your model into a throwaway image, and the modern Mendix Docker guidance simply doesn't cover a runtime this old.

The **`mendix-7` runtime crate** solves this. It is a model-agnostic, version-pinned Docker image that boots *any* Mendix 7.x application you bind-mount into it — no Studio Pro, no model baked into the image, no Mendix binaries committed to source control.

> **TL;DR**
> ```bash
> cd crates/mendix-7
> docker build --platform linux/amd64 --build-arg MENDIX_VERSION=7.23.8.58888 \
>   -t ontologylabs/mendix-runtime:7 .
> unzip your-mx7-app.mda -d ./tests/mda
> docker compose -f tests/docker-compose.smoke.yml up   # → http://localhost:8080
> ```

## What you get

* **Java 8 + the Mendix 7.23 runtime**, pulled from `cdn.mendix.com` at build time (never committed).
* **Your model bind-mounted**, not baked — `docker compose restart` to reload, with zero dangling images.
* A **PostgreSQL-backed** runtime driven entirely through the **m2ee admin protocol** — the same protocol Mendix Cloud and `m2ee-tools` use against production Mendix 7 servers.
* Verified: this crate boots **MoneyWorksPortal 7.23.8** to a healthy **HTTP 200**.

## Prerequisites

* Docker (Docker Desktop on macOS/Windows, or any engine on Linux).
* An **unzipped MDA** of your Mendix 7 app — a directory containing `model/metadata.json`. (An `.mda` is just a zip; `unzip your.mda -d ./app/`.)
* That's it. No Studio Pro, no Windows, no Mendix account.

## Step 1 — build the runtime image

```bash
cd crates/mendix-7
docker build \
  --platform linux/amd64 \
  --build-arg MENDIX_VERSION=7.23.8.58888 \
  -t ontologylabs/mendix-runtime:7.23.8.58888 \
  -t ontologylabs/mendix-runtime:7 \
  .
```

The Dockerfile `curl`s `https://cdn.mendix.com/runtime/mendix-7.23.8.58888.tar.gz` (~341 MB) and asserts the expected `runtimelauncher.jar` is present — so a CDN or layout change fails the build loudly rather than at runtime. The image is **reusable across every Mendix 7.23 app**; build it once.

> **Apple Silicon / arm64:** the image is `linux/amd64` and runs under emulation. The pure-Java runtime works fine; expect a slower first boot (JVM container-start alone can take ~60 s under emulation).

## Step 2 — run it against your app

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:14-alpine
    environment: { POSTGRES_USER: mendix, POSTGRES_PASSWORD: mendix, POSTGRES_DB: mendix }
  mendix:
    image: ontologylabs/mendix-runtime:7.23.8.58888
    depends_on: [postgres]
    environment:
      ADMIN_PASSWORD: "ChangeMe2026!"            # the runtime rejects weak passwords
      DATABASE_ENDPOINT: "postgres://mendix:mendix@postgres:5432/mendix"
      DEVELOPMENT_MODE: "true"
    ports: ["8080:8080", "8090:8090"]
    volumes:
      - ./app:/opt/mendix/app                    # your unzipped MDA
      - mendix-data:/opt/mendix/data
volumes: { mendix-data: {} }
```

```bash
docker compose up
curl -fsSI http://localhost:8080/                # 200 OK once the runtime is up
```

On first boot the crate creates the schema (DDL sync) and starts the runtime; subsequent boots are fast. Port `8080` is the app; `8090` is the m2ee admin protocol.

## Mendix-7-specific gotchas (the things that actually trip people up)

* **Java 8, not 11/21.** Mendix 7.x targets Java 8 — the crate's base image is `eclipse-temurin:8-jre-jammy`. Newer JDKs are not a drop-in for the MX7 runtime/toolchain.
* **Model-default constants must be supplied.** The Mendix runtime does **not** auto-apply a constant's *model default* when the deployment config omits it — that's normally the buildpack's job. Omit them and startup fails with `Could not find value for constant '<Module.Const>'` during microflow-engine reload. The crate handles this automatically: `start.sh` reads the constants and their defaults from your model's `metadata.json` and supplies them. Override any value with the `MICROFLOW_CONSTANTS` env var (`{"Module.Constant":"value"}`).
* **`HttpHeaders` is not a recognised config key on MX7.** The runtime logs `Unknown configuration setting 'HttpHeaders'` and ignores it — harmless; leave `MXRUNTIME_HttpHeaders` empty.
* **Weak admin passwords are rejected.** `ADMIN_PASSWORD=1` throws inside `PasswordStrengthVerifier`. Use a real password.
* **The boot path is stable.** Mendix 7.23's `runtimelauncher.jar` + m2ee admin protocol are the *same* mechanism as Mendix 8/9/10/11 — so the identical `start.sh` drives every major. (We assert the launcher's presence at build time.)

## How it differs from the cloud buildpack

| | `cf-mendix-buildpack` image | `mendix-7` crate |
|---|---|---|
| Application model | **baked into the image** | **bind-mounted** |
| Reload | `docker build --no-cache` (~minutes) | `docker compose restart` (~seconds) |
| Disk per reload | ~785 MB dangling | 0 |
| Image per app/commit | many | one per Mendix version |
| Mendix binary in your repo | n/a | **never** (pulled from CDN at build) |

## Troubleshooting

* **`Could not find value for constant …`** — a no-default constant wasn't supplied. The crate auto-supplies model defaults; if you overrode `MICROFLOW_CONSTANTS`, make sure your JSON includes every required constant.
* **Hangs on first boot under emulation** — large apps doing DDL on amd64 emulation are slow; give it time (the bundled smoke test's poll timeout is configurable via `SMOKE_TIMEOUT`).
* **`runtimelauncher.jar not found` at build** — the CDN tarball layout changed or the version string is wrong; check `MENDIX_VERSION` matches your model's `RuntimeVersion` in `metadata.json`.

## Provenance & licence

The crate scaffolding (Dockerfile, `start.sh`, docs) is **Apache-2.0**. The Mendix runtime it downloads is Mendix's IP and is **never committed here** — it is `curl`ed from the official CDN at build time on your machine, and remains subject to [Mendix's terms of use](https://www.mendix.com/terms-of-use/).

---

*Part of [mendix-runtime-crates](https://github.com/ontologylabs/mendix-runtime-crates) — the runtime layer of the **mxto** Mendix toolchain. Maintaining a Mendix 8, 9, or 10 app? The same pattern works for every version — see the the [README](../README.md) page.*
