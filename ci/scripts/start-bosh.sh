#!/usr/bin/env bash

set -e

if [[ -n "${DEBUG:-}" ]]; then
  set -x
  export BOSH_LOG_LEVEL=debug
fi

function generate_certs() {
  local certs_dir
  certs_dir="${1}"

  pushd "${certs_dir}" > /dev/null
    cat <<EOF > ./bosh-vars.yml
---
variables:
- name: docker_ca
  type: certificate
  options:
    is_ca: true
    common_name: ca
- name: docker_tls
  type: certificate
  options:
    extended_key_usage: [server_auth]
    common_name: $OUTER_CONTAINER_IP
    alternative_names: [$OUTER_CONTAINER_IP]
    ca: docker_ca
- name: client_docker_tls
  type: certificate
  options:
    extended_key_usage: [client_auth]
    common_name: $OUTER_CONTAINER_IP
    alternative_names: [$OUTER_CONTAINER_IP]
    ca: docker_ca
EOF

   bosh int ./bosh-vars.yml --vars-store=./certs.yml
   bosh int ./certs.yml --path=/docker_ca/ca > ./ca.pem
   bosh int ./certs.yml --path=/docker_tls/certificate > ./server-cert.pem
   bosh int ./certs.yml --path=/docker_tls/private_key > ./server-key.pem
   bosh int ./certs.yml --path=/client_docker_tls/certificate > ./cert.pem
   bosh int ./certs.yml --path=/client_docker_tls/private_key > ./key.pem

   # generate certs in json format
   ruby -e 'puts File.read("./ca.pem").split("\n").join("\\n")' > "${certs_dir}/ca_json_safe.pem"
   ruby -e 'puts File.read("./cert.pem").split("\n").join("\\n")' > "${certs_dir}/client_certificate_json_safe.pem"
   ruby -e 'puts File.read("./key.pem").split("\n").join("\\n")' > "${certs_dir}/client_private_key_json_safe.pem"

  popd > /dev/null
}

