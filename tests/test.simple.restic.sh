#!/usr/bin/env bash
set -euo pipefail

set -x

WORKDIR="$(readlink -m "$(dirname "${0}")")"

cd "${WORKDIR}/.."

TMP_DIR="$(mktemp --directory)"
trap 'sudo rm -rf "${TMP_DIR}"' EXIT

: "${SRC_DIR:=/tmp/source}"
: "${DEST_DIR:=/tmp/dest}"
: "${RESTIC_REPOSITORY:=/tmp/dest}"
: "${BACKUP_INTERVAL:=0}"
: "${INITIAL_DELAY:=0s}"
: "${EXCLUDES:='*.jar,exclude_dir'}"
: "${RCON_PATH:=/usr/bin/rcon-cli}"
: "${RESTIC_PASSWORD:=1234}"

export LOCAL_SRC_DIR="${TMP_DIR}/${SRC_DIR}"
export LOCAL_DEST_DIR="${TMP_DIR}/${DEST_DIR}"
export TMP_DIR

"${WORKDIR}/common.bootstrap.sh"

export SRC_DIR
export DEST_DIR
export RESTIC_REPOSITORY
export BACKUP_INTERVAL
export INITIAL_DELAY
export EXCLUDES
export RCON_PATH
export RESTIC_PASSWORD

timeout --kill-after=20 50 docker run --rm \
    --env SRC_DIR \
    --env BACKUP_INTERVAL \
    --env INITIAL_DELAY \
    --env EXCLUDES \
    --env PRUNE_BACKUPS_DAYS \
    --env RESTIC_REPOSITORY \
    --env RESTIC_PASSWORD \
    --env DEBUG \
    --env BACKUP_METHOD=restic \
    --mount "type=bind,src=${LOCAL_SRC_DIR},dst=${SRC_DIR}" \
    --mount "type=bind,src=${LOCAL_DEST_DIR},dst=${DEST_DIR}" \
    --mount "type=bind,src=${TMP_DIR}/rcon-cli,dst=${RCON_PATH}" \
    testimg

restic() {
  docker run --rm \
      --env RESTIC_REPOSITORY \
      --env RESTIC_PASSWORD \
      --entrypoint=restic \
      --mount "type=bind,src=${LOCAL_SRC_DIR},dst=${SRC_DIR}" \
      --mount "type=bind,src=${LOCAL_DEST_DIR},dst=${DEST_DIR}" \
      testimg "${@}"
}
restic ls latest
! restic ls latest 2>/dev/null | grep -q "exclude_"
[ 4 -eq "$(restic ls latest 2>/dev/null | grep -c "backup_me")" ]
