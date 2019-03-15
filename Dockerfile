FROM alpine

RUN apk -U add unzip bash

ARG RCLONE_VERSION=1.46
ARG RCON_CLI_VERSION=1.4.4

ADD https://github.com/ncw/rclone/releases/download/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.zip /tmp/rclone.zip

RUN unzip /tmp/rclone.zip -d /opt && \
    ln -s /opt/rclone-v${RCLONE_VERSION}-linux-amd64/rclone /usr/bin && \
    rm /tmp/rclone.zip

ADD https://github.com/itzg/rcon-cli/releases/download/${RCON_CLI_VERSION}/rcon-cli_${RCON_CLI_VERSION}_linux_amd64.tar.gz /tmp/rcon-cli.tgz

RUN mkdir -p /opt/rcon-cli && \
    tar x -f /tmp/rcon-cli.tgz -C /opt/rcon-cli && \
    ln -s /opt/rcon-cli/rcon-cli /usr/bin && \
    rm /tmp/rcon-cli.tgz

ENTRYPOINT ["/opt/backup-loop.sh"]

VOLUME ["/data", "/backups"]

ENV SRC_DIR=/data \
    DEST_DIR=/backups \
    BACKUP_NAME=world \
    INITIAL_DELAY=120 \
    INTERVAL_SEC=86400 \
    TYPE=VANILLA \
    LEVEL=world \
    RCON_PORT=25575 \
    RCON_PASSWORD=minecraft

COPY backup-loop.sh /opt/