function sanitize_cgroups() {
  mkdir -p /sys/fs/cgroup
  mountpoint -q /sys/fs/cgroup || \
    mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup

  if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    # cgroups v2: enable nesting (based on moby/moby hack/dind)
    mkdir -p /sys/fs/cgroup/init
    # Loop to handle races from concurrent process creation (e.g. docker exec)
    while ! {
      xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || :
      sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
        > /sys/fs/cgroup/cgroup.subtree_control
    }; do true; done
    return
  fi

  mount -o remount,rw /sys/fs/cgroup

  # shellcheck disable=SC2034
  sed -e 1d /proc/cgroups | while read -r sys hierarchy num enabled; do
    if [ "$enabled" != "1" ]; then
      # subsystem disabled; skip
      continue
    fi

    grouping="$(cut -d: -f2 < /proc/self/cgroup | grep "\\<$sys\\>")"
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

function stop_docker() {
  service docker stop
}

function start_docker() {
  local certs_dir
  certs_dir="${1}"

  export DNS_IP="8.8.8.8"

  # docker will fail starting with the new iptables. it throws:
  # iptables v1.8.7 (nf_tables): Could not fetch rule set generation id: ....
  update-alternatives --set iptables /usr/sbin/iptables-legacy

  generate_certs "${certs_dir}"

  mkdir -p /var/log
  mkdir -p /var/run

  sanitize_cgroups
  echo "Sanitized cgroups for docker" >&2

  # systemd inside nested Docker containers requires shared mount propagation
  mount --make-rshared /

  # ensure systemd cgroup is present (cgroups v1 only)
  if [ ! -f /sys/fs/cgroup/cgroup.controllers ]; then
    mkdir -p /sys/fs/cgroup/systemd
    if ! mountpoint -q /sys/fs/cgroup/systemd ; then
      mount -t cgroup -o none,name=systemd cgroup /sys/fs/cgroup/systemd
    fi
  fi

  # check for /proc/sys being mounted readonly, as systemd does
  if grep '/proc/sys\s\+\w\+\s\+ro,' /proc/mounts >/dev/null; then
    mount -o remount,rw /proc/sys
  fi

  local mtu
  mtu=$(cat "/sys/class/net/$(ip route get ${DNS_IP} | awk '{ print $5 }')/mtu")

  [[ ! -d /etc/docker ]] && mkdir /etc/docker
  cat <<EOF > /etc/docker/daemon.json
{
  "hosts": ["${DOCKER_HOST}"],
  "tls": true,
  "tlscert": "${certs_dir}/server-cert.pem",
  "tlskey": "${certs_dir}/server-key.pem",
  "tlscacert": "${certs_dir}/ca.pem",
  "mtu": ${mtu},
  "dns": ["8.8.8.8", "8.8.4.4"],
  "data-root": "/scratch/docker",
  "tlsverify": true
}
EOF

  service docker start
  echo "Started docker service" >&2

  rc=1
  for i in $(seq 1 100); do
    echo "waiting for docker to come up... (${i})"
    sleep 1
    set +e
    echo "Docker started, checking if it's responsive..."
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

  echo "${certs_dir}"
}

function main() {
  # ".first" - original code could return multiple IPs (e.g., container IP + docker0 bridge IP)
  # which breaks the docker_tls JSON variable formatting
  OUTER_CONTAINER_IP=$(ruby -rsocket -e 'puts Socket.ip_address_list
                         .reject { |addr| !addr.ip? || addr.ipv4_loopback? || addr.ipv6? }
                         .map { |addr| addr.ip_address }.first')
  export OUTER_CONTAINER_IP
  echo "Determined OUTER_CONTAINER_IP: ${OUTER_CONTAINER_IP}" >&2

  local certs_dir
  certs_dir=$(mktemp -d)

  local local_bosh_dir
  local_bosh_dir="/tmp/local-bosh/director"
  mkdir -p ${local_bosh_dir}

  cat <<EOF > "${local_bosh_dir}/docker-env"
export DOCKER_HOST="tcp://${OUTER_CONTAINER_IP}:4243"
export DOCKER_TLS_VERIFY=1
export DOCKER_CERT_PATH="${certs_dir}"
EOF
  echo "Source '${local_bosh_dir}/docker-env' to run docker" >&2
  source "${local_bosh_dir}/docker-env"

  start_docker "${certs_dir}"
  echo "Docker is up and running with TLS configured" >&2

  local docker_network_name="director_network"
  local docker_network_cidr="10.245.0.0/16"
  if docker network ls | grep -q "${docker_network_name}"; then
    echo "A docker network named '${docker_network_name}' already exists, skipping creation" >&2
  else
    docker network create -d bridge --subnet=${docker_network_cidr} "${docker_network_name}"
    echo "Created docker network '${docker_network_name}' with subnet '${docker_network_cidr}'" >&2
  fi

  pushd "${BOSH_DEPLOYMENT_PATH:-/usr/local/bosh-deployment}" > /dev/null
      echo "Current directory: $(pwd)" >&2

      export BOSH_DIRECTOR_IP="10.245.0.3"
      export BOSH_ENVIRONMENT="docker-director"

      cat <<EOF > "${local_bosh_dir}/docker_tls.json"
{
  "ca": "$(cat "${certs_dir}/ca_json_safe.pem")",
  "certificate": "$(cat "${certs_dir}/client_certificate_json_safe.pem")",
  "private_key": "$(cat "${certs_dir}/client_private_key_json_safe.pem")"
}
EOF

      echo "Interpolating BOSH deployment manifest with Docker CPI and TLS configuration..." >&2
      bosh int bosh.yml \
        -o runtime-configs/dns.yml \
        -o docker/cpi.yml \
        -o jumpbox-user.yml \
        -o /usr/local/local-releases.yml \
        -o "$PWD/noble-updates.yml" \
        -v director_name=docker \
        -v internal_cidr=${docker_network_cidr} \
        -v internal_gw=10.245.0.1 \
        -v internal_ip="${BOSH_DIRECTOR_IP}" \
        -v docker_host="${DOCKER_HOST}" \
        -v network="${docker_network_name}" \
        -v docker_tls="$(cat "${local_bosh_dir}/docker_tls.json")" \
        "${@}" > "${local_bosh_dir}/bosh-director.yml"

    # #region agent log — monitor containers during create-env for systemd exit diagnostics
      (
        while true; do
          for cid in $(docker ps -a -q 2>/dev/null); do
            cstatus=$(docker inspect --format '{{.State.Status}}' "$cid" 2>/dev/null)
            if [ "$cstatus" = "exited" ] || [ "$cstatus" = "dead" ]; then
              cname=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')
              exitcode=$(docker inspect --format '{{.State.ExitCode}}' "$cid" 2>/dev/null)
              echo "=== DEBUG[58375b] $(date -u +%H:%M:%S) DEAD container: ${cname} (${cid}) exit=${exitcode} ==="
              echo "=== DEBUG[58375b] container Cmd ==="
              docker inspect --format '{{.Config.Cmd}}' "$cid" 2>/dev/null | head -5 || true
              echo "=== DEBUG[58375b] container logs ==="
              docker logs "$cid" 2>&1 | tail -30 || true
              echo "=== DEBUG[58375b] dmesg last 20 ==="
              dmesg 2>/dev/null | tail -20 || true
              echo "=== DEBUG[58375b] container journal ==="
              docker cp "$cid":/var/log/journal /tmp/journal-diag-"$cid" 2>/dev/null && \
                find /tmp/journal-diag-"$cid" -name '*.journal' -exec journalctl --file '{}' --no-pager \; 2>/dev/null | tail -50 || \
                echo "(no journal)"
              echo "=== DEBUG[58375b] end dead container $cid ==="
            fi
          done
          sleep 2
        done
      ) &
      CREATE_ENV_MONITOR_PID=$!
      # #endregion agent log

      echo "Starting monit-nft-watcher to correct NF table for any starting container..." >&2
      nohup /usr/local/sbin/watch-containers.sh >/var/log/monit-nft-watcher.log 2>&1 &

      echo "Creating BOSH director environment..." >&2
      create_env_exit=0
      bosh create-env "${local_bosh_dir}/bosh-director.yml" \
        --vars-store="${local_bosh_dir}/creds.yml" \
        --state="${local_bosh_dir}/state.json" || create_env_exit=$?

      kill $CREATE_ENV_MONITOR_PID 2>/dev/null || true
      wait $CREATE_ENV_MONITOR_PID 2>/dev/null || true

      if [ "$create_env_exit" -ne 0 ]; then
        echo "=== DEBUG[58375b] create-env failed (exit=${create_env_exit}) ==="
        echo "=== DEBUG[58375b] all containers ==="
        docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}' || true
        for cid in $(docker ps -a -q 2>/dev/null); do
          cname=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')
          cstatus=$(docker inspect --format '{{.State.Status}}' "$cid" 2>/dev/null)
          exitcode=$(docker inspect --format '{{.State.ExitCode}}' "$cid" 2>/dev/null)
          echo "=== DEBUG[58375b] container ${cname} (${cid}): status=${cstatus} exit=${exitcode} ==="
          echo "=== DEBUG[58375b] Cmd ==="
          docker inspect --format '{{.Config.Cmd}}' "$cid" 2>/dev/null | head -3 || true
          echo "=== DEBUG[58375b] HostConfig ==="
          docker inspect --format 'Privileged={{.HostConfig.Privileged}} CgroupnsMode={{.HostConfig.CgroupnsMode}} Binds={{.HostConfig.Binds}}' "$cid" 2>/dev/null || true
          echo "=== DEBUG[58375b] logs ==="
          docker logs "$cid" 2>&1 | tail -30 || true
          echo "=== DEBUG[58375b] cgroup info from inside container ==="
          docker exec "$cid" bash -c 'cat /proc/self/cgroup 2>/dev/null; echo "---"; ls -la /sys/fs/cgroup/ 2>/dev/null; echo "---"; cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null; echo "---"; cat /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null' 2>/dev/null || true
          echo "=== DEBUG[58375b] journal from container ==="
          docker cp "$cid":/var/log/journal /tmp/journal-post-"$cid" 2>/dev/null && \
            find /tmp/journal-post-"$cid" -name '*.journal' -exec journalctl --file '{}' --no-pager \; 2>/dev/null | tail -100 || echo "(no journal)"
        done
        echo "=== DEBUG[58375b] dmesg (last 40) ==="
        dmesg 2>/dev/null | tail -40 || true

        echo "=== DEBUG[58375b] reproducing with verbose startup to find failure point ==="
        local failed_image
        failed_image=$(docker inspect --format '{{.Config.Image}}' "$(docker ps -a -q | head -1)" 2>/dev/null) || true
        if [ -n "$failed_image" ]; then
          echo "=== DEBUG[58375b] test: running pre-start commands step by step ==="
          docker run --rm --privileged --cgroupns=host \
            -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
            -v /lib/modules:/usr/lib/modules \
            "$failed_image" bash -c '
              set -x
              echo "step1: umount resolv.conf" && umount /etc/resolv.conf 2>&1; echo "exit=$?"
              echo "step2: write resolv.conf" && printf "%s\n" "nameserver 8.8.8.8" > /etc/resolv.conf 2>&1; echo "exit=$?"
              echo "step3: umount hosts" && umount /etc/hosts 2>&1; echo "exit=$?"
              echo "step4: umount hostname" && umount /etc/hostname 2>&1; echo "exit=$?"
              echo "step5: mkdir data/sys" && rm -rf /var/vcap/data/sys && mkdir -p /var/vcap/data/sys 2>&1; echo "exit=$?"
              echo "step6: mkdir store" && mkdir -p /var/vcap/store 2>&1; echo "exit=$?"
              echo "step7: sed chronyc" && sed -i "s/chronyc/# chronyc/g" /var/vcap/bosh/bin/sync-time 2>&1; echo "exit=$?"
              echo "step8: rm sv" && rm -rf /etc/sv/{ssh,cron} && rm -rf /etc/service/{ssh,cron} 2>&1; echo "exit=$?"
              echo "step9: find/delete units" && find /etc/systemd/system /lib/systemd/system -path "*.wants/*" \
                -not -name "*bosh-agent*" -not -name "*journald*" -not -name "*logrotate*" \
                -not -name "*runit*" -not -name "*ssh*" -not -name "*systemd-user-sessions*" \
                -not -name "*systemd-tmpfiles*" -exec rm {} \; 2>&1; echo "exit=$?"
              echo "step10: cgroup state before init"
              cat /proc/self/cgroup 2>&1
              ls /sys/fs/cgroup/ 2>&1
              cat /sys/fs/cgroup/cgroup.controllers 2>&1 || true
              cat /sys/fs/cgroup/cgroup.subtree_control 2>&1 || true
              MYCG=$(grep "^0::" /proc/self/cgroup | cut -d: -f3)
              echo "my cgroup path: ${MYCG}"
              ls "/sys/fs/cgroup${MYCG}/" 2>&1 || true
              cat "/sys/fs/cgroup${MYCG}/cgroup.controllers" 2>&1 || true
              cat "/sys/fs/cgroup${MYCG}/cgroup.subtree_control" 2>&1 || true
              cat "/sys/fs/cgroup${MYCG}/cgroup.procs" 2>&1 || true
              echo "step11: attempting /sbin/init with timeout"
              timeout 5 /sbin/init --log-level=debug --log-target=console 2>&1 || echo "init exited with $?"
            ' 2>&1 || echo "DEBUG[58375b] test container exited with $?"
        fi

        exit "$create_env_exit"
      fi

      echo "Extracting BOSH director credentials and CA certificate..." >&2
      bosh int "${local_bosh_dir}/creds.yml" --path /director_ssl/ca > "${local_bosh_dir}/ca.crt"
      bosh_client_secret="$(bosh int "${local_bosh_dir}/creds.yml" --path /admin_password)"

      echo "Setting up BOSH CLI environment..." >&2
      bosh -e "${BOSH_DIRECTOR_IP}" --ca-cert "${local_bosh_dir}/ca.crt" alias-env "${BOSH_ENVIRONMENT}"

      cat <<EOF > "${local_bosh_dir}/env"
      export BOSH_DIRECTOR_IP="${BOSH_DIRECTOR_IP}"
      export BOSH_ENVIRONMENT="${BOSH_ENVIRONMENT}"
      export BOSH_CLIENT=admin
      export BOSH_CLIENT_SECRET=${bosh_client_secret}
      export BOSH_CA_CERT="${local_bosh_dir}/ca.crt"
EOF
      echo "Source '${local_bosh_dir}/env' to run bosh" >&2
      source "${local_bosh_dir}/env"

      echo "Updating BOSH cloud config with Docker network..." >&2
      bosh -n update-cloud-config docker/cloud-config.yml -v network="${docker_network_name}"

      # #region agent log — Hypothesis A: check if runsvdir-start exists in stemcell image
      local stemcell_image
      stemcell_image=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | head -1)
      echo "=== DEBUG[58375b] stemcell image: ${stemcell_image} ==="
      echo "=== DEBUG[58375b] checking runsvdir-start and /sbin/init in stemcell ==="
      docker run --rm --entrypoint "" "${stemcell_image}" bash -c \
        'echo "runsvdir-start exists: $(test -f /usr/sbin/runsvdir-start && echo YES || echo NO)"; \
         echo "sbin/init exists: $(test -f /sbin/init && echo YES || echo NO)"; \
         echo "systemd exists: $(test -f /lib/systemd/systemd && echo YES || echo NO)"; \
         ls -la /usr/sbin/runsvdir-start /sbin/init /lib/systemd/systemd 2>&1 || true' \
        || echo "DEBUG[58375b] failed to inspect stemcell image"
      # #endregion agent log

      # #region agent log — Hypothesis B/D: monitor new containers during deploy
      echo "=== DEBUG[58375b] pre-deploy container list ==="
      docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'

      local director_cid_pre
      director_cid_pre=$(docker ps -q --filter "expose=25555" | head -1)
      echo "=== DEBUG[58375b] director container id: ${director_cid_pre} ==="

      (
        seen_containers=""
        while true; do
          for cid in $(docker ps -a -q); do
            if [ "$cid" = "$director_cid_pre" ]; then
              continue
            fi
            cname=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')
            cstatus=$(docker inspect --format '{{.State.Status}}' "$cid" 2>/dev/null)
            if [[ "$cname" == c-* ]]; then
              if ! echo "$seen_containers" | grep -q "$cid"; then
                seen_containers="${seen_containers} ${cid}"
                echo "=== DEBUG[58375b] $(date -u +%H:%M:%S) NEW non-director container: ${cname} (${cid}) status=${cstatus} ==="
                echo "=== DEBUG[58375b] container cmd ==="
                docker inspect --format '{{.Config.Cmd}}' "$cid" 2>/dev/null || true
                echo "=== DEBUG[58375b] container hostconfig ==="
                docker inspect --format 'Privileged={{.HostConfig.Privileged}} CgroupnsMode={{.HostConfig.CgroupnsMode}} Binds={{.HostConfig.Binds}}' "$cid" 2>/dev/null || true
              fi
              if [ "$cstatus" = "exited" ] || [ "$cstatus" = "dead" ]; then
                echo "=== DEBUG[58375b] $(date -u +%H:%M:%S) CONTAINER DIED: ${cname} (${cid}) ==="
                docker inspect --format 'ExitCode={{.State.ExitCode}} Error={{.State.Error}}' "$cid" 2>/dev/null || true
                echo "=== DEBUG[58375b] container logs ==="
                docker logs "$cid" 2>&1 | tail -80 || true
              fi
            fi
          done
          sleep 2
        done
      ) &
      MONITOR_PID=$!
      # #endregion agent log

      deployment_name="haproxy"
      deploy_exit=0
      bosh deploy --non-interactive \
        --deployment "${deployment_name}" \
        "${REPO_ROOT}/manifests/haproxy.yml" \
         --var haproxy-backend-port=12000 --var haproxy-backend-servers=["127.0.0.1"] || deploy_exit=$?

      # #region agent log — post-deploy diagnostics
      echo "=== DEBUG[58375b] post-deploy container list ==="
      docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}'

      if [ "$deploy_exit" -ne 0 ]; then
        echo "=== DEBUG[58375b] deploy failed (exit=${deploy_exit}), capturing CPI config ==="
        docker exec "$(docker ps -q --filter name=c-)" bash -c \
          'cat /var/vcap/jobs/docker_cpi/config/cpi.json 2>/dev/null' || echo "DEBUG[58375b] could not read cpi.json"

        echo "=== DEBUG[58375b] CPI debug log ==="
        docker exec "$(docker ps -q --filter name=c-)" bash -c \
          'find /var/vcap -name "cpi.log" -o -name "docker_cpi*" 2>/dev/null | while read f; do echo "--- $f ---"; tail -100 "$f"; done' || true

        echo "=== DEBUG[58375b] task debug log (last 200 lines) ==="
        docker exec "$(docker ps -q --filter name=c-)" bash -c \
          'find /var/vcap/data/director/tasks -name "debug" 2>/dev/null | sort -V | tail -1 | xargs tail -200 2>/dev/null' || true
      fi

      kill $MONITOR_PID 2>/dev/null || true
      wait $MONITOR_PID 2>/dev/null || true
      # #endregion agent log

  popd > /dev/null
}

echo "----- Starting BOSH"
main "${@}"
