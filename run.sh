#!/usr/bin/env bash
# DEVIL launcher: always resolves paths from this checkout.
set -Eeuo pipefail
IFS=$' \t\n'

readonly PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly MAIN="$PROJECT_DIR/devil"

fail() { printf 'DEVIL launcher: %s\n' "$*" >&2; exit 1; }
[[ -f "$MAIN" ]] || fail "missing executable: $MAIN"
[[ -f "$PROJECT_DIR/assets/devil.png" ]] || fail "missing branding asset: assets/devil.png"
[[ ${BASH_VERSINFO[0]} -ge 5 ]] || fail "Bash 5 or newer is required"

find "$PROJECT_DIR" -type f \( -name '*.sh' -o -name 'devil' \) -exec chmod u+x {} + 2>/dev/null || true
exec "$MAIN" "$@"
