FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    xz-utils \
    valgrind \
    cppcheck \
    python3 \
    python3-pip \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install FB Infer
ENV INFER_VERSION=1.2.0
RUN curl -sSL "https://github.com/facebook/infer/releases/download/v${INFER_VERSION}/infer-linux-x86_64-v${INFER_VERSION}.tar.xz" | tar -C /opt -xJ && \
    ln -s "/opt/infer-linux-x86_64-v${INFER_VERSION}/bin/infer" /usr/local/bin/infer

WORKDIR /code