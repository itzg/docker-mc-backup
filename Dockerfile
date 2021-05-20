FROM alpine AS builder

# provided by buildx when using --platform
# or manually using --build-arg TARGETARCH=amd64 --build-arg TARGETVARIANT=
ARG TARGETARCH
ARG TARGETVARIANT

ARG RCON_CLI_VERSION=1.4.8

ADD https://github.com/itzg/rcon-cli/releases/download/${RCON_CLI_VERSION}/rcon-cli_${RCON_CLI_VERSION}_linux_${TARGETARCH}${TARGETVARIANT}.tar.gz /tmp/rcon-cli.tar.gz

RUN mkdir -p /opt && \
    tar x -f /tmp/rcon-cli.tar.gz -C /opt/ && \
    chmod +x /opt/rcon-cli

ARG RESTIC_VERSION=0.11.0

# NOTE: restic releases don't differentiate arm v6 from v7, so TARGETVARIANT is not used
# and have to assume they release armv7
ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_${TARGETARCH}.bz2 /tmp/restic.bz2

RUN bunzip2 /tmp/restic.bz2 && \
    mv /tmp/restic /opt/restic && \
    chmod +x /opt/restic

ARG DEMOTER_VERSION=0.3.1

ADD https://github.com/itzg/entrypoint-demoter/releases/download/v${DEMOTER_VERSION}/entrypoint-demoter_${DEMOTER_VERSION}_Linux_${TARGETARCH}${TARGETVARIANT}.tar.gz /tmp/entrypoint-demoter.tar.gz

RUN tar x -f /tmp/entrypoint-demoter.tar.gz -C /opt/ && \
    chmod +x /opt/entrypoint-demoter

ARG RCLONE_VERSION=1.53.3

ADD https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${TARGETARCH}.zip /tmp/rclone.zip

RUN mkdir -p /tmp/rclone && \
    unzip /tmp/rclone.zip -d /tmp/rclone && \
    mv /tmp/rclone/rclone-v${RCLONE_VERSION}-linux-${TARGETARCH}/rclone /opt/rclone && \
    chmod +x /opt/rclone


FROM alpine

RUN apk -U --no-cache add \
    bash \
    coreutils \
    openssh-client \
    tzdata


COPY --from=builder /opt/rcon-cli /opt/rcon-cli

RUN ln -s /opt/rcon-cli /usr/bin


COPY --from=builder /opt/restic /opt/restic

RUN ln -s /opt/restic /usr/bin


COPY --from=builder /opt/entrypoint-demoter /opt/entrypoint-demoter

RUN ln -s /opt/entrypoint-demoter /usr/bin


COPY --from=builder /opt/rclone /opt/rclone

RUN ln -s /opt/rclone /usr/bin


COPY backup-loop.sh /opt/

RUN chmod +x /opt/backup-loop.sh


VOLUME ["/data", "/backups"]

# Workaround for some tools (i.e. RCLONE) creating cache files in $HOME
# and not having permissions to write when demoter does demote to UID,
# while keeping the $HOME=/root
ENV HOME=/tmp

ENTRYPOINT ["/opt/entrypoint-demoter", "--match", "/backups"]

CMD ["/opt/backup-loop.sh"]
