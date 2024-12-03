#!/bin/bash

set -eux

source ./src/meta-info/blobs-versions.env
BLOBS_TMP_DIR=".blobs"

mkdir -p "$BLOBS_TMP_DIR"

function down_add_blob {
  BLOBS_GROUP=$1
  FILE=$2
  URL=$3
  if [ ! -f "blobs/${BLOBS_GROUP}/${FILE}" ];then
    echo "Downloads resource from the Internet ($URL -> $BLOBS_TMP_DIR/$FILE)"
    curl -L "$URL" --output "$BLOBS_TMP_DIR/$FILE"
    echo "Adds blob ($BLOBS_TMP_DIR/$FILE -> $BLOBS_GROUP/$FILE), starts tracking blob in config/blobs.yml for inclusion in packages"
    bosh add-blob "$BLOBS_TMP_DIR/$FILE" "$BLOBS_GROUP/$FILE"
  fi
}

# down_add_blob "haproxy" "haproxy-${HAPROXY_1_8_VERSION}.tar.gz" "$HAPROXY_1_8_URL"
# down_add_blob "haproxy" "haproxy-${HAPROXY_1_9_VERSION}.tar.gz" "$HAPROXY_1_9_URL"

down_add_blob "haproxy" "haproxy-${HAPROXY_2_8_VERSION}.tar.gz" "$HAPROXY_2_8_URL"
down_add_blob "haproxy" "haproxy-${HAPROXY_2_9_VERSION}.tar.gz" "$HAPROXY_2_9_URL"
down_add_blob "haproxy" "haproxy-${HAPROXY_3_0_VERSION}.tar.gz" "$HAPROXY_3_0_URL"
down_add_blob "haproxy" "haproxy-${HAPROXY_3_1_VERSION}.tar.gz" "$HAPROXY_3_1_URL"

down_add_blob "haproxy" "hatop-${HATOP_VERSION}" "$HATOP_URL"
down_add_blob "haproxy" "lua-${LUA_VERSION}.tar.gz" "$LUA_URL"
down_add_blob "haproxy" "pcre2-${PCRE2_VERSION}.tar.gz" "$PCRE2_URL"
down_add_blob "haproxy" "socat-${SOCAT_VERSION}.tar.gz" "$SOCAT_URL"
down_add_blob "keepalived" "keepalived-${KEEPALIVED_VERSION}.tar.gz" "$KEEPALIVED_URL"

echo "Download blobs into blobs/ based on config/blobs.yml"
bosh sync-blobs

echo "Upload previously added blobs that were not yet uploaded to the blobstore. Updates config/blobs.yml with returned blobstore IDs."
bosh upload-blobs
