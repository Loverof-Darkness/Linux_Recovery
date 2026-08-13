#!/usr/bin/env bash
# Builds a reproducible-ish source ZIP after exercising DEVIL's local tests.
set -Eeuo pipefail
IFS=$' \t\n'

readonly ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly DIST="$ROOT/dist"
readonly VERSION="$(sed -n 's/^readonly DEVIL_VERSION="\([^"]*\)"/\1/p' "$ROOT/core/bootstrap.sh")"

fail() { printf 'DEVIL release: %s\n' "$*" >&2; exit 1; }
[[ -n "$VERSION" ]] || fail 'could not derive project version'
command -v zip >/dev/null 2>&1 || fail 'zip is required to build a ZIP release'

bash "$ROOT/tests/smoke.sh"
mkdir -p -- "$DIST"
archive="$DIST/DEVIL-v$VERSION.zip"
rm -f -- "$archive"
(
  cd "$ROOT"
  zip -qr "$archive" . \
    -x '.git/*' '.agents/*' '.codex/*' 'dist/*' 'DEVIL-v*.zip' '*.swp' '*~'
)
unzip -tq "$archive" >/dev/null
printf 'Release archive: %s\n' "$archive"
