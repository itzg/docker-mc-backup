FROM alpine AS builder

# provided by buildx when using --platform
# or manually using --build-arg TARGETARCH=amd64 --build-arg TARGETVARIANT=
ARG TARGETARCH
ARG TARGETVARIANT

RUN mkdir -p /opt

ARG RCON_CLI_VERSION=1.7.2

ADD https://github.com/itzg/rcon-cli/releases/download/${RCON_CLI_VERSION}/rcon-cli_${RCON_CLI_VERSION}_linux_${TARGETARCH}${TARGETVARIANT}.tar.gz /tmp/rcon-cli.tar.gz

RUN tar x -f /tmp/rcon-cli.tar.gz -C /opt/ && \
    chmod +x /opt/rcon-cli

ARG MC_MONITOR_VERSION=0.15.6

ADD https://github.com/itzg/mc-monitor/releases/download/${MC_MONITOR_VERSION}/mc-monitor_${MC_MONITOR_VERSION}_linux_${TARGETARCH}${TARGETVARIANT}.tar.gz /tmp/mc-monitor.tar.gz

RUN tar x -f /tmp/mc-monitor.tar.gz -C /opt/ && \
    chmod +x /opt/mc-monitor

ARG RESTIC_VERSION=0.18.0

# NOTE: restic releases don't differentiate arm v6 from v7, so TARGETVARIANT is not used
# and have to assume they release armv7
ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_${TARGETARCH}.bz2 /tmp/restic.bz2

RUN bunzip2 /tmp/restic.bz2 && \
    mv /tmp/restic /opt/restic && \
    chmod +x /opt/restic

ARG DEMOTER_VERSION=0.4.8

ADD https://github.com/itzg/entrypoint-demoter/releases/download/v${DEMOTER_VERSION}/entrypoint-demoter_${DEMOTER_VERSION}_Linux_${TARGETARCH}${TARGETVARIANT}.tar.gz /tmp/entrypoint-demoter.tar.gz

RUN tar x -f /tmp/entrypoint-demoter.tar.gz -C /opt/ && \
    chmod +x /opt/entrypoint-demoter

ARG RCLONE_VERSION=1.71.0

ADD https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${TARGETARCH}.zip /tmp/rclone.zip

RUN mkdir -p /tmp/rclone && \
    unzip /tmp/rclone.zip -d /tmp/rclone && \
    mv /tmp/rclone/rclone-v${RCLONE_VERSION}-linux-${TARGETARCH}/rclone /opt/rclone && \
    chmod +x /opt/rclone


FROM alpine

RUN apk -U --no-cache add \
    bash \
    coreutils \
    curl \
    openssh-client \
    tar \
    tzdata \
    rsync \
    zstd


COPY --from=builder /opt/rcon-cli /opt/rcon-cli

RUN ln -s /opt/rcon-cli /usr/bin


COPY --from=builder /opt/mc-monitor /opt/mc-monitor

RUN ln -s /opt/mc-monitor /usr/bin


COPY --from=builder /opt/restic /opt/restic

RUN ln -s /opt/restic /usr/bin


COPY --from=builder /opt/entrypoint-demoter /opt/entrypoint-demoter

RUN ln -s /opt/entrypoint-demoter /usr/bin


COPY --from=builder /opt/rclone /opt/rclone

RUN ln -s /opt/rclone /usr/bin

COPY --chmod=755 scripts/opt/ /opt/
COPY --chmod=755 scripts/bin/ /usr/bin/

VOLUME ["/data", "/backups"]
WORKDIR "/backups"

# Workaround for some tools (i.e. RCLONE) creating cache files in $HOME
# and not having permissions to write when demoter does demote to UID,
# while keeping the $HOME=/root
ENV HOME=/tmp

ENTRYPOINT ["/usr/bin/backup"]

CMD ["loop"]
