#!/usr/bin/env bash

set -e

if [ -z "$CONCOURSE_TARGET" ]; then
    echo "Missing CONCOURSE_TARGET env var."
    exit 1
fi

if [ -z "$CONCOURSE_URL" ]; then
    echo "Missing CONCOURSE_URL env var."
    exit 1
fi

if [ -z "$CONCOURSE_USER" ]; then
    echo "Missing CONCOURSE_USER env var."
    exit 1
fi

if [ -z "$CONCOURSE_PASSWORD" ]; then
    echo "Missing CONCOURSE_PASSWORD env var."
    exit 1
fi

if [ ! -f "vars.yml" ]; then
    echo "Missing vars.yml. Please create it first."
    exit 1
fi


fly -t "$CONCOURSE_TARGET" login -c "$CONCOURSE_URL" -u "$CONCOURSE_USER" -p "$CONCOURSE_PASSWORD"
fly -t "$CONCOURSE_TARGET" validate-pipeline -c pipeline.yml
fly -t "$CONCOURSE_TARGET" set-pipeline -p haproxy-boshrelease -c pipeline.yml --load-vars-from vars.yml
fly -t "$CONCOURSE_TARGET" expose-pipeline -p haproxy-boshrelease

echo "Done."
