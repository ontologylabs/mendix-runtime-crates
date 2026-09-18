# Building Mendix apps in Docker — compile an `.mpr` to an `.mda` without Studio Pro

You have a Mendix project (`.mpr`) and you want a deployable app package (`.mda`) —
in CI, on a build server, or on a laptop that doesn't have Studio Pro installed.
The **build crates** do exactly that: a version-pinned `mxbuild` + `mx` toolchain in
a Docker image, pulled from the Mendix CDN at build time. Bind-mount your project,
run `build`, get an `.mda`. Same pattern for Mendix 7, 8, 9, 10, and 11.

> **TL;DR**
> ```bash
> cd crates/mendix-11/build
> docker build --platform linux/amd64 --build-arg MENDIX_VERSION=11.6.4 \
>   -t ontologylabs/mendix-mxbuild:11 .
> docker run --rm -v "$PWD/MyApp":/workspace ontologylabs/mendix-mxbuild:11 build /workspace/MyApp.mpr
> # → MyApp.mda appears next to MyApp.mpr
> ```

## What you get

* **A JDK + the Mendix `mxbuild` + `mx` toolchain**, pulled from
  `cdn.mendix.com/runtime/mxbuild-<version>.tar.gz` at build time (never committed).
* **`build`** — compile an `.mpr` to an `.mda` (the package the [runtime
  crates](../README.md) run).
* **`check`** — run `mx check` with CI-normalised exit codes (`0` clean, `1`
  errors, `2` warnings only).
* One image per Mendix major version; reused across every project at that version.
* No Studio Pro, no licensed modeler install on the host — just Docker.

## Pick the version

The build crate must match the Mendix version your project was last edited with
(its `_ProductVersion`). Each major has its own crate and JDK:

| Build crate | Default version | JDK |
|---|---|---|
| `crates/mendix-11/build` | `11.6.4` | Java 21 |
| `crates/mendix-10/build` | `10.24.13.86719` | Java 21 |
| `crates/mendix-9/build` | `9.24.20.33307` | Java 11 |
| `crates/mendix-8/build` | `8.18.35.97` | Java 11 |
| `crates/mendix-7/build` | `7.23.8.58888` | Java 8 |

Override the exact patch with `--build-arg MENDIX_VERSION=<your-version>`. The
toolchain CDN serves any patch that runtime serves; the build crate's `build.sh`
passes `--loose-version-check`, so a small patch drift between toolchain and model
is tolerated.

## Build the image

```bash
cd crates/mendix-10/build
docker build --platform linux/amd64 \
  --build-arg MENDIX_VERSION=10.24.13.86719 \
  -t ontologylabs/mendix-mxbuild:10.24.13.86719 \
  -t ontologylabs/mendix-mxbuild:10 .
```

## Compile a project

```bash
# /path/to/MyApp contains MyApp.mpr
docker run --rm --platform linux/amd64 \
  -v /path/to/MyApp:/workspace \
  ontologylabs/mendix-mxbuild:10 \
  build /workspace/MyApp.mpr
# → writes /path/to/MyApp/MyApp.mda
```

Then run it with the matching runtime crate:

```bash
unzip /path/to/MyApp/MyApp.mda -d /path/to/MyApp/app
# … docker run the mendix-10 runtime crate with /path/to/MyApp/app bind-mounted
```

## Validate a model (CI gate)

```bash
docker run --rm -v /path/to/MyApp:/workspace \
  ontologylabs/mendix-mxbuild:10 \
  check /workspace/MyApp.mpr
echo $?   # 0 = clean · 1 = errors · 2 = warnings only
```

`build.sh` auto-injects the toolchain paths `mxbuild` needs (`--java-home`,
`--java-exe-path`, `--gradle-home`, `--loose-version-check`) and defaults the
output to `/workspace/<App>.mda`. Pass any of those explicitly to override.

## What this costs

Numbers below are one MEASUREMENT, not a promise — one 40-core Linux host, Docker
29.6.1, overlayfs, `docker build --no-cache` (a genuinely cold pull, no layer
reuse). Your network and CPU will differ; treat these as an order of magnitude.

| step | measured | notes |
|---|---|---|
| Build the image (once per Mendix version) | **~2m10s–2m26s** | includes an **~700–850 MB** CDN pull of `mxbuild-<version>.tar.gz` (size scales with Mendix version — MX 10.24 measured 847 MB) |
| Rebuild after editing only `build.sh` | **~2s** | the toolchain layer is cached; only the small `COPY build.sh` layer reruns |
| Compile a real project (`mxbuild`, cold) | **~2m05s** | a ~7,000-file production-sized MX 10.24 project, `BUILD SUCCEEDED`, 84 MB `.mda` |
| Compile the **same** project again (warm) | **no faster — sometimes slower** | see below |

