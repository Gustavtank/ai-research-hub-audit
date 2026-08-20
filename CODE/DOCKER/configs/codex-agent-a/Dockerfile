FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gawk \
        gzip \
        tar \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/codex-install \
    && curl -fsSL https://chatgpt.com/codex/install.sh \
       | CODEX_HOME=/opt/codex-install \
         CODEX_INSTALL_DIR=/usr/local/bin \
         CODEX_NON_INTERACTIVE=1 \
         sh \
    && codex --version

RUN useradd \
    --create-home \
    --shell /bin/bash \
    codex

USER codex
WORKDIR /home/codex

CMD ["codex", "--version"]
