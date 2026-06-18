#!/usr/bin/env bash
#
# dev-build.sh
#
# Builds HAProxy release variants locally and uploads them to the BOSH director.
#
# Usage: ./scripts/dev-build.sh [--upload-only] [--version BASE] [--output-dir DIR] [variant...]
#
# Variants:
#   openssl, openssl-patched, awslc, awslc-patched, awslc-fips, awslc-fips-patched, multi
#
# If no variants are specified, all 7 are built.
#
# Versioning:
#   Each invocation produces release versions of the form
#       <BASE>+dev[-<variant>].<unix_timestamp>
#   e.g. "16.9.0+dev.1779286286" (openssl), "16.9.0+dev-awslc.1779286286" (awslc).
#   BASE defaults to the highest existing final release in releases/haproxy/ (or 0.0.0 if none),
#   and can be overridden with --version. Each run uses a fresh timestamp, so previously
#   built tarballs do not need to be deleted before rebuilding.
#
# Examples:
#   ./scripts/dev-build.sh                          # build all 7, BASE=highest final release
#   ./scripts/dev-build.sh multi                    # build only multi
#   ./scripts/dev-build.sh --version 17.0.0 multi   # override BASE
#   ./scripts/dev-build.sh awslc awslc-fips         # build awslc and awslc-fips
#   ./scripts/dev-build.sh --upload-only            # upload everything in builds/
#
# Prerequisites:
#   - All blobs present locally (bosh add-blob done for aws-lc, cmake, golang, aws-lc-fips)
#   - haproxy-patches/ directory exists with .patch files
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Pull in AWS_LC_VERSION / AWS_LC_FIPS_VERSION so they can be embedded in
# variant suffixes — keeps dev tarball filenames self-describing.
# shellcheck disable=SC1091
source src/haproxy-versions.sh

ALL_VARIANTS=(openssl openssl-patched awslc awslc-patched awslc-fips awslc-fips-patched multi)

is_variant() {
  local arg="$1"
  for v in "${ALL_VARIANTS[@]}"; do
    [[ "$v" == "$arg" ]] && return 0
  done
  return 1
}

# Map a variant name to the suffix used in the BOSH release version, embedding
# the upstream AWS-LC versions so tarballs are self-describing. Mirrors the
# scheme in ci/scripts/shipit so dev and CI artifacts agree.
variant_suffix() {
  case "$1" in
    awslc)              echo "awslc-${AWS_LC_VERSION}" ;;
    awslc-patched)      echo "awslc-${AWS_LC_VERSION}-patched" ;;
    awslc-fips)         echo "awslc-fips-${AWS_LC_FIPS_VERSION}" ;;
    awslc-fips-patched) echo "awslc-fips-${AWS_LC_FIPS_VERSION}-patched" ;;
    multi)              echo "multi-awslc-${AWS_LC_VERSION}-fips-${AWS_LC_FIPS_VERSION}" ;;
    *)                  echo "$1" ;;
  esac
}

UPLOAD_ONLY=false
BASE_VERSION=""
OUTPUT_DIR="./builds"
VARIANTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upload-only)
      UPLOAD_ONLY=true
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

# Derive base version from the highest existing final release if --version not given.
# Final releases live in releases/haproxy/haproxy-<MAJOR.MINOR.PATCH>[+meta].yml
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
  local suffix="dev"
  [[ -n "$variant" ]] && suffix="dev-$(variant_suffix "$variant")"
  local version="${BASE_VERSION}+${suffix}.${TIMESTAMP}"
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
  sed -i.bak 's/^- haproxy$/- haproxy-deps\n- haproxy-openssl\n- haproxy-openssl-patched\n- haproxy-awslc\n- haproxy-awslc-patched\n- haproxy-awslc-fips\n- haproxy-awslc-fips-patched/' "$JOB_SPEC_FILE"
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

if [[ "$UPLOAD_ONLY" == true ]]; then
  upload_glob="$OUTPUT_DIR/haproxy-*.tgz"
else
  upload_glob="$OUTPUT_DIR/haproxy-*.${TIMESTAMP}.tgz"
fi

shopt -s nullglob
uploaded=0
for tgz in $upload_glob; do
  echo "Uploading: $tgz"
  bosh upload-release "$tgz" --fix
  uploaded=$((uploaded + 1))
done
shopt -u nullglob

if [[ $uploaded -eq 0 ]]; then
  echo "No tarballs matching '$upload_glob' to upload." >&2
  exit 1
fi

echo ""
echo "Done."
