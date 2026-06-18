# Running Mendix 10 in Docker

**Mendix 10** (the **10.24 LTS** line) is the current long-term-support release and the version most production apps target today. The **`mendix-10` runtime crate** boots *any* Mendix 10.x application you bind-mount into it — model-free, Studio-Pro-free, with no Mendix binaries in your repo. It's ideal for local testing, CI, and migration spikes against real production models.

> **TL;DR**
> ```bash
> cd crates/mendix-10
> docker build --platform linux/amd64 --build-arg MENDIX_VERSION=10.24.13.86719 \
>   -t ontologylabs/mendix-runtime:10 .
> unzip your-mx10-app.mda -d ./tests/mda
> docker compose -f tests/docker-compose.smoke.yml up   # → http://localhost:8080
> ```

## What you get

* **Java 21 + the Mendix 10.24 runtime**, pulled from `cdn.mendix.com` at build time (never committed). Mendix 10.24 LTS supports JDK 21; the base image is `eclipse-temurin:21-jre-jammy`.
* **Your model bind-mounted**, not baked — `docker compose restart` to reload, zero dangling images.
* PostgreSQL-backed, driven through the **m2ee admin protocol**.
* Verified: this crate boots a **large production app — AdviserMarketplace (10.24.13)** — to a healthy **HTTP 200**, with 91 model-default constants and 9,647 first-boot DDL commands.

## Build & run

```bash
cd crates/mendix-10
docker build --platform linux/amd64 --build-arg MENDIX_VERSION=10.24.13.86719 \
  -t ontologylabs/mendix-runtime:10.24.13.86719 -t ontologylabs/mendix-runtime:10 .
```

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:14-alpine
    environment: { POSTGRES_USER: mendix, POSTGRES_PASSWORD: mendix, POSTGRES_DB: mendix }
  mendix:
    image: ontologylabs/mendix-runtime:10.24.13.86719
    depends_on: [postgres]
    environment:
      ADMIN_PASSWORD: "ChangeMe2026!"
      DATABASE_ENDPOINT: "postgres://mendix:mendix@postgres:5432/mendix"
      DEVELOPMENT_MODE: "true"
    ports: ["8080:8080", "8090:8090"]
    volumes: ["./app:/opt/mendix/app", "mendix-data:/opt/mendix/data"]
volumes: { mendix-data: {} }
```

## Mendix-10-specific notes

* **`DEVELOPMENT_MODE=true`** is the easy path for local runs: it forces `DTAPMode=D`, relaxing the strict project-security checks (`CheckFormsAndMicroflows` / `CheckEverything`) that otherwise block a non-production deploy. Drop it for production-faithful runs.
* **Large apps take a while on the *first* boot.** A real production model can run thousands of DDL commands to create its schema (AdviserMarketplace: 9,647). On native hardware that's quick; under **amd64 emulation on Apple Silicon** it can take ~10 minutes. The bundled smoke test's poll timeout is configurable — `SMOKE_TIMEOUT=1200 ./tests/smoke-test.sh <mda>`. Subsequent boots reuse the schema and are fast.
* **Model-default constants are auto-supplied.** Like Mendix 9, the MX10 runtime doesn't auto-apply model defaults when the deployment config omits them; `start.sh` reads them from `metadata.json` and supplies them (override with `MICROFLOW_CONSTANTS`).
* **`HttpHeaders`** logs a harmless `Unknown configuration setting` — leave `MXRUNTIME_HttpHeaders` empty.

## How it differs from the cloud buildpack

The `cf-mendix-buildpack` image bakes the model (a new ~785 MB image, orphaned, per reload). This crate bind-mounts it: `docker compose restart`, zero dangling images, one image per Mendix version. (Full table in the [Mendix 7 guide](running-mendix-7-in-docker.md#how-it-differs-from-the-cloud-buildpack).)

## Troubleshooting

* **Never reaches HTTP 200 on first boot** — it's probably still doing DDL on a large model under emulation. Watch the logs for `Executing N database synchronization command(s)` and raise `SMOKE_TIMEOUT`.
* **`Could not find value for constant …`** — a no-default constant wasn't supplied; the crate auto-supplies model defaults, so check any `MICROFLOW_CONSTANTS` override is complete.
* **Refuses to start citing project security** — set `DEVELOPMENT_MODE=true` for local runs.

## Provenance & licence

The crate scaffolding is **Apache-2.0**. The Mendix runtime is `curl`ed from the official CDN at build time and is **never committed** — it remains Mendix's IP under [Mendix's terms of use](https://www.mendix.com/terms-of-use/).

---

*Part of [mendix-runtime-crates](https://github.com/ontologylabs/mendix-runtime-crates) — the runtime layer of the **mxto** Mendix toolchain. The same pattern works for Mendix 7, 8, 9, and 11 — see the [README](../README.md).*
