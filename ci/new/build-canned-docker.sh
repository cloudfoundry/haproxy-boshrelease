#!/usr/bin/env bash

BUILD_CONTAINER=bosh-director-build-$(date +%s)-$RANDOM

docker run -d -e BOSH_CERT_DIR=/tmp/certs --privileged --name $BUILD_CONTAINER bosh/docker-cpi:main sleep infinity

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

docker tag $(docker commit "$BUILD_CONTAINER") bosh-director-docker 

docker rm -f "$BUILD_CONTAINER"

docker run -d --privileged --name canned-bosh bosh-director-docker

docker exec -t -e BOSH_CERT_DIR=/tmp/certs canned-bosh bash -l -c '
    source start-bosh
    generate_certs $BOSH_CERT_DIR

    echo '"'"'export OUTER_CONTAINER_IP=$(ip route get 8.8.8.8 | head -n1 | cut -d " " -f 8)'"'"' >> /etc/profile
    echo '"'"'export DOCKER_HOST=tcp://$OUTER_CONTAINER_IP:4243'"'"' >> /etc/profile
    echo "export DOCKER_TLS_VERIFY=1" >> /etc/profile
    echo "export DOCKER_CERT_PATH=$BOSH_CERT_DIR" >> /etc/profile

    source /etc/profile

    service docker start || echo "Failed to start Docker!"

    while ! docker ps > /dev/null; do echo "Waiting for Docker to start"; sleep 1; done;

    export BOSH0_CONTAINER=$(jq .current_vm_cid -r /tmp/local-bosh/director/state.json)

    docker start "$BOSH0_CONTAINER"

    while [ "$(docker container ls -a --format "{{json .State}}" --filter name=$BOSH0_CONTAINER | jq . -r)" != "running" ]; do echo Waiting for bosh/0 container to start; sleep 1; done;

    docker exec "$BOSH0_CONTAINER" /var/vcap/bosh/bin/monit start all
    docker exec "$BOSH0_CONTAINER" bash -c "while ! ( /var/vcap/bosh/bin/monit summary | grep -E '"'"'System.*running$'"'"' ); do echo Waiting for monit to start all jobs; sleep 1; done"
    bosh env
'
