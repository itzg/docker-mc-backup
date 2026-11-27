#!/usr/bin/env bash
set -euo pipefail

set -x

WORKDIR="$(readlink -m "$(dirname "${0}")")"

cd "${WORKDIR}/.."

TMP_DIR="$(mktemp --directory)"
trap 'sudo rm -rf "${TMP_DIR}"' EXIT

: "${SRC_DIR:=/tmp/source}"
: "${DEST_DIR:=/tmp/dest}"
: "${RCON_PATH:=/usr/bin/rcon-cli}"

export LOCAL_SRC_DIR="${TMP_DIR}/${SRC_DIR}"
export LOCAL_DEST_DIR="${TMP_DIR}/${DEST_DIR}"
export TMP_DIR

"${WORKDIR}/common.bootstrap.sh"

# The latest symlink must not take one of the PRUNE_BACKUPS_COUNT slots
for run in 1 2; do
  timeout 50 docker run --rm \
            --env SRC_DIR="${SRC_DIR}" \
            --env DEST_DIR="${DEST_DIR}" \
            --env BACKUP_INTERVAL=0 \
            --env INITIAL_DELAY=0s \
            --env LINK_LATEST=true \
            --env PRUNE_BACKUPS_COUNT=1 \
            --mount "type=bind,src=${LOCAL_SRC_DIR},dst=${SRC_DIR}" \
            --mount "type=bind,src=${LOCAL_DEST_DIR},dst=${DEST_DIR}" \
            --mount "type=bind,src=${TMP_DIR}/rcon-cli,dst=${RCON_PATH}" \
            localhost:5000/itzg/mc-backup:latest
  sleep 1
done

tree "${LOCAL_DEST_DIR}"
[ 1 -eq "$(find "${LOCAL_DEST_DIR}" -maxdepth 1 -type f -name '*.tar.gz' | wc -l)" ]
tar -tzf "${LOCAL_DEST_DIR}/latest.tar.gz" > /dev/null
