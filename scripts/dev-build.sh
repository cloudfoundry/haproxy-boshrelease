#!/usr/bin/env bash
#
# dev-build.sh
#
# Builds HAProxy release variants locally and uploads them to the BOSH director.
#
# Usage: ./scripts/dev-build.sh [--upload-only] [--version VERSION] [--output-dir DIR] [variant...]
#
# Variants:
#   openssl, openssl-patched, awslc, awslc-patched, awslc-fips, awslc-fips-patched, multi
#
# If no variants are specified, all 7 are built.
#
# Examples:
#   ./scripts/dev-build.sh                          # build all 7, version=dev
#   ./scripts/dev-build.sh multi                    # build only multi, version=dev
#   ./scripts/dev-build.sh --version 1.0 multi      # build only multi, version=1.0
#   ./scripts/dev-build.sh awslc awslc-fips         # build awslc and awslc-fips
#   ./scripts/dev-build.sh --upload-only            # upload previously built releases
#
# Prerequisites:
#   - All blobs present locally (bosh add-blob done for aws-lc, cmake, golang, aws-lc-fips)
#   - haproxy-patches/ directory exists with .patch files
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

ALL_VARIANTS=(openssl openssl-patched awslc awslc-patched awslc-fips awslc-fips-patched multi)

is_variant() {
  local arg="$1"
  for v in "${ALL_VARIANTS[@]}"; do
    [[ "$v" == "$arg" ]] && return 0
  done
  return 1
}

UPLOAD_ONLY=false
VERSION="dev"
OUTPUT_DIR="./dev-releases"
VARIANTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upload-only)
      UPLOAD_ONLY=true
      shift
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      if is_variant "$1"; then
        VARIANTS+=("$1")
      else
        echo "Unknown argument: $1" >&2
        echo "Valid variants: ${ALL_VARIANTS[*]}" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ ${#VARIANTS[@]} -eq 0 ]]; then
  VARIANTS=("${ALL_VARIANTS[@]}")
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

copy_multi_packages() {
  cp -r packages-multi/* packages/
}

remove_multi_packages() {
  for dir in packages-multi/*/; do
    rm -rf "packages/$(basename "$dir")"
  done
}

cleanup() {
  echo "$SPEC_ORIG" > "$SPEC_FILE"
  echo "$JOB_SPEC_ORIG" > "$JOB_SPEC_FILE"
  remove_multi_packages
  rm -f haproxy-patches.tar.gz
}
trap cleanup EXIT

reset_spec() {
  echo "$SPEC_ORIG" > "$SPEC_FILE"
  echo "$JOB_SPEC_ORIG" > "$JOB_SPEC_FILE"
}

add_patches_to_spec() {
  echo "- haproxy/patches.tar.gz" >> "$SPEC_FILE"
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
  add_patches_to_spec
  tar -czf haproxy-patches.tar.gz haproxy-patches
  bosh add-blob haproxy-patches.tar.gz haproxy/patches.tar.gz
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
  add_patches_to_spec
  echo "- haproxy/aws-lc-v*.tar.gz" >> "$SPEC_FILE"
  echo "- haproxy/cmake-*.tar.gz" >> "$SPEC_FILE"
  tar -czf haproxy-patches.tar.gz haproxy-patches
  bosh add-blob haproxy-patches.tar.gz haproxy/patches.tar.gz
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
  add_patches_to_spec
  echo "- haproxy/aws-lc-fips-*.tar.gz" >> "$SPEC_FILE"
  echo "- haproxy/cmake-*.tar.gz" >> "$SPEC_FILE"
  echo "- haproxy/golang-*.tar.gz" >> "$SPEC_FILE"
  tar -czf haproxy-patches.tar.gz haproxy-patches
  bosh add-blob haproxy-patches.tar.gz haproxy/patches.tar.gz
  build_release "awslc-fips-patched"
fi

# --- 7. Multi (all variants, property-driven selection) ---
if should_build multi; then
  reset_spec
  copy_multi_packages
  tar -czf haproxy-patches.tar.gz haproxy-patches
  bosh add-blob haproxy-patches.tar.gz haproxy/patches.tar.gz
  sed -i.bak 's/^- haproxy$/- haproxy-openssl\n- haproxy-openssl-patched\n- haproxy-awslc\n- haproxy-awslc-patched\n- haproxy-awslc-fips\n- haproxy-awslc-fips-patched/' "$JOB_SPEC_FILE"
  rm -f "${JOB_SPEC_FILE}.bak"
  build_release "multi"
  remove_multi_packages
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
