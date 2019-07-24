FROM alpine AS builder

ARG IMAGE_ARCH=amd64

ARG RCON_CLI_VERSION=1.4.4

ADD https://github.com/itzg/rcon-cli/releases/download/${RCON_CLI_VERSION}/rcon-cli_${RCON_CLI_VERSION}_linux_${IMAGE_ARCH}.tar.gz /tmp/rcon-cli.tar.gz

RUN mkdir -p /opt/rcon-cli && \
    tar x -f /tmp/rcon-cli.tar.gz -C /opt/rcon-cli && \
    rm /tmp/rcon-cli.tar.gz

ARG RESTIC_VERSION=0.9.5

ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_${IMAGE_ARCH}.bz2 /tmp/restic.bz2

RUN bunzip2 /tmp/restic.bz2 && \
    mv /tmp/restic /opt/restic

ARG DEMOTER_VERSION=0.1.0

ADD https://github.com/itzg/entrypoint-demoter/releases/download/${DEMOTER_VERSION}/entrypoint-demoter_${DEMOTER_VERSION}_linux_${IMAGE_ARCH}.tar.gz /tmp/entrypoint-demoter.tar.gz

RUN mkdir -p /opt/entrypoint-demoter && \
    tar x -f /tmp/entrypoint-demoter.tar.gz -C /opt/entrypoint-demoter && \
    rm /tmp/entrypoint-demoter.tar.gz



FROM alpine

RUN apk -U --no-cache add \
    bash \
    coreutils

COPY --from=builder /opt/rcon-cli/rcon-cli /opt/rcon-cli/rcon-cli

RUN ln -s /opt/rcon-cli/rcon-cli /usr/bin

COPY --from=builder /opt/restic /opt/restic

RUN chmod +x /opt/restic && \
    ln -s /opt/restic /usr/bin

COPY --from=builder /opt/entrypoint-demoter/entrypoint-demoter /opt/entrypoint-demoter

RUN chmod +x /opt/entrypoint-demoter && \
    ln -s /opt/entrypoint-demoter /usr/bin

COPY backup-loop.sh /opt/

VOLUME ["/data", "/backups"]

ENTRYPOINT ["/opt/entrypoint-demoter", "--match", "/backups"]

CMD ["/opt/backup-loop.sh"]
