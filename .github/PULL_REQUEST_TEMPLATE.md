<!-- Thanks for contributing! Keep it small and recipe-only. -->

## What does this PR do?

<!-- e.g. "Adds Mendix 10.18.5 to the mendix-10 crate." -->

## Checklist
- [ ] **Adding a version?** I built it and ran the crate's `tests/smoke-test.sh` against a real MDA (HTTP 200).
- [ ] I added the version row to the crate's `versions.yaml`.
- [ ] **No Mendix binaries committed** — the runtime is `curl`'d from the Mendix CDN at build time. (The `no-mendix-binaries` check must pass.)
- [ ] Docs / `CHANGELOG.md` updated if behaviour changed.

## Smoke result
<!-- paste the version + HTTP status, or the smoke-test output -->
