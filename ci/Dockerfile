FROM bosh/docker-cpi:main

# Install all necessary tools for haproxy testflight and dependency autobump
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y wget jq git vim nano python3-pip && \
    apt-get clean

# Set bosh env at login
RUN echo "source /tmp/local-bosh/director/env" >> /root/.bashrc

# Install Python libraries needed for scripts
COPY scripts/requirements.txt /requirements.txt
RUN /usr/bin/python3 -m pip install -r /requirements.txt

# Install go dependencies
ENV GOBIN=/usr/local/bin
RUN go install github.com/onsi/ginkgo/v2/ginkgo@latest && \
    go install github.com/geofffranks/spruce/cmd/spruce@latest
