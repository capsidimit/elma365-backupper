ARG BASE_HASH=sha256:f06537653ac770703bc45b4b113475bd402f451e85223f0f2837acbf89ab020a
ARG ELMA_BACKUPPER_VERSION=1.0.17
FROM docker.io/debian@${BASE_HASH} AS builder
ENV DEBIAN_FRONTEND=noninteractive
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
RUN curl -fsSL --proto '=https' --tlsv1.2 \
        https://repo.elma365.tech/deb/elma365-keyring.gpg \
        -o /tmp/elma365-keyring.gpg && \
    gpg --dearmor < /tmp/elma365-keyring.gpg \
        > /etc/apt/trusted.gpg.d/elma365-keyring.gpg && \
    rm -f /tmp/elma365-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/elma365-keyring.gpg] \
        https://repo.elma365.tech/deb $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/elma365.list
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        elma365-backupper=${ELMA_BACKUPPER_VERSION} \
    && rm -rf /var/lib/apt/lists/*

FROM docker.io/debian@${BASE_HASH}
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && find / -xdev \( -perm -4000 -o -perm -2000 \) -exec chmod ug-s {} \; 2>/dev/null || true
RUN groupadd --gid 10001 elma && \
    useradd --uid 10001 --gid 10001 \
            --no-create-home \
            --shell /usr/sbin/nologin \
            elma
COPY --from=builder --chown=10001:10001 /opt/elma365    /opt/elma365
COPY --from=builder --chown=10001:10001 /usr/local/bin/elma365-backupper \
                                        /usr/local/bin/elma365-backupper
WORKDIR /home/elma
COPY --chown=10001:10001 src/entrypoint.sh  ./entrypoint.sh
COPY --chown=10001:10001 src/config.yaml    ./config.yaml

RUN chmod 550 ./entrypoint.sh && \
    chmod 440 ./config.yaml

USER 10001:10001

ENTRYPOINT ["./entrypoint.sh"]

ARG BUILD_DATE
ARG GIT_SHA
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.title="elma365-backupper" \
      org.opencontainers.image.version="${ELMA_BACKUPPER_VERSION}"


# ARG BASE_HASH=sha256:f06537653ac770703bc45b4b113475bd402f451e85223f0f2837acbf89ab020a
# FROM docker.io/debian@${BASE_HASH}
# RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
#     --mount=type=cache,target=/var/lib/apt,sharing=locked \
#     apt update && \
#     apt install -y apt-transport-https ca-certificates curl gpg sudo lsb-release
# RUN curl -fsSL https://repo.elma365.tech/deb/elma365-keyring.gpg | \
#         gpg --dearmor > /etc/apt/trusted.gpg.d/elma365-keyring.gpg && \
#     echo "deb [arch=amd64] https://repo.elma365.tech/deb $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/elma365.list
# RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
#     --mount=type=cache,target=/var/lib/apt,sharing=locked \
#     apt update && apt install -y elma365-backupper
# # -s /usr/sbin/nologin 
# RUN useradd -m elma && \
#     chown elma:elma -R /opt/elma365 \
#         /usr/share/doc/elma365
# #USER elma
# WORKDIR /home/elma
# COPY src/* .
# ENTRYPOINT ["bash", "-c"]
