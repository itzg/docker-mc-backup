#!/bin/bash

log() {
  level=$1
  shift
  echo "$(date -Iseconds) ${level} $*"
}

case $TYPE in
  FTB|CURSEFORGE)
    resolvedSrcDir="${SRC_DIR}/FeedTheBeast"
    ;;
  *)
    resolvedSrcDir="${SRC_DIR}"
    ;;
esac

log INFO "waiting initial delay of ${INITIAL_DELAY} seconds..."
sleep ${INITIAL_DELAY}

while true; do
  ts=$(date -u +"%Y%m%d-%H%M%S")

  rcon-cli save-off
  if [ $? = 0 ]; then

    rcon-cli save-all
    if [ $? = 0 ]; then

      outFile="${DEST_DIR}/${BACKUP_NAME}-${ts}.tgz"
      log INFO "backing up '${LEVEL}' in ${resolvedSrcDir} to ${outFile}"
      tar c -f ${outFile} -C ${resolvedSrcDir} ${LEVEL}
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

  log INFO "Sleeping ${INTERVAL_SEC} seconds..."
  sleep ${INTERVAL_SEC}
done