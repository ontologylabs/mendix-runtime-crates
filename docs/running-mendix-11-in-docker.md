# Running Mendix 11 in Docker

**Mendix 11** is the latest major release. New apps start here, and teams evaluating Mendix want a fast, repeatable way to run an 11.x app in a container — for CI, demos, or local development — without baking the model into a throwaway image. The **`mendix-11` runtime crate** does exactly that: bind-mount your MDA, get a working runtime, reload in seconds.

> **TL;DR**
> ```bash
> cd crates/mendix-11
> docker build --platform linux/amd64 --build-arg MENDIX_VERSION=11.6.4 \
>   -t ontologylabs/mendix-runtime:11 .
> unzip your-mx11-app.mda -d ./tests/mda
> docker compose -f tests/docker-compose.smoke.yml up   # → http://localhost:8080
> ```

## What you get

* **Java 21 + the Mendix 11.x runtime**, pulled from `cdn.mendix.com` at build time (never committed). Base image `eclipse-temurin:21-jre-jammy`.
* **Your model bind-mounted**, not baked — `docker compose restart` to reload, zero dangling images.
* PostgreSQL-backed, driven through the **m2ee admin protocol**.
* Verified: this crate boots both **Claudius** (a certification reference app) and **ExpenseWorks** (an independent fresh 11.6.4 app) to a healthy **HTTP 200** in ~15–25 s — the same image, different ProjectIDs, confirming it's genuinely "any v11 app".

## Build & run

```bash
cd crates/mendix-11
docker build --platform linux/amd64 --build-arg MENDIX_VERSION=11.6.4 \
  -t ontologylabs/mendix-runtime:11.6.4 -t ontologylabs/mendix-runtime:11 .
```

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:14-alpine
    environment: { POSTGRES_USER: mendix, POSTGRES_PASSWORD: mendix, POSTGRES_DB: mendix }
  mendix:
    image: ontologylabs/mendix-runtime:11.6.4
    depends_on: [postgres]
    environment:
      ADMIN_PASSWORD: "ChangeMe2026!"
      DATABASE_ENDPOINT: "postgres://mendix:mendix@postgres:5432/mendix"
      DEVELOPMENT_MODE: "true"
    ports: ["8080:8080", "8090:8090"]
    volumes: ["./app:/opt/mendix/app", "mendix-data:/opt/mendix/data"]
volumes: { mendix-data: {} }
```

## Mendix-11-specific notes

* **Strict startup by default.** Mendix 11 refuses to load a production/acceptance MDA unless project security is `CheckEverything` *and* a strong admin password is set. For local runs, `DEVELOPMENT_MODE=true` (forces `DTAPMode=D`) relaxes that — and `ADMIN_PASSWORD` must be a real password (weak values like `1` are rejected in `PasswordStrengthVerifier`).
* **Custom CSP / HTTP headers.** The default empty `MXRUNTIME_HttpHeaders=[]` is harmless. If you need to inject custom response headers (e.g. a CSP for browser automation), note that the exact v11 config-key wiring is still being finalised — for plain app runs you don't need it.
* **Constants are auto-supplied** from the model's `metadata.json` defaults (override with `MICROFLOW_CONSTANTS`). Mendix 11 is more tolerant of omitted constants than 9/10, but the crate supplies them for consistency across versions.
* **Forward-compatible:** additional 11.x patch releases bake into the same image as extra `/opt/mendix/runtimes/<version>/` subdirs; `start.sh` resolves the right one per the deployed model's `metadata.json`.

## How it differs from the cloud buildpack

The `cf-mendix-buildpack` image bakes the model (a new ~785 MB image, orphaned, per reload). This crate bind-mounts it: `docker compose restart`, zero dangling images, one image per Mendix version. (Full table in the [Mendix 7 guide](running-mendix-7-in-docker.md#how-it-differs-from-the-cloud-buildpack).)

## Troubleshooting

* **Refuses to start citing project security / password** — set `DEVELOPMENT_MODE=true` and a strong `ADMIN_PASSWORD`.
* **`runtimelauncher.jar not found` at build** — `MENDIX_VERSION` must match your model's `RuntimeVersion` in `metadata.json`.

## Provenance & licence

The crate scaffolding is **Apache-2.0**. The Mendix runtime is `curl`ed from the official CDN at build time and is **never committed** — it remains Mendix's IP under [Mendix's terms of use](https://www.mendix.com/terms-of-use/).

---

*Part of [mendix-runtime-crates](https://github.com/ontologylabs/mendix-runtime-crates) — the runtime layer of the **mxto** Mendix toolchain. The same pattern works for Mendix 7, 8, 9, and 10 — see the [README](../README.md).*
