FROM ghcr.io/cloudfoundry/bosh/docker-cpi:latest

# Install all necessary tools for haproxy testflight and dependency autobump
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y wget jq git vim nano python3-pip python3-venv && \
    apt-get clean

# Set bosh env at login
RUN echo "source /tmp/local-bosh/director/docker-env" >> /root/.bashrc
RUN echo "source /tmp/local-bosh/director/env" >> /root/.bashrc

RUN mkdir -p /usr/local/bosh-deployment/haproxy-boshrelease

# Copy ops files
COPY ops/bosh-scaled-out.yml /usr/local/bosh-deployment/haproxy-boshrelease/bosh-scaled-out.yml
COPY ops/bosh-timeouts.yml /usr/local/bosh-deployment/haproxy-boshrelease/bosh-timeouts.yml
COPY ops/compilation.yml /usr/local/bosh-deployment/haproxy-boshrelease/compilation.yml

# Install Python libraries needed for scripts
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
COPY scripts/requirements.txt /requirements.txt
RUN pip install -r /requirements.txt

# Install go dependencies
ENV GOBIN=/usr/local/bin
RUN go install github.com/geofffranks/spruce/cmd/spruce@latest
