# Mendix Runtime Crates

> Model-agnostic, app-agnostic, version-pinned Docker recipes for **running** and
> **building** any Mendix application — Mendix 7 through 11 — without baking the
> model into the image. Bind-mount your unzipped MDA, set a few env vars, get a
> working Mendix runtime; or bind-mount a project and compile it to an `.mda`,
> with no Studio Pro on the host.

[![no-mendix-binaries](https://github.com/ontologylabs/mendix-runtime-crates/actions/workflows/no-mendix-binaries.yml/badge.svg)](https://github.com/ontologylabs/mendix-runtime-crates/actions/workflows/no-mendix-binaries.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Mendix 7–11](https://img.shields.io/badge/Mendix-7%20%E2%80%93%2011-blue)

**TL;DR** — `git clone` → `cd crates/mendix-11` → `docker build` (the Mendix runtime
is pulled from the Mendix CDN, not committed) → `docker run` with your unzipped MDA
bind-mounted. One image per Mendix version, reused across every app at that version,
zero dangling layers. **[Jump to Quick start ↓](#quick-start)**

> If you searched for *run a Mendix app in Docker*, *dockerize a Mendix app*, *Mendix
> runtime Docker image*, *Mendix without Studio Pro*, *self-hosted Mendix container*,
> or *Mendix 10 LTS Docker image* — this is that.

## What this is

A set of **recipes** — `Dockerfile`, `start.sh` / `build.sh`, and supporting
scaffolding — that build a clean, reusable Docker image for each Mendix major
version, in two flavours: a **runtime crate** (`crates/mendix-<N>/`) that runs an
app, and a **build crate** (`crates/mendix-<N>/build/`) that compiles a project to
an `.mda` and runs `mx check`. They contain **no Mendix binaries**: the Mendix
runtime/toolchain tarball is downloaded from the official Mendix CDN
(`cdn.mendix.com`) *at build time, on your machine*. You bring the licensed
runtime; we bring the build recipe.

## The problem it solves

The official `cf-mendix-buildpack` Docker pattern bakes the application model
directly into the image. Every model change spawns a new image and orphans the
previous one — typically ~785 MB of dangling layers per reload. An iterative
dev/test loop that reloads many times a day consumes tens of GB of disk in a
single working session.

These crates invert the pattern:

| | CF-buildpack image | These crates |
|---|---|---|
| Mendix runtime files | baked | baked (from CDN at build) |
| JRE | baked | baked |
| Application model | **baked** | **bind-mounted** |
| Reload mechanism | `docker build --no-cache` | `docker compose restart` |
| Disk cost per reload | ~785 MB (dangling) | 0 |
| Images per Mendix version | many (one per app commit) | 1 |
| Reusable across apps | no | yes |

Same Mendix version → same image. Multiple apps at the same version → one image,
multiple bind-mounts.

## Supported versions

### Runtime crates — *run* an app

| Crate | Verified Mendix version | JRE | Base image | Status |
|---|---|---|---|---|
| [`crates/mendix-11`](crates/mendix-11) | `11.6.4` | Java 21 | `eclipse-temurin:21-jre-jammy` | verified |
| [`crates/mendix-10`](crates/mendix-10) | `10.24.13.86719` (LTS) | Java 21 | `eclipse-temurin:21-jre-jammy` | verified |
| [`crates/mendix-9`](crates/mendix-9) | `9.24.20.33307` | Java 11 | `eclipse-temurin:11-jre-jammy` | verified |
| [`crates/mendix-8`](crates/mendix-8) | `8.18.35.97` (final LTS) | Java 11 | `eclipse-temurin:11-jre-jammy` | recipe (CDN 200) |
| [`crates/mendix-7`](crates/mendix-7) | `7.23.8.58888` | Java 8 | `eclipse-temurin:8-jre-jammy` | verified |

### Build crates — *compile* an `.mpr` → `.mda`

Each version also ships a **build crate** under `crates/mendix-<N>/build/`: a
version-pinned `mxbuild` + `mx` toolchain image that compiles a project and runs
`mx check`, with nothing on the host but Docker (no Studio Pro). The toolchain is
pulled from the same CDN as `mxbuild-<version>.tar.gz`. See
**[Building MDAs in Docker](docs/building-mendix-apps-in-docker.md)**.

| Build crate | mxbuild version | JDK | Base image | Status |
|---|---|---|---|---|
| [`crates/mendix-11/build`](crates/mendix-11/build) | `11.6.4` | Java 21 | `eclipse-temurin:21-jdk-jammy` | image-verified¹ |
| [`crates/mendix-10/build`](crates/mendix-10/build) | `10.24.13.86719` | Java 21 | `eclipse-temurin:21-jdk-jammy` | recipe (CDN 200) |
| [`crates/mendix-9/build`](crates/mendix-9/build) | `9.24.20.33307` | Java 11 | `eclipse-temurin:11-jdk-jammy` | recipe (CDN 200) |
| [`crates/mendix-8/build`](crates/mendix-8/build) | `8.18.35.97` | Java 11 | `eclipse-temurin:11-jdk-jammy` | recipe (CDN 200) |
| [`crates/mendix-7/build`](crates/mendix-7/build) | `7.23.8.58888` | Java 8 | `eclipse-temurin:8-jdk-jammy` | recipe (CDN 200) |

¹ *image-verified* = the image builds, the CDN toolchain pull succeeds, and the
binaries + entrypoint resolve and run; a full `.mpr → .mda` compile against a
licensed project is the remaining smoke gate (per crate `provenance.yaml`).
*recipe (CDN 200)* = authored to the same proven pattern with the CDN source
URL verified reachable, image build pending.

Each crate's `versions.yaml` lists the exact versions it targets. The runtime
boot path (`runtimelauncher.jar` + the m2ee admin protocol) and the build
invocation are identical from Mendix 7 through 11. **Mendix 8** is out of
standard support but its final LTS patch (`8.18.35.97`) is still CDN-hosted;
older MX8 patches that aren't are covered by
[`crates/mendix-8/PORTAL-DOWNLOAD.md`](crates/mendix-8/PORTAL-DOWNLOAD.md).

## Quick start

```bash
git clone https://github.com/ontologylabs/mendix-runtime-crates.git
cd mendix-runtime-crates/crates/mendix-11

# Build — the Mendix 11.6.4 runtime is curl'd from the Mendix CDN during this step
docker build \
    --platform linux/amd64 \
    --build-arg MENDIX_VERSION=11.6.4 \
    -t ontologylabs/mendix-runtime:11.6.4 \
    -t ontologylabs/mendix-runtime:11 \
    .

# Run — bind-mount your unzipped MDA; the model is never baked in
docker run -d --name my-mendix \
    -p 8080:8080 -p 8090:8090 \
    -v /path/to/unzipped/mda:/opt/mendix/app:ro \
    -v my-mendix-data:/opt/mendix/data \
    -e DATABASE_ENDPOINT="postgres://mendix:mendix@db:5432/mendix" \
    -e ADMIN_PASSWORD="a-strong-password" \
    -e DEVELOPMENT_MODE="true" \
    ontologylabs/mendix-runtime:11.6.4
```

The image tag (`ontologylabs/mendix-runtime:…`) is a **local** tag you choose at
build time — these recipes publish no registry image, so name it whatever suits
your pipeline. See each crate's `README.md` for the full env-var contract,
bind-mount layout, and a `docker compose` smoke example.

## How distribution works (and the Mendix IP line)

These recipes are distributed **recipe-only**:

- **What's in this repo** — Dockerfiles, `start.sh`, `versions.yaml`,
  `provenance.yaml`, tests, and docs. All of it is original scaffolding,
  licensed **Apache-2.0** (see [LICENSE](LICENSE)). It contains no Mendix code.
- **What's *not* in this repo** — the Mendix runtime itself. It is fetched from
  `https://cdn.mendix.com/runtime/mendix-<version>.tar.gz` during `docker build`,
  on your machine. The runtime you download is **subject to Mendix's own license**
  (https://www.mendix.com/terms-of-use/). No upstream Mendix code is forked,
  modified, or redistributed here.

A CI guard (`.github/workflows/no-mendix-binaries.yml`) enforces this on every
push and pull request: it rejects any commit that introduces a Mendix-binary
file pattern (`*.tar.gz`, `*.mda`, `*.mpr`, `*.jar`, …) or any file over 256 KB.
A Mendix tarball can never be merged into this repository.

## Repository layout

```
mendix-runtime-crates/
├── README.md
├── LICENSE                                  # Apache-2.0
├── guard.sh                                 # the no-Mendix-binary CI check
├── .github/workflows/no-mendix-binaries.yml # runs guard.sh on push + PR
├── docs/
│   ├── running-mendix-<N>-in-docker.md      # per-version run guides
│   └── building-mendix-apps-in-docker.md    # compile an .mpr → .mda
└── crates/
    ├── mendix-7/   { Dockerfile, start.sh, versions.yaml, provenance.yaml, README.md, CHANGELOG.md, tests/ }
    │   └── build/  { Dockerfile, build.sh, versions.yaml, provenance.yaml, README.md, CHANGELOG.md, tests/ }
    ├── mendix-8/   { …runtime… , PORTAL-DOWNLOAD.md, build/ }   # final 8.18 LTS; portal fallback for older patches
    ├── mendix-9/   { …runtime… , build/ }
    ├── mendix-10/  { …runtime… , build/ }
    └── mendix-11/  { …runtime… , build/ }
```

## Contributing a new version

Freshness is the point of this library. To add a Mendix version:

1. Add the version to the relevant crate's `versions.yaml`.
2. Build it and run the crate's `tests/smoke-test.sh` against a known-good MDA.
3. Open a PR with the smoke result noted. The `no-mendix-binaries` guard must pass.

New majors are welcome as new `crates/mendix-<N>/` directories following the same
shape.

## License

Apache License 2.0 — see [LICENSE](LICENSE). Copyright © 2026 Ontology Labs, Inc.

The Mendix runtime fetched at build time is licensed separately by Mendix.

---

Maintained by **[Ontology Labs](https://ontologylabs.ai)**, the team behind
[mxto.ai](https://mxto.ai) — tooling for working with Mendix applications as
first-class, version-controlled, AI-readable artifacts. If cross-version Mendix
Docker plumbing is a pain you recognise, the rest of what we build may interest you.
