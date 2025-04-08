#!/usr/bin/env bash

set -eo pipefail

function generate_certs() {
  local certs_dir
  certs_dir="${1}"

  pushd "${certs_dir}"

    jq -ner --arg "ip" "${OUTER_CONTAINER_IP}" '{
      "variables": [
        {
          "name": "docker_ca",
          "type": "certificate",
          "options": {
            "is_ca": true,
            "common_name": "ca"
          }
        },
        {
          "name": "docker_tls",
          "type": "certificate",
          "options": {
            "extended_key_usage": [
              "server_auth"
            ],
            "common_name": $ip,
            "alternative_names": [ $ip ],
            "ca": "docker_ca"
          }
        },
        {
          "name": "client_docker_tls",
          "type": "certificate",
          "options": {
            "extended_key_usage": [
              "client_auth"
            ],
            "common_name": $ip,
            "alternative_names": [ $ip ],
            "ca": "docker_ca"
          }
        }
      ]
    }' > ./bosh-vars.yml

   bosh int ./bosh-vars.yml --vars-store=./certs.yml
   bosh int ./certs.yml --path=/docker_ca/ca > ./ca.pem
   bosh int ./certs.yml --path=/docker_tls/certificate > ./server-cert.pem
   bosh int ./certs.yml --path=/docker_tls/private_key > ./server-key.pem
   bosh int ./certs.yml --path=/client_docker_tls/certificate > ./cert.pem
   bosh int ./certs.yml --path=/client_docker_tls/private_key > ./key.pem
    # generate certs in json format
    #
   ruby -e 'puts File.read("./ca.pem").split("\n").join("\\n")' > "$certs_dir/ca_json_safe.pem"
   ruby -e 'puts File.read("./cert.pem").split("\n").join("\\n")' > "$certs_dir/client_certificate_json_safe.pem"
   ruby -e 'puts File.read("./key.pem").split("\n").join("\\n")' > "$certs_dir/client_private_key_json_safe.pem"
  popd
}

function sanitize_cgroups() {
  mkdir -p /sys/fs/cgroup
  mountpoint -q /sys/fs/cgroup || \
    mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup

  mount -o remount,rw /sys/fs/cgroup

  sed -e 1d /proc/cgroups | while read sys hierarchy num enabled; do
    if [ "$enabled" != "1" ]; then
      # subsystem disabled; skip
      continue
    fi

    grouping="$(cat /proc/self/cgroup | cut -d: -f2 | grep "\\<$sys\\>")"
    if [ -z "$grouping" ]; then
      # subsystem not mounted anywhere; mount it on its own
      grouping="$sys"
    fi

    mountpoint="/sys/fs/cgroup/$grouping"

    mkdir -p "$mountpoint"

    # clear out existing mount to make sure new one is read-write
    if mountpoint -q "$mountpoint"; then
      umount "$mountpoint"
    fi

    mount -n -t cgroup -o "$grouping" cgroup "$mountpoint"

    if [ "$grouping" != "$sys" ]; then
      if [ -L "/sys/fs/cgroup/$sys" ]; then
        rm "/sys/fs/cgroup/$sys"
      fi

      ln -s "$mountpoint" "/sys/fs/cgroup/$sys"
    fi
  done
}

source "ci/scripts/functions-ci.sh"

