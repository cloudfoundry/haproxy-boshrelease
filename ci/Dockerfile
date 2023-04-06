FROM ${BOSH_DIRECTOR_TAG:-bosh-director-docker}

ARG GINKGO_VERSION="v2.2.0"

# Install all necessary tools for haproxy testflight and dependency autobump
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y curl wget jq git vim python3-pip

# install go tooling
ENV GOBIN=/usr/local/bin
RUN go install github.com/geofffranks/spruce/cmd/spruce@latest && \
    go install "github.com/onsi/ginkgo/v2/ginkgo@${GINKGO_VERSION}"

# Install Python libraries needed for scripts
COPY scripts/requirements.txt /requirements.txt
RUN /usr/bin/python3 -m pip install -r /requirements.txt
