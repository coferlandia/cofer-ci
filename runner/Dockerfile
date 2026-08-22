ARG RUNNER_IMAGE_TAG=latest
FROM ghcr.io/actions/actions-runner:${RUNNER_IMAGE_TAG}

LABEL io.coferlandia.ci="true" \
      org.opencontainers.image.title="coferlandia-ci-runner"

USER root

ARG TARGETARCH
ARG COMPOSE_VERSION=v5.1.4

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       gzip \
       jq \
       procps \
       rsync \
       tar \
       tini \
       unzip \
       zip \
       zstd \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) compose_arch="x86_64" ;; \
      arm64) compose_arch="aarch64" ;; \
      *) echo "Arquitectura no soportada: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL \
      "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${compose_arch}" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose; \
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose

RUN mkdir -p \
      /opt/actions-runner-dist \
      /opt/actions-runner \
      /opt/runner-hooks \
      /cache \
    && cp -a /home/runner/. /opt/actions-runner-dist/ \
    && chown -R runner:docker \
      /opt/actions-runner-dist \
      /opt/actions-runner \
      /opt/runner-hooks \
      /cache

COPY --chown=runner:docker runner/entrypoint.sh /usr/local/bin/runner-entrypoint.sh
RUN chmod 0755 /usr/local/bin/runner-entrypoint.sh

USER runner
WORKDIR /opt/actions-runner
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/runner-entrypoint.sh"]
CMD ["run"]