function start_docker() {
  generate_certs "$1"
  local mtu
  mkdir -p /var/log
  mkdir -p /var/run

  sanitize_cgroups

  # ensure systemd cgroup is present
  mkdir -p /sys/fs/cgroup/systemd
  if ! mountpoint -q /sys/fs/cgroup/systemd ; then
    mount -t cgroup -o none,name=systemd cgroup /sys/fs/cgroup/systemd
  fi

  # check for /proc/sys being mounted readonly, as systemd does
  if grep '/proc/sys\s\+\w\+\s\+ro,' /proc/mounts >/dev/null; then
    mount -o remount,rw /proc/sys
  fi

  mtu=$(cat /sys/class/net/$(ip route get 8.8.8.8|awk '{ print $5 }')/mtu)

  [[ ! -d /etc/docker ]] && mkdir /etc/docker
  cat <<EOF > /etc/docker/daemon.json
{
  "hosts": ["${DOCKER_HOST}","unix:///var/run/docker.sock"],
  "tls": true,
  "tlscert": "${certs_dir}/server-cert.pem",
  "tlskey": "${certs_dir}/server-key.pem",
  "tlscacert": "${certs_dir}/ca.pem",
  "mtu": ${mtu},
  "data-root": "/scratch/docker",
  "tlsverify": true
}
EOF

  service docker start

  export DOCKER_TLS_VERIFY=1
  export DOCKER_CERT_PATH=$1

  rc=1
  for i in $(seq 1 10); do
    echo waiting for docker to come up...
    sleep 10
    set +e
    docker info
    rc=$?
    set -e
    if [ "$rc" -eq "0" ]; then
      break
    else
      service docker restart
      sleep 20
    fi
  done

  if [ "$rc" -ne "0" ]; then
    echo "Failed starting docker. Exiting."
    exit 1
  fi

  if [ -z "${KEEP_RUNNING}" ] ; then
      trap stop_docker ERR
  fi
  echo "$certs_dir"
}

function main() {
  export OUTER_CONTAINER_IP=$(ruby -rsocket -e 'puts Socket.ip_address_list
                          .reject { |addr| !addr.ip? || addr.ipv4_loopback? || addr.ipv6? }
                          .map { |addr| addr.ip_address }.first')

  export DOCKER_HOST="tcp://${OUTER_CONTAINER_IP}:4243"

  local certs_dir
  certs_dir=$(mktemp -d)
  start_docker "${certs_dir}"

  local local_bosh_dir
  local_bosh_dir="/tmp/local-bosh/director"

  if ! docker network ls | grep director_network; then
    docker network create -d bridge --subnet=10.245.0.0/16 director_network
  fi

  compilation_ops="$PWD/ci/compilation.yml"
  pushd "${BOSH_DEPLOYMENT_PATH:-/usr/local/bosh-deployment}" > /dev/null
      export BOSH_DIRECTOR_IP="10.245.0.3"
      export BOSH_ENVIRONMENT="docker-director"

      mkdir -p ${local_bosh_dir}

      command bosh int bosh.yml \
        -o docker/cpi.yml \
        -o jumpbox-user.yml \
        -v director_name=docker \
        -v internal_cidr=10.245.0.0/16 \
        -v internal_gw=10.245.0.1 \
        -v internal_ip="${BOSH_DIRECTOR_IP}" \
        -v docker_host="${DOCKER_HOST}" \
        -v network=director_network \
        -v docker_tls="{\"ca\": \"$(cat "${certs_dir}"/ca_json_safe.pem)\",\"certificate\": \"$(cat "${certs_dir}"/client_certificate_json_safe.pem)\",\"private_key\": \"$(cat "${certs_dir}"/client_private_key_json_safe.pem)\"}" \
        ${@} > "${local_bosh_dir}/bosh-director.yml"

      command bosh create-env "${local_bosh_dir}/bosh-director.yml" \
              --vars-store="${local_bosh_dir}/creds.yml" \
              --state="${local_bosh_dir}/state.json"

      bosh int "${local_bosh_dir}/creds.yml" --path /director_ssl/ca > "${local_bosh_dir}/ca.crt"
      bosh -e "${BOSH_DIRECTOR_IP}" --ca-cert "${local_bosh_dir}/ca.crt" alias-env "${BOSH_ENVIRONMENT}"

      cat <<EOF > "${local_bosh_dir}/env"
      export BOSH_ENVIRONMENT="${BOSH_ENVIRONMENT}"
      export BOSH_CLIENT=admin
      export BOSH_CLIENT_SECRET=$(bosh int "${local_bosh_dir}/creds.yml" --path /admin_password)
      export BOSH_CA_CERT="${local_bosh_dir}/ca.crt"

EOF
      source "${local_bosh_dir}/env"

      bosh -n update-cloud-config docker/cloud-config.yml -v network=director_network -o "${compilation_ops}"

  popd > /dev/null
}

echo "----- Starting BOSH"
main $@
