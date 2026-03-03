FROM ghcr.io/cloudfoundry/bosh/docker-cpi:latest

# Install all necessary tools for haproxy testflight and dependency autobump
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y wget jq git vim nano python3-pip python3-venv && \
    apt-get clean

# Set bosh env at login
RUN echo "source /tmp/local-bosh/director/env" >> /root/.bashrc

# Copy ops files
COPY noble-updates.yml /usr/local/bosh-deployment/noble-updates.yml

# Copy scripts
COPY scripts/nft/update-monit-nft.sh /usr/local/sbin/update-monit-nft.sh
COPY scripts/nft/watch-containers.sh /usr/local/sbin/watch-containers.sh
RUN chmod 755 /usr/local/sbin/update-monit-nft.sh /usr/local/sbin/watch-containers.sh

# Install Python libraries needed for scripts
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
COPY scripts/requirements.txt /requirements.txt
RUN pip install -r /requirements.txt

# Install go dependencies
ENV GOBIN=/usr/local/bin
RUN go install github.com/geofffranks/spruce/cmd/spruce@latest
