# Contributing

Thanks for helping improve Mendix Runtime Crates!

## The one hard rule: no Mendix binaries

This repository ships **recipes only** — `Dockerfile`, `start.sh`, YAML, docs. It
must **never** contain a Mendix binary (`*.tar.gz`, `*.mda`, `*.mpr`, `*.jar`,
`*.war`, …). The Mendix runtime is pulled from `cdn.mendix.com` at build time, on
the build machine — never committed.

A CI guard (`guard.sh`, run by `.github/workflows/no-mendix-binaries.yml`) fails
any change that adds a forbidden file pattern or any file over 256 KB. `main` is
protected: this check must pass before a PR can merge. Run it locally first:

```sh
./guard.sh
```

## Adding a new Mendix version

See **[Contributing a new version](README.md#contributing-a-new-version)**. In
short: copy the closest crate, set the `FROM` JDK base for that major (MX7/8 → 8,
MX9 → 11, MX10/11 → 21), set `ARG MENDIX_VERSION`, build, smoke-test against a real
app, and record the result in `versions.yaml` + `provenance.yaml`.

## Pull requests

Keep changes focused — one version or one doc per PR where practical. Be kind in
reviews and issues.
