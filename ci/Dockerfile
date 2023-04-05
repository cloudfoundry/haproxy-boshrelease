FROM bosh/main-bosh-docker

ARG GINKGO_VERSION=v2.9.2
ARG SPRUCE_VERSION=v1.30.2

ENV DEBIAN_FRONTEND=noninteractive

# Install all necessary tools for haproxy testflight and dependency autobump
RUN apt-get update && apt-get install -y wget jq git vim nano python3-pip

# Set bosh env at login
RUN echo "source /tmp/local-bosh/director/env" >> /root/.bashrc
# Add go to path
RUN echo "export PATH=\$PATH:\$GOPATH/bin" >> /root/.bashrc

# Install Python libraries needed for scripts
COPY scripts/requirements.txt /requirements.txt
RUN /usr/bin/python3 -m pip install -r /requirements.txt

ADD --chmod=755 https://github.com/geofffranks/spruce/releases/download/${SPRUCE_VERSION}/spruce-linux-amd64 /usr/local/bin/spruce
RUN rm -rf /usr/local/go/ && mkdir -p /usr/local/go/
COPY --from=golang:1.20 /usr/local/go/ /usr/local/go/

RUN mkdir /go
ENV GOPATH=/go PATH=${PATH}:/go/bin

RUN go install "github.com/onsi/ginkgo/v2/ginkgo@${GINKGO_VERSION}"
