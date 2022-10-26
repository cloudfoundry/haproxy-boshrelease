#!/usr/bin/env bash

set -eo pipefail

mkdir -p /etc/docker

cat <<EOF > /etc/docker/daemon.json
{
  "storage-driver": "vfs"
}
EOF
service docker start

BUILD_CONTAINER=bosh-director-build-$(date +%s)-$RANDOM

docker run -d -e BOSH_CERT_DIR=/tmp/certs --privileged --name $BUILD_CONTAINER bosh/docker-cpi:main sleep infinity

docker exec -it -e BOSH_CERT_DIR=/tmp/certs $BUILD_CONTAINER bash -c '
    sed -i '"'"'s#certs_dir=$(mktemp -d)#certs_dir=${BOSH_CERT_DIR:-$(mktemp -d /tmp/certs.XXXX)}#'"'"' $(command -v start-bosh)
    sed -i '"'"'s/^{/{\n  "storage-driver": "vfs"/g'"'"' $(command -v start-bosh)
    [ -n "$BOSH_CERT_DIR" ] && mkdir -p $BOSH_CERT_DIR
    source start-bosh

    echo "export DOCKER_TLS_VERIFY=1" >> /etc/profile
    echo "export DOCKER_HOST=$DOCKER_HOST" >> /etc/profile
    echo "export DOCKER_CERT_PATH=$DOCKER_CERT_PATH" >> /etc/profile

    echo "source /tmp/local-bosh/director/env" >> /etc/profile

    docker exec $(jq .current_vm_cid -r /tmp/local-bosh/director/state.json) bash -c "
        /var/vcap/bosh/bin/monit stop all
        
        while ! ( /var/vcap/bosh/bin/monit summary | grep -E '"'"'System.*not monitored$'"'"' ); do echo Waiting for monit to stop all jobs; sleep 1; done

        echo Redirecting the volume for /var/vcap/store to the mounted BOSH volume
        umount -f /var/vcap/store
        rm -rf /var/vcap/store; ln -nfs /warden-cpi-dev/vol-* /var/vcap/store
    "

    docker restart $(jq .current_vm_cid -r /tmp/local-bosh/director/state.json)

    docker exec $(jq .current_vm_cid -r /tmp/local-bosh/director/state.json) bash -c "while ! ( /var/vcap/bosh/bin/monit summary | grep -E '"'"'System.*running$'"'"' ); do echo Waiting for monit to start all jobs; sleep 1; done"

    bosh env
'

docker stop $BUILD_CONTAINER

docker container commit $BUILD_CONTAINER bosh-director-docker:latest
docker login iacbox.common.repositories.cloud.sap -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
docker image tag bosh-director-docker:latest iacbox.common.repositories.cloud.sap/bosh-director-docker:latest

docker rm -f $BUILD_CONTAINER

docker run -d --name canned-bosh bosh-director-docker

docker exec -it -e BOSH_CERT_DIR=/tmp/certs canned-bosh bash -l -c '
    service docker start
    source /etc/profile

    while ! docker ps > /dev/null; do echo "Waiting for Docker to start"; sleep 1; done;

    docker start $(jq .current_vm_cid -r /tmp/local-bosh/director/state.json)
    docker exec $(jq .current_vm_cid -r /tmp/local-bosh/director/state.json) /var/vcap/bosh/bin/monit start all
    docker exec $(jq .current_vm_cid -r /tmp/local-bosh/director/state.json) bash -c "while ! ( /var/vcap/bosh/bin/monit summary | grep -E '"'"'System.*running$'"'"' ); do echo Waiting for monit to start all jobs; sleep 1; done"
    bosh env

    exec bash
'
