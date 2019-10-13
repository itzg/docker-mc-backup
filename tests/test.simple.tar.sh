#!/usr/bin/env bash
set -euo pipefail

set -x

WORKDIR="$(readlink -m "$(dirname "${0}")")"

cd "${WORKDIR}/.."

TMP_DIR="$(mktemp --directory)"
trap 'sudo rm -rf "${TMP_DIR}"' EXIT

: "${SRC_DIR:=/tmp/source}"
: "${DEST_DIR:=/tmp/dest}"
: "${BACKUP_INTERVAL:=0}"
: "${INITIAL_DELAY:=5s}"
: "${EXCLUDES:='*.jar,exclude_dir'}"
: "${RCON_PATH:=/usr/bin/rcon-cli}"
: "${PRUNE_BACKUPS_DAYS:=3}"

export LOCAL_SRC_DIR="${TMP_DIR}/${SRC_DIR}"
export LOCAL_DEST_DIR="${TMP_DIR}/${DEST_DIR}"
export TMP_DIR

"${WORKDIR}/common.bootstrap.sh"

export SRC_DIR
export DEST_DIR
export EXTRACT_DIR="${TMP_DIR}/extract"
export BACKUP_INTERVAL
export INITIAL_DELAY
export EXCLUDES
export RCON_PATH
export PRUNE_BACKUPS_DAYS

mkdir "${EXTRACT_DIR}"
touch -d "$(( PRUNE_BACKUPS_DAYS + 2 )) days ago" "${LOCAL_DEST_DIR}/fake_backup_that_should_be_deleted.tgz"
ls -al "${LOCAL_DEST_DIR}"

timeout 50 docker run --rm \
          --env SRC_DIR \
          --env DEST_DIR \
          --env BACKUP_INTERVAL \
          --env INITIAL_DELAY \
          --env EXCLUDES \
          --env PRUNE_BACKUPS_DAYS \
          --env DEBUG \
          --mount "type=bind,src=${LOCAL_SRC_DIR},dst=${SRC_DIR}" \
          --mount "type=bind,src=${LOCAL_DEST_DIR},dst=${DEST_DIR}" \
          --mount "type=bind,src=${TMP_DIR}/rcon-cli,dst=${RCON_PATH}" \
          testimg

tree "${LOCAL_DEST_DIR}"
tar -xzf "${LOCAL_DEST_DIR}/"*.tgz -C "${EXTRACT_DIR}"
tree "${EXTRACT_DIR}"
[ -z "$(find "${EXTRACT_DIR}" -name "exclude_*" -print -quit)" ]
[ 4 -eq "$(find "${EXTRACT_DIR}" -name "backup_me*" -print | wc -l)" ]

