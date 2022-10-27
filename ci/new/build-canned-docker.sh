#!/usr/bin/env bash

BUILD_CONTAINER=bosh-director-build-$(date +%s)-$RANDOM

BOSH_DIRECTOR_TAG=${1:-bosh-director-docker}
BASE_IMAGE=${2:-bosh/main-bosh-docker}

docker run -d -e BOSH_CERT_DIR=/tmp/certs --privileged --name "$BUILD_CONTAINER" "$BASE_IMAGE" sleep infinity

docker exec -e BOSH_CERT_DIR=/tmp/certs $BUILD_CONTAINER bash -c '
    sed -i '"'"'s#certs_dir=$(mktemp -d)#certs_dir=${BOSH_CERT_DIR:-$(mktemp -d /tmp/certs.XXXX)}#'"'"' $(command -v start-bosh)

    [ -n "$BOSH_CERT_DIR" ] && mkdir -p $BOSH_CERT_DIR
    
    # disable automatically calling the bosh director creation, just register the functions.
    sed -i "/main .*\$/d" $(command -v start-bosh)
    source start-bosh

    # run the code in start-bosh
    main

    echo "source /tmp/local-bosh/director/env" >> /etc/profile

    export BOSH0_CONTAINER=$(jq .current_vm_cid -r /tmp/local-bosh/director/state.json)

    docker exec "$BOSH0_CONTAINER" bash -c "
        /var/vcap/bosh/bin/monit stop all
        
        while ! ( /var/vcap/bosh/bin/monit summary | grep -E '"'"'System.*not monitored$'"'"' ); do echo Waiting for monit to stop all jobs; sleep 1; done

        echo Redirecting the volume for /var/vcap/store to the mounted BOSH volume
        umount -f /var/vcap/store
        rm -rf /var/vcap/store; ln -nfs /warden-cpi-dev/vol-* /var/vcap/store
    "

    # remove folders that tie the docker engine to this container
    rm -rf /scratch/docker/tmp /scratch/docker/runtimes
'

docker stop "$BUILD_CONTAINER"

docker tag $(docker commit "$BUILD_CONTAINER") "$BOSH_DIRECTOR_TAG"

docker rm -f "$BUILD_CONTAINER"
