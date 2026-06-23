# Obtaining a Mendix 8 toolchain that isn't on the public CDN

This crate's **default** version (`8.18.35.97`, the final 8.18 LTS patch) is served
from the public Mendix CDN, so `docker build` Just Works — no portal needed. Use
this document only when you need an **older MX8 patch** (or any Mendix version) that
the CDN does **not** host.

> **How to tell.** Probe the CDN first — no login required:
> ```bash
> curl -sI "https://cdn.mendix.com/runtime/mendix-8.18.21.4259.tar.gz" | head -1
> curl -sI "https://cdn.mendix.com/runtime/mxbuild-8.18.21.4259.tar.gz" | head -1
> ```
> `HTTP/2 200` → it's on the CDN; just pass `--build-arg MENDIX_VERSION=<that>` and
> skip this document. `HTTP/2 404` → it's portal-only; continue below.
>
> Observed (2026-06-23): `8.18.35.97` → **200**; `8.18.21.4259` → **404**.

## Why some versions are portal-only

Mendix prunes older runtime/mxbuild tarballs from the public CDN over time. Those
versions remain available to licensed users through the Mendix Platform (portal),
or are bundled inside the matching Studio Pro install. This repo commits **no
Mendix binary** (`guard.sh`, D-DOCKER-LIB-002) — you bring the licensed tarball;
the crate stays a recipe.

## The recipe stays the same — only the source URL changes

Both the runtime crate and the build crate already accept a CDN-base build-arg:

| Crate | Build-arg | Default |
|---|---|---|
| `mendix-8` (runtime) | `RUNTIME_CDN_BASE` | `https://cdn.mendix.com/runtime` |
| `mendix-8/build` (mxbuild) | `MXBUILD_CDN_BASE` | `https://cdn.mendix.com/runtime` |

So the portal flow is: **fetch the tarball → serve it over HTTP locally → point the
build-arg at your local host.** The tarball is never committed.

### 1. Download from the portal (human or agent)

The runtime tarball must be named `mendix-<version>.tar.gz`; the build toolchain
tarball must be named `mxbuild-<version>.tar.gz` (the crate's curl builds that name
from `MENDIX_VERSION`).

### Agent download-instructions

An AI agent with browser automation (e.g. Claude-in-Chrome / Playwright) can obtain
a portal-only tarball as follows. **Stop and ask the operator to log in** — never
script credential entry.

1. **Authenticate.** Open `https://sprintr.home.mendix.com/` (or
   `https://marketplace.mendix.com/`). If not already authenticated, hand control to
   the operator to complete Mendix SSO. Do not enter credentials yourself.
2. **Locate the version.** Mendix Studio Pro / runtime archives live under the
   Marketplace → "Studio Pro" downloads and the version archive
   (`https://marketplace.mendix.com/link/studiopro/<version>`). The runtime tarball
   matches `mendix-<version>.tar.gz`; the build toolchain is inside the Studio Pro
   package as `modeler/mxbuild` (+ `modeler/mx`).
3. **If only a Studio Pro installer is available** (no standalone tarball): install
   Studio Pro `<version>`, then locate its `modeler/` directory and `tar -czf
   mxbuild-<version>.tar.gz modeler/` so the archive's top-level is `modeler/`
   (the layout the crate's `tar -xzf … -C /opt/mxtools` expects).
4. **Verify the archive shape** before serving it:
   ```bash
   tar -tzf mxbuild-<version>.tar.gz | grep -m1 'modeler/mxbuild'   # build toolchain
   tar -tzf mendix-<version>.tar.gz  | grep -m1 "<version>/runtime/launcher/runtimelauncher.jar"  # runtime
   ```
5. **Record provenance.** Note the portal URL + SHA-256 in the crate's
   `provenance.yaml` (`cdn_source_url:` → the portal link, plus a `sha256:` of the
   tarball you fetched).

### 2. Serve the tarball locally

```bash
mkdir -p /tmp/mxcdn && cp mendix-<version>.tar.gz mxbuild-<version>.tar.gz /tmp/mxcdn/
( cd /tmp/mxcdn && python3 -m http.server 8000 )   # serves http://localhost:8000/
```

On Docker-for-Mac / Colima the build reaches the host as `host.docker.internal`.

### 3. Build pointing at your local source

```bash
# runtime
docker build --platform linux/amd64 \
    --build-arg MENDIX_VERSION=<version> \
    --build-arg RUNTIME_CDN_BASE=http://host.docker.internal:8000 \
    -t ontologylabs/mendix-runtime:<version> crates/mendix-8

# build toolchain
docker build --platform linux/amd64 \
    --build-arg MENDIX_VERSION=<version> \
    --build-arg MXBUILD_CDN_BASE=http://host.docker.internal:8000 \
    -t ontologylabs/mendix-mxbuild:<version> crates/mendix-8/build
```

The resulting image is identical in shape to a CDN-built one; only the byte source
of the tarball differed. Tear down the local server when done.

## Guard compliance

Do **not** `cp` the tarball into `crates/mendix-8/` (the build context) and `git
add` it — `guard.sh` blocks `*.tar.gz` and any file over 256 KB. Keep the tarball
outside the repo (e.g. `/tmp/mxcdn`) and serve it; the repo stays binary-free.
