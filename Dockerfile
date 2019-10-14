FROM alpine AS builder

RUN mkdir -p /opt

ARG IMAGE_ARCH=amd64

ARG RCON_CLI_VERSION=1.4.4

ADD https://github.com/itzg/rcon-cli/releases/download/${RCON_CLI_VERSION}/rcon-cli_${RCON_CLI_VERSION}_linux_${IMAGE_ARCH}.tar.gz /tmp/rcon-cli.tar.gz

RUN tar x -f /tmp/rcon-cli.tar.gz -C /opt/ && \
    chmod +x /opt/rcon-cli

ARG RESTIC_VERSION=0.9.5

ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_${IMAGE_ARCH}.bz2 /tmp/restic.bz2

RUN bunzip2 /tmp/restic.bz2 && \
    mv /tmp/restic /opt/restic && \
    chmod +x /opt/restic

ARG DEMOTER_VERSION=0.1.0

ADD https://github.com/itzg/entrypoint-demoter/releases/download/${DEMOTER_VERSION}/entrypoint-demoter_${DEMOTER_VERSION}_linux_${IMAGE_ARCH}.tar.gz /tmp/entrypoint-demoter.tar.gz

RUN tar x -f /tmp/entrypoint-demoter.tar.gz -C /opt/ && \
    chmod +x /opt/entrypoint-demoter

ARG RCLONE_VERSION=1.49.5

ADD https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${IMAGE_ARCH}.zip /tmp/rclone.zip

RUN mkdir -p /tmp/rclone && \
    unzip /tmp/rclone.zip -d /tmp/rclone && \
    mv /tmp/rclone/rclone-v${RCLONE_VERSION}-linux-${IMAGE_ARCH}/rclone /opt/rclone && \
    chmod +x /opt/rclone


FROM alpine

RUN apk -U --no-cache add \
    bash \
    coreutils

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

ENTRYPOINT ["/opt/entrypoint-demoter", "--match", "/backups"]

CMD ["/opt/backup-loop.sh"]
