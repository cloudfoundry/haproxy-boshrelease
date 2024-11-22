#!/usr/bin/env bash

set -e

if [ ! -f "vars.yml" ]; then
    echo "Missing vars.yml. Please create it first."
    exit 1
fi

echo "Please follow https://github.com/cloudfoundry/routing-concourse/blob/main/README.md#authentication-to-concourse for login."

! fly status -t networking-extensions >/dev/null && \
    fly -t networking-extensions login -c https://concourse.arp.cloudfoundry.org/
fly -t networking-extensions validate-pipeline -c pipeline.yml
fly -t networking-extensions set-pipeline -p haproxy-boshrelease -c pipeline.yml --load-vars-from vars.yml
fly -t networking-extensions expose-pipeline -p haproxy-boshrelease

echo "Done."
