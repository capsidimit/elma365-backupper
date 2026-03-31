ARG BASE_HASH=sha256:f06537653ac770703bc45b4b113475bd402f451e85223f0f2837acbf89ab020a
ARG ELMA_BACKUPPER_VERSION=1.0.17


FROM docker.io/debian@${BASE_HASH} AS builder
ENV DEBIAN_FRONTEND=noninteractive
# Installing base dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        gpg \
        lsb-release \
    && rm -rf /var/lib/apt/lists/*
# Adding elma apt repo
RUN curl -fsSL --proto '=https' --tlsv1.2 \
        https://repo.elma365.tech/deb/elma365-keyring.gpg \
        -o /tmp/elma365-keyring.gpg && \
    gpg --dearmor < /tmp/elma365-keyring.gpg \
        > /etc/apt/trusted.gpg.d/elma365-keyring.gpg && \
    rm -f /tmp/elma365-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/elma365-keyring.gpg] \
        https://repo.elma365.tech/deb $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/elma365.list
# Installing elma-backupper
ARG ELMA_BACKUPPER_VERSION
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        elma365-backupper=${ELMA_BACKUPPER_VERSION} \
    && rm -rf /var/lib/apt/lists/*
# Adding execution user
RUN groupadd --gid 10001 elma && \
    useradd --uid 10001 --gid 10001 \
            --no-create-home \
            --shell /usr/sbin/nologin \
            elma && \
    mkdir /home/elma && \
    chown 10001:10001 -R /home/elma && \
    chown 10001:10001 -R /opt/elma365
WORKDIR /home/elma
COPY --chown=10001:10001 --chmod=500 src/entrypoint.sh  ./entrypoint.sh

USER 10001:10001
VOLUME [ "/opt/elma365/backupper/backup" ]
ENTRYPOINT ["./entrypoint.sh"]

ARG ELMA_BACKUPPER_VERSION
ARG BUILD_DATE
ARG GIT_SHA
ARG GIT_URL
ARG BASE_HASH
ARG VERSION
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.url="${GIT_URL}" \
      org.opencontainers.image.source="${GIT_URL}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.base.name="docker.io/debian@${BASE_HASH}" \
      org.opencontainers.image.title="elma365-backupper" \
      org.opencontainers.image.version="${ELMA_BACKUPPER_VERSION}"
