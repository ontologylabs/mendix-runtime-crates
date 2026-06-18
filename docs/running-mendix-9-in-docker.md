# Running Mendix 9 in Docker

**Mendix 9** (the 9.x LTS line, e.g. **9.24**) is still one of the most widely deployed Mendix versions in production — and one of the most awkward to run locally without Studio Pro. The **`mendix-9` runtime crate** boots *any* Mendix 9.x application you bind-mount into it: no Studio Pro, no model baked into the image, no Mendix binaries in your repo.

> **TL;DR**
> ```bash
> cd crates/mendix-9
> docker build --platform linux/amd64 --build-arg MENDIX_VERSION=9.24.20.33307 \
>   -t ontologylabs/mendix-runtime:9 .
> unzip your-mx9-app.mda -d ./tests/mda
> docker compose -f tests/docker-compose.smoke.yml up   # → http://localhost:8080
> ```

## What you get

* **Java 11 + the Mendix 9.24 runtime**, pulled from `cdn.mendix.com` at build time (never committed).
* **Your model bind-mounted**, not baked — `docker compose restart` to reload, zero dangling images.
* PostgreSQL-backed, driven through the **m2ee admin protocol** (the same mechanism Mendix Cloud uses).
* Verified: this crate boots the native-mobile app **FigWarehouse 9.24.20** to a healthy **HTTP 200**.

## The one rule that bites everyone: use JDK 11, not 21

**Mendix 9.24 is incompatible with JDK 21.** The 9.x toolchain bundles Gradle 7.6.3, which throws `Unsupported class file major version 65` on Java 21. The crate's base image is therefore `eclipse-temurin:11-jre-jammy` — do **not** "upgrade" it to 17/21 for a Mendix 9 app.

## Build & run

```bash
cd crates/mendix-9
docker build --platform linux/amd64 --build-arg MENDIX_VERSION=9.24.20.33307 \
  -t ontologylabs/mendix-runtime:9.24.20.33307 -t ontologylabs/mendix-runtime:9 .
```

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:14-alpine
    environment: { POSTGRES_USER: mendix, POSTGRES_PASSWORD: mendix, POSTGRES_DB: mendix }
  mendix:
    image: ontologylabs/mendix-runtime:9.24.20.33307
    depends_on: [postgres]
    environment:
      ADMIN_PASSWORD: "ChangeMe2026!"
      DATABASE_ENDPOINT: "postgres://mendix:mendix@postgres:5432/mendix"
      DEVELOPMENT_MODE: "true"
    ports: ["8080:8080", "8090:8090"]
    volumes: ["./app:/opt/mendix/app", "mendix-data:/opt/mendix/data"]
volumes: { mendix-data: {} }
```

`docker compose up`, then `curl -fsSI http://localhost:8080/`.

## Mendix-9-specific gotchas

* **Model-default constants must be supplied.** On Mendix 9 the runtime does **not** auto-apply a constant's model default when the deployment config omits it — startup then fails with `Could not find value for constant '<Module.Const>'` during microflow-engine reload. The crate handles this automatically: `start.sh` reads the constants + defaults from your model's `metadata.json` and supplies them (FigWarehouse boots with 10 of them, including a nested-JSON value). Override any with `MICROFLOW_CONSTANTS={"Module.Constant":"value"}`.
* **`HttpHeaders`** logs a harmless `Unknown configuration setting` — leave `MXRUNTIME_HttpHeaders` empty.
* **Native mobile apps** run fine: the crate serves the runtime + the bundled web/native assets; you point your Make-It-Native build at the URL.
* The **m2ee boot path is identical** to Mendix 7/8/10/11, so the same `start.sh` drives it.

## How it differs from the cloud buildpack

The `cf-mendix-buildpack` image **bakes the model** — every reload spawns a new ~785 MB image and orphans the last one. This crate bind-mounts the model: reload is `docker compose restart`, disk cost per reload is **0**, and **one image** serves every app at that Mendix version. (Full comparison in the [Mendix 7 guide](running-mendix-7-in-docker.md#how-it-differs-from-the-cloud-buildpack).)

## Troubleshooting

* **`Unsupported class file major version 65`** — you're on JDK 21; Mendix 9 needs JDK 11 (the crate's base image is correct out of the box).
* **`Could not find value for constant …`** — a no-default constant wasn't supplied; the crate auto-supplies model defaults, so check any `MICROFLOW_CONSTANTS` override is complete.
* **`runtimelauncher.jar not found` at build** — `MENDIX_VERSION` must match your model's `RuntimeVersion` in `metadata.json`.

## Provenance & licence

The crate scaffolding is **Apache-2.0**. The Mendix runtime is `curl`ed from the official CDN at build time and is **never committed** — it remains Mendix's IP under [Mendix's terms of use](https://www.mendix.com/terms-of-use/).

---

*Part of [mendix-runtime-crates](https://github.com/ontologylabs/mendix-runtime-crates) — the runtime layer of the **mxto** Mendix toolchain. The same pattern works for Mendix 7, 8, 10, and 11 — see the [README](../README.md).*
