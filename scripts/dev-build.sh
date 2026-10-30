#!/usr/bin/env bash
#
# dev-build.sh
#
# Builds the HAProxy release locally and uploads it to the BOSH director.
#
# Usage: ./scripts/dev-build.sh [--upload-only] [--version BASE] [--output-dir DIR]
##
# Versioning:
#   Each invocation produces a release version of the form <BASE>+dev.<unix_timestamp>
#   e.g. "16.9.0+dev.1779286286". BASE defaults to the highest existing final release in
#   releases/haproxy/ and can be overridden with --version. Each run uses a fresh timestamp.
#
# Examples:
#   ./scripts/dev-build.sh                          # build and upload, BASE=highest final release
#   ./scripts/dev-build.sh --version 17.0.0         # same, and override BASE
#   ./scripts/dev-build.sh --upload-only            # no build, only upload everything in builds/
#   ./scripts/dev-build.sh --fix                    # force re-upload AND full recompile (corrupt blobstore)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

UPLOAD_ONLY=false
BASE_VERSION=""
OUTPUT_DIR="./builds"
BOSH_UPLOAD_RELEASE_OPTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upload-only)
      UPLOAD_ONLY=true
      shift
      ;;
    --fix)
      BOSH_UPLOAD_RELEASE_OPTS+=(--fix)
      shift
      ;;
    --version)
      BASE_VERSION="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Derive base version from the highest existing final release if --version not given.
if [[ -z "$BASE_VERSION" ]]; then
  BASE_VERSION=$(
    ls releases/haproxy/haproxy-*.yml 2>/dev/null \
      | sed 's|.*/haproxy-||;s|\.yml$||;s|+.*||' \
      | sort -V \
      | tail -1
  )
  BASE_VERSION="${BASE_VERSION:-0.0.0}"
fi

TIMESTAMP=$(date +%s)
mkdir -p "$OUTPUT_DIR"

if [[ "$UPLOAD_ONLY" == false ]]; then
  VERSION="${BASE_VERSION}+dev.${TIMESTAMP}"
  TARBALL="$OUTPUT_DIR/haproxy-${VERSION}.tgz"

  echo ""
  echo "========================================"
  echo "  Building: haproxy (version: $VERSION)"
  echo "========================================"
  echo ""

  bosh -n create-release --force \
    --name "haproxy" \
    --version "$VERSION" \
    --tarball "$TARBALL"

  echo "  -> $TARBALL"
fi

# --- Upload release(s) ---
echo ""
echo "========================================"
echo "  Uploading releases to BOSH director"
echo "========================================"
echo ""

if [[ "$UPLOAD_ONLY" == true ]]; then
  upload_glob="$OUTPUT_DIR/haproxy-*.tgz"
else
  upload_glob="$OUTPUT_DIR/haproxy-*.${TIMESTAMP}.tgz"
fi

shopt -s nullglob
uploaded=0
for tgz in $upload_glob; do
  echo "Uploading: $tgz"
  bosh upload-release "$tgz" "${BOSH_UPLOAD_RELEASE_OPTS[@]}"
  uploaded=$((uploaded + 1))
done
shopt -u nullglob

if [[ $uploaded -eq 0 ]]; then
  echo "No tarballs matching '$upload_glob' to upload." >&2
  exit 1
fi

echo ""
echo "Done."
