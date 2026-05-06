#!/usr/bin/env bash
#
# dev-build.sh
#
# Builds HAProxy release variants locally and uploads them to the BOSH director.
#
# Usage: ./dev-build.sh [--upload-only] [version] [output_dir] [variant...]
#
# Variants:
#   openssl, openssl-patched, awslc, awslc-patched, awslc-fips, awslc-fips-patched, multi
#
# If no variants are specified, all 7 are built.
#
# Prerequisites:
#   - All blobs present locally (bosh add-blob done for aws-lc, cmake, golang, aws-lc-fips)
#   - haproxy-patches/ directory exists with .patch files
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

UPLOAD_ONLY=false
if [[ "${1:-}" == "--upload-only" ]]; then
  UPLOAD_ONLY=true
  shift
fi

VERSION="${1:-dev}"
OUTPUT_DIR="${2:-./dev-releases}"
shift 2 2>/dev/null || true

VARIANTS=("$@")
if [[ ${#VARIANTS[@]} -eq 0 ]]; then
  VARIANTS=(openssl openssl-patched awslc awslc-patched awslc-fips awslc-fips-patched multi)
fi

should_build() {
  local variant="$1"
  for v in "${VARIANTS[@]}"; do
    [[ "$v" == "$variant" ]] && return 0
  done
  return 1
}

mkdir -p "$OUTPUT_DIR"

if [[ "$UPLOAD_ONLY" == false ]]; then

SPEC_FILE="packages/haproxy/spec"
SPEC_ORIG=$(cat "$SPEC_FILE")
JOB_SPEC_FILE="jobs/haproxy/spec"
JOB_SPEC_ORIG=$(cat "$JOB_SPEC_FILE")

cleanup() {
  echo "$SPEC_ORIG" > "$SPEC_FILE"
  echo "$JOB_SPEC_ORIG" > "$JOB_SPEC_FILE"
  rm -f haproxy-patches.tar.gz
}
trap cleanup EXIT

reset_spec() {
  echo "$SPEC_ORIG" > "$SPEC_FILE"
  echo "$JOB_SPEC_ORIG" > "$JOB_SPEC_FILE"
  rm -f haproxy-patches.tar.gz
}

add_patches() {
  echo "- haproxy/patches.tar.gz" >> "$SPEC_FILE"
  tar -czf haproxy-patches.tar.gz haproxy-patches
  bosh add-blob haproxy-patches.tar.gz haproxy/patches.tar.gz
}

build_release() {
  local variant="$1"
  local version="$VERSION"
  [[ -n "$variant" ]] && version="${VERSION}-${variant}"
  local tarball="$OUTPUT_DIR/haproxy-${version}.tgz"

  echo ""
  echo "========================================"
  echo "  Building: haproxy (version: $version)"
  echo "========================================"
  echo ""

  bosh -n create-release --force \
    --name "haproxy" \
    --version "$version" \
    --tarball "$tarball"

  echo "  -> $tarball"
}

# --- 1. OpenSSL (base) ---
if should_build openssl; then
  reset_spec
  build_release ""
fi

# --- 2. OpenSSL + Patched ---
if should_build openssl-patched; then
  reset_spec
  add_patches
  build_release "patched"
fi

# --- 3. AWS-LC ---
if should_build awslc; then
  reset_spec
  echo "- haproxy/aws-lc-v*.tar.gz" >> "$SPEC_FILE"
  echo "- haproxy/cmake-*.tar.gz" >> "$SPEC_FILE"
  build_release "awslc"
fi

# --- 4. AWS-LC + Patched ---
if should_build awslc-patched; then
  reset_spec
  add_patches
  echo "- haproxy/aws-lc-v*.tar.gz" >> "$SPEC_FILE"
  echo "- haproxy/cmake-*.tar.gz" >> "$SPEC_FILE"
  build_release "awslc-patched"
fi

# --- 5. AWS-LC FIPS ---
if should_build awslc-fips; then
  reset_spec
  echo "- haproxy/aws-lc-fips-*.tar.gz" >> "$SPEC_FILE"
  echo "- haproxy/cmake-*.tar.gz" >> "$SPEC_FILE"
  echo "- haproxy/golang-*.tar.gz" >> "$SPEC_FILE"
  build_release "awslc-fips"
fi

# --- 6. AWS-LC FIPS + Patched ---
if should_build awslc-fips-patched; then
  reset_spec
  add_patches
  echo "- haproxy/aws-lc-fips-*.tar.gz" >> "$SPEC_FILE"
  echo "- haproxy/cmake-*.tar.gz" >> "$SPEC_FILE"
  echo "- haproxy/golang-*.tar.gz" >> "$SPEC_FILE"
  build_release "awslc-fips-patched"
fi

# --- 7. Multi (all variants, property-driven selection) ---
if should_build multi; then
  reset_spec
  # Modify job spec: replace '- haproxy' package with all variant packages
  sed -i.bak 's/^- haproxy$/- haproxy-openssl\n- haproxy-openssl-patched\n- haproxy-awslc\n- haproxy-awslc-patched\n- haproxy-awslc-fips\n- haproxy-awslc-fips-patched/' "$JOB_SPEC_FILE"
  rm -f "${JOB_SPEC_FILE}.bak"
  # Include patches blob for patched variant packages
  add_patches
  build_release "multi"
fi

fi # UPLOAD_ONLY

# --- Upload all releases ---
echo ""
echo "========================================"
echo "  Uploading releases to BOSH director"
echo "========================================"
echo ""

for tgz in "$OUTPUT_DIR"/haproxy-"${VERSION}"*.tgz; do
  echo "Uploading: $tgz"
  bosh upload-release "$tgz" --fix
done

echo ""
echo "Done."
