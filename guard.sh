#!/usr/bin/env sh
# guard.sh — reject any Mendix binary or oversized file from the public recipe repo.
#
# This repository ships recipes ONLY (Dockerfiles, start.sh, YAML, docs) — never a
# Mendix binary. The Mendix runtime is curl'd from cdn.mendix.com at build time, on
# the consumer's machine, and is never committed. Recipes are all small pure-text
# files (< 16 KB), so a 256 KB cap makes any larger or binary-typed file suspicious
# by construction.
#
# Host-agnostic: invoked by .github/workflows/no-mendix-binaries.yml (GitHub) or any
# CI runner. Exit 0 = clean, exit 1 = violation. Enforces D-DOCKER-LIB-002.
set -eu

MAX_BYTES=262144  # 256 KB
BIN_PATTERN='\.(tar\.gz|tgz|mda|mpr|mpk|war|jar|zip|so|dll|exe|class|bin)$'

fail=0

# 1. Forbidden binary file patterns among tracked files.
binaries=$(git ls-files | grep -iE "$BIN_PATTERN" || true)
if [ -n "$binaries" ]; then
  echo "BLOCKED: Mendix-binary file pattern(s) tracked in the repo:"
  echo "$binaries" | while IFS= read -r f; do printf '  - %s\n' "$f"; done
  fail=1
fi

# 2. Oversized tracked files (a Mendix tarball would be huge; recipes are tiny).
# Note: an `if` block (not `[ ] && printf`) so a small-file iteration returns 0 and
# does not trip `set -e` inside the command substitution.
oversized=$(git ls-files | while IFS= read -r f; do
  [ -f "$f" ] || continue
  bytes=$(wc -c < "$f" | tr -d ' ')
  if [ "$bytes" -gt "$MAX_BYTES" ]; then
    printf '%s (%s bytes)\n' "$f" "$bytes"
  fi
done) || true
if [ -n "$oversized" ]; then
  echo "BLOCKED: file(s) exceed the ${MAX_BYTES}-byte cap (possible embedded binary):"
  echo "$oversized" | while IFS= read -r line; do printf '  - %s\n' "$line"; done
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "This repository ships recipes only — never Mendix binaries (D-DOCKER-LIB-002)."
  echo "The Mendix runtime is fetched from cdn.mendix.com at build time, never committed."
  exit 1
fi

echo "OK: no Mendix binaries, no oversized files. $(git ls-files | wc -l | tr -d ' ') tracked files checked."
