#!/bin/bash

log() {
  level=$1
  shift
  echo "$(date -Iseconds) ${level} $*"
}

backupSet=${BACKUP_SET}
excludes="--exclude '*.jar'"

case $TYPE in
  FTB|CURSEFORGE)
    cd ${SRC_DIR}/FeedTheBeast
    ;;
  *)
    cd ${SRC_DIR}
    ;;
esac

backupSet="${backupSet} ${LEVEL}"
backupSet="${backupSet} $(find . -maxdepth 1 -name '*.properties' -o -name '*.yml' -o -name '*.yaml' -o -name '*.json')"

if [ -d plugins ]; then
  backupSet="${backupSet} plugins"
fi

log INFO "waiting for rcon readiness..."
while true; do
  rcon-cli save-on >& /dev/null && break

  sleep 10
done
log INFO "waiting initial delay of ${INITIAL_DELAY} seconds..."
sleep ${INITIAL_DELAY}

while true; do
  ts=$(date -u +"%Y%m%d-%H%M%S")

  rcon-cli save-off
  if [ $? = 0 ]; then

    rcon-cli save-all
    if [ $? = 0 ]; then

      outFile="${DEST_DIR}/${BACKUP_NAME}-${ts}.tgz"
      log INFO "backing up content in $(pwd) to ${outFile}"
      tar cz -f ${outFile} ${backupSet} ${excludes}
      if [ $? != 0 ]; then
        log ERROR "backup failed"
      else
        log INFO "successfully backed up"
      fi

    fi

    rcon-cli save-on
  else
    log ERROR "rcon save-off command failed"
  fi

  if (( ${PRUNE_BACKUPS_DAYS} > 0 )); then
    log INFO "pruning backup files older than ${PRUNE_BACKUPS_DAYS} days"
    find ${DEST_DIR} -mtime +${PRUNE_BACKUPS_DAYS} -delete
  fi

  log INFO "sleeping ${INTERVAL_SEC} seconds..."
  sleep ${INTERVAL_SEC}
done
