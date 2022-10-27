#!/usr/bin/env bash

set -e
source start-bosh
generate_certs $BOSH_CERT_DIR

echo 'export OUTER_CONTAINER_IP=$(ip route get 8.8.8.8 | head -n1 | cut -d " " -f 7)' >> /tmp/local-bosh/director/env
echo 'export DOCKER_HOST=tcp://$OUTER_CONTAINER_IP:4243' >> /tmp/local-bosh/director/env
echo "export DOCKER_TLS_VERIFY=1" >> /tmp/local-bosh/director/env
echo "export DOCKER_CERT_PATH=$BOSH_CERT_DIR" >> /tmp/local-bosh/director/env

source /tmp/local-bosh/director/env

export

if ! docker ps &>/dev/null; then
  service docker start || ( echo "Failed to start Docker!"
    echo --- docker log ---
    tail -n 50 /var/log/docker.log
    echo --- / docker log ---
    exit 1
  )
fi

docker_retries=10
while ! docker ps &>/dev/null; do 
  echo "Waiting for Docker to start"
  sleep 1
  docker_retries=$(($docker_retries - 1))
  if [ $docker_retries -eq 0 ]; then
    echo "Starting Docker failed"
    echo --- docker log ---
    tail -n 20 /var/log/docker.log
    echo --- / docker log ---
    exit 1
  fi
done


export BOSH0_CONTAINER=$(jq .current_vm_cid -r /tmp/local-bosh/director/state.json)

docker start "$BOSH0_CONTAINER" || (echo could not start bosh/0 && exit 1)

while [ "$(docker container ls -a --format "{{json .State}}" --filter name=$BOSH0_CONTAINER | jq . -r)" != "running" ]; do 
  echo "Waiting for bosh/0 container to start"
  sleep 1
done

docker exec "$BOSH0_CONTAINER" /var/vcap/bosh/bin/monit start all
docker exec "$BOSH0_CONTAINER" bash -c 'while ! ( /var/vcap/bosh/bin/monit summary | grep -E "System.*running\$" ); do echo Waiting for monit to start all jobs; sleep 1; done'

while ! bosh env &>/dev/null; do
  echo "Waiting for BOSH Director to respond"
  sleep 1
done
bosh env