⚠ **There is no warm-build cache, and planning around one will disappoint you.**
`mxbuild`'s own first steps are "Cleaning app bundle log file... Cleaning web
deployment directory..." — it discards the project's `deployment/` directory on
**every** run, toolchain-side, before it does anything else. Three consecutive
runs against the same project and container measured 2m05s, 2m10s, 1m53s — the
second run was not faster than the first. The only cold cost worth caching is
the **image** (the CDN pull); a project's `deployment/` output buys you nothing
and is safe to `--exclude` if you're staging files onto another host.

Image size on disk is **~2.4–3.3 GB** depending on Mendix major (more recent
majors bundle a larger toolchain) — budget for that per version you build, once.

## The major-version guard

Each build crate is baked for **one Mendix major**. `build.sh` reads your
project's `_ProductVersion` (via `sqlite3` against the `.mpr`) before compiling,
and **refuses** with exit code `3` if it doesn't match the image's major:

```
$ docker run --rm -v /path/to/MyApp:/workspace ontologylabs/mendix-mxbuild:10 build /workspace/App.mpr
ERROR: MAJOR VERSION MISMATCH. The project is Mendix 12; this image
       carries the Mendix 10 build toolchain (10.24.13.86719).
       Use the matching image — ontologylabs/mendix-mxbuild:12 — or an
       exact tag for your project's version. Compiling across a major would pick the
       wrong JDK and the wrong model format, and --loose-version-check (injected for
       PATCH drift) would not stop it.
       Deliberate cross-major experiment: set MXBUILD_ALLOW_MAJOR_MISMATCH=1.
```

This is deliberate: a build that silently ran against the wrong JDK and produced
*something* costs more than one that stopped and said why. **Patch/minor drift
within the same major is fine** — that's what `--loose-version-check` is for —
only a MAJOR mismatch refuses. To force a deliberate cross-major experiment
anyway, set `MXBUILD_ALLOW_MAJOR_MISMATCH=1`.

Every image ships a self-test that exercises the guard against planted inputs,
entirely inside the container (no project, no network needed):

```bash
docker run --rm ontologylabs/mendix-mxbuild:10 selftest
```

## Mendix 8 note

Mendix 8 is out of standard support, but its final LTS patch (`8.18.35.97`, the
crate default) is still CDN-hosted, so it builds with no extra steps. Older MX8
patches aren't all on the CDN — obtain the toolchain via the Mendix portal and
point `MXBUILD_CDN_BASE` at a local copy. See
[`crates/mendix-8/PORTAL-DOWNLOAD.md`](../crates/mendix-8/PORTAL-DOWNLOAD.md),
which includes step-by-step agent download-instructions.

## Troubleshooting

* **The build hangs / `mxbuild` crashes under emulation** — on Apple Silicon,
  `mxbuild` (x86_64 .NET) needs Rosetta. Start Colima with
  `colima start --vm-type vz --vz-rosetta`. A hung build is the classic
  Rosetta-off symptom.
* **`modeler/mxbuild not found` at image build** — `MENDIX_VERSION` must be a
  real CDN-hosted version; probe `curl -sI cdn.mendix.com/runtime/mxbuild-<v>.tar.gz`.
* **`Project file '/workspace/App.mpr' does not exist`** — on Colima only `$HOME`
  is mounted into the VM; keep your project under `$HOME` (or stage a copy there).
  **A second, unrelated cause gives the identical message**: `-v` bind mounts are
  resolved by the Docker **daemon**, not by your shell. If `DOCKER_HOST` points at
  a remote engine (`docker context ls`; common with a remote builder, an SSH-forwarded
  daemon, or some cloud CI runners), your bind-mount path is resolved on that remote
  machine — a path that doesn't exist there is silently **created empty** and the
  container builds against nothing. Check `echo $DOCKER_HOST` and `docker context ls`
  before assuming a mount is broken; a `docker run -v <dir>:/w --entrypoint /bin/bash
  <image> -c "ls -la /w"` that comes back empty when your host directory isn't is the
  tell.
* **Root-owned `.mda` on Linux** — the build container runs as root to write the
  output into your bind-mount; pass `--user $(id -u)` if you need host-uid output.

## Provenance & licence

The crate scaffolding (`Dockerfile`, `build.sh`, docs, tests) is **Apache-2.0**.
The Mendix `mxbuild`/`mx` toolchain is `curl`ed from the official CDN at build time
and is **never committed** — it remains Mendix's IP under
[Mendix's terms of use](https://www.mendix.com/terms-of-use/). The repo's
`no-mendix-binaries` CI guard enforces this on every push and PR.

---

*Part of [mendix-runtime-crates](https://github.com/ontologylabs/mendix-runtime-crates)
— the build layer of the **mxto** Mendix toolchain. To run the `.mda` you produce,
see the [README](../README.md) and the per-version run guides.*
