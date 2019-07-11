FROM alpine AS builder

ARG RCON_CLI_VERSION=1.4.4

ADD https://github.com/itzg/rcon-cli/releases/download/${RCON_CLI_VERSION}/rcon-cli_${RCON_CLI_VERSION}_linux_amd64.tar.gz /tmp/rcon-cli.tgz

RUN mkdir -p /opt/rcon-cli && \
    tar x -f /tmp/rcon-cli.tgz -C /opt/rcon-cli && \
    rm /tmp/rcon-cli.tgz



FROM alpine

RUN apk -U --no-cache add \
    bash \
    coreutils \
    unzip

COPY --from=builder /opt/rcon-cli/rcon-cli /opt/rcon-cli/rcon-cli

RUN ln -s /opt/rcon-cli/rcon-cli /usr/bin

ENTRYPOINT ["/opt/backup-loop.sh"]

VOLUME ["/data", "/backups"]

COPY backup-loop.sh /opt/

