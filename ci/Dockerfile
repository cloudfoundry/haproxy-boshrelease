FROM bosh/main-bosh-docker

ARG GINKGO_VERSION=v2.2.0

ENV DEBIAN_FRONTEND=noninteractive

# Install all necessary tools for haproxy testflight and dependency autobump
RUN apt-get update && apt-get install -y wget jq git vim nano python3-pip\
  && wget -q -O - https://raw.githubusercontent.com/starkandwayne/homebrew-cf/master/public.key | apt-key add - \
  && echo "deb http://apt.starkandwayne.com stable main" | tee /etc/apt/sources.list.d/starkandwayne.list \
  && apt-get update && apt-get install -y wget spruce && apt-get clean

# Set bosh env at login
RUN echo "source /tmp/local-bosh/director/env" >> /root/.bashrc
# Add go to path
RUN echo "export PATH=\$PATH:\$GOPATH/bin" >> /root/.bashrc

# Install Python libraries needed for scripts
COPY scripts/requirements.txt /requirements.txt
RUN /usr/bin/python3 -m pip install -r /requirements.txt

ENV GOPATH=/go
RUN mkdir /go
RUN go install "github.com/onsi/ginkgo/v2/ginkgo@${GINKGO_VERSION}"
