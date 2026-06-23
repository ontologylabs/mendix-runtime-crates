# Mendix 11 Build Crate

> A model-agnostic, version-pinned Docker image that compiles **any** Mendix 11.x
> project (`.mpr`) into a deployable `.mda` — and runs `mx check` — with nothing
> on the host but Docker. The Mendix build toolchain (`mxbuild` + `mx`) is pulled
> from the official Mendix CDN at build time; no Studio Pro install, no committed
> binaries.

This is the **build** companion to the [`mendix-11` runtime crate](../). The build
crate *produces* the `.mda`; the runtime crate *runs* it.

## Why this exists

The AIDE pipeline compiles models with `mxbuild` driven from a bind-mounted Studio
Pro install. That requires a licensed modeler on the host. This crate makes the
toolchain self-contained and version-pinned: one image per Mendix major, the
matching `mxbuild` fetched from `cdn.mendix.com` at `docker build` — so a CI runner
or a contributor with only Docker can compile a Mendix 11 app without Studio Pro.

| | Studio Pro on host | aide-mxtools (bind-mount) | This build crate |
|---|---|---|---|
| Needs Studio Pro installed | yes | yes (modeler bind-mounted) | **no** |
| Toolchain source | local install | local install | **CDN at build** |
| Version pinning | manual | manual | **one image per version** |
| Runs in plain CI | no | partial | **yes** |

## Image tags

| Tag | Pins | Use |
|---|---|---|
| `ontologylabs/mendix-mxbuild:11.6.4` | Exact version (immutable) | Reproducible CI |
| `ontologylabs/mendix-mxbuild:11` | Latest 11.x in this crate | Dev, demo |

## Build the image

```bash
cd crates/mendix-11/build
docker build \
    --platform linux/amd64 \
    --build-arg MENDIX_VERSION=11.6.4 \
    -t ontologylabs/mendix-mxbuild:11.6.4 .
# mxbuild + mx are pulled from cdn.mendix.com/runtime/mxbuild-11.6.4.tar.gz at build.
```

## Compile an app

```bash
# /path/to/project contains App.mpr
docker run --rm \
    --platform linux/amd64 \
    -v /path/to/project:/workspace \
    ontologylabs/mendix-mxbuild:11.6.4 \
    build /workspace/App.mpr
# → writes /path/to/project/App.mda
```

Then run it with the runtime crate:

```bash
unzip /path/to/project/App.mda -d /path/to/project/app
cd ../                       # the mendix-11 runtime crate
docker compose -f tests/docker-compose.smoke.yml up   # or your own compose
```

## Validate a model (`mx check`)

```bash
docker run --rm -v /path/to/project:/workspace \
    ontologylabs/mendix-mxbuild:11.6.4 \
    check /workspace/App.mpr
# exit 0 = clean · 1 = errors · 2 = warnings only
```

## What the entrypoint auto-injects

`build.sh` supplies the toolchain paths `mxbuild` needs unless you pass them:

* `--java-home` / `--java-exe-path` → the baked JDK (`$JAVA_HOME`)
* `--gradle-home` → the toolchain's bundled Gradle
* `--loose-version-check` → tolerate patch drift between toolchain and model
* `--output=/workspace/<App>.mda` → default output beside the `.mpr`

Pass any of these explicitly to override.

## Notes & gotchas

* **Runs as root by design.** A single-shot build container, not a service. Root
  avoids the bind-mount uid mismatch that would block writing the `.mda` back into
  your mounted `/workspace`. On Linux, pass `--user $(id -u)` if you want
  host-uid-owned output; the entrypoint re-creates the Mendix settings dir under
  the resulting `$HOME`.
* **`.NET` whitelist (MX 11).** mxbuild creates settings under
  `$HOME/.local/share/Mendix` and FailFast-rejects *creating* that path itself; the
  image pre-creates it. (Same fix as the AIDE aide-mxtools image.)
* **amd64 emulation.** On Apple Silicon, `mxbuild` runs x86_64 under emulation.
  Enable Colima Rosetta (`colima start --vm-type vz --vz-rosetta`) for speed; a
  hung emulated build is the classic symptom of Rosetta being off.
* **No Mendix binary is committed.** The toolchain is fetched from the CDN at build,
  on your licensed machine (D-DOCKER-LIB-002). See repo `guard.sh`.

See [`provenance.yaml`](provenance.yaml) for the exact CDN source and
[`versions.yaml`](versions.yaml) for verified versions.
