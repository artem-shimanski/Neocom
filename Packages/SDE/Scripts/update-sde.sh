#!/bin/sh
# Installs the SDE build DogmaKit was imported from into Packages/SDE and rebuilds the databases.
set -eu

SELF=$(cd "$(dirname "$0")/.." && pwd)

usage() {
    cat <<USAGE
Usage: Scripts/update-sde.sh [--check] [-h] [LANGUAGE...]

  --check   print requested, cached, linked and latest builds; change nothing
  LANGUAGE  languages for build-sde (default: all)

The build is the one DogmaKit's SDEVersion names. DogmaKit is taken from \$DOGMAKIT_DIR
(a local checkout) or from the package's resolved checkout.
Cache: \$EVE_SDE_CACHE, default ~/Library/Caches/EVE-SDE.
USAGE
}

check=
case ${1:-} in
    -h|--help) usage; exit 0 ;;
    --check) check=--check; shift ;;
esac

dogmakit=${DOGMAKIT_DIR:-$SELF/.build/checkouts/DogmaKit}
if [ -z "${DOGMAKIT_DIR:-}" ]; then
    xcrun swift package --package-path "$SELF" resolve
fi
version=$dogmakit/Sources/DogmaIDs/Generated/SDEVersion.swift
[ -f "$version" ] || { echo "$version not found: DogmaKit is older than 0.2.1" >&2; exit 1; }
build=$(sed -n 's/.*buildNumber[^0-9]*\([0-9][0-9]*\).*/\1/p' "$version" | head -n 1)
[ -n "$build" ] || { echo "cannot read buildNumber from $version" >&2; exit 1; }

if [ -n "$check" ]; then
    exec "$dogmakit/Scripts/update-sde.sh" --build "$build" --package "$SELF" --check
fi
exec "$dogmakit/Scripts/update-sde.sh" --build "$build" --package "$SELF" --command build-sde -- "$@"
