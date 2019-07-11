#!/bin/bash

set -euo pipefail

readonly backup_extension="tgz"
: "${SRC_DIR:=/data}"
: "${DEST_DIR:=/backups}"
: "${BACKUP_NAME:=world}"
: "${INITIAL_DELAY:=2m}"
: "${BACKUP_INTERVAL:=${INTERVAL_SEC:-24h}}"
: "${PRUNE_BACKUPS_DAYS:=7}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=minecraft}"
: "${EXCLUDES:=*.jar,cache,logs}" # Comma separated list of glob(3) patterns

export RCON_PORT
export RCON_PASSWORD

log() {
  if [ "$#" -lt 1 ]; then
    echo "Wrong number of arguments passed to log function" >&2
    return 1
  fi
  local level="${1}"
  shift
  (
    # If any arguments are passed besides log level
    if [ "$#" -ge 1 ]; then
      # then use them as log message(s)
      <<<"${*}" cat -
    else
      # otherwise read log messages from standard input
      cat -
    fi
  ) | awk -v level="${level}" '{ printf("%s %s %s\n", strftime("%FT%T%z"), level, $0); fflush(); }'
}

find_old_backups() {
  find "${DEST_DIR}" -maxdepth 1 -name "*.${backup_extension}" -mtime "+${PRUNE_BACKUPS_DAYS}" "${@}"
}

retry() {
  if [ "$#" -lt 3 ]; then
    log ERROR "Wrong number of arguments passed to retry function"
    return 1
  fi

  # How many times should we retry?
  # Value smaller than zero means infinitely
  local retries="${1}"
  # Time to sleep between retries
  local interval="${2}"
  readonly retries interval
  shift 2

  if (( retries < 0 )); then
    local retries_msg="infinite"
  else
    local retries_msg="${retries}"
  fi

  local i=-1 # -1 since we will increment it before printing
  while (( retries >= ++i )) || [ "${retries_msg}" != "${retries}" ]; do
    # Send SIGINT after 5 minutes. If it doesn't shut down in 30 seconds, kill it.
    if output="$(timeout --signal=SIGINT --kill-after=30s 5m "${@}" 2>&1 | tr '\n' '\t')"; then
      log INFO "Command executed successfully ${*}"
      return 0
    else
      log ERROR "Unable to execute ${*} - try ${i}/${retries_msg}. Retrying in ${interval}"
      if [ -n "${output}" ]; then
        log ERROR "Failure reason: ${output}"
      fi
    fi
    # shellcheck disable=SC2086
    sleep ${interval}
  done
  return 2
}

if [ -n "${INTERVAL_SEC:-}" ]; then
  log WARN 'INTERVAL_SEC is deprecated. Use BACKUP_INTERVAL instead'
fi

# We unfortunately can't use a here-string, as it inserts new line at the end
readarray -td, excludes_patterns < <(printf '%s' "${EXCLUDES}")

excludes=()
for pattern in "${excludes_patterns[@]}"; do
  excludes+=(--exclude "${pattern}")
done


log INFO "waiting initial delay of ${INITIAL_DELAY}..."
# shellcheck disable=SC2086
sleep ${INITIAL_DELAY}

log INFO "waiting for rcon readiness..."
# 20 times, 10 second delay
retry 20 10s rcon-cli save-on


while true; do
  ts=$(date -u +"%Y%m%d-%H%M%S")

  if retry 5 10s rcon-cli save-off; then
    # No matter what we were doing, from now on if the script crashes
    # or gets shut down, we want to make sure saving is on
    trap 'retry 5 5s rcon-cli save-on' EXIT

    retry 5 10s rcon-cli save-all
    outFile="${DEST_DIR}/${BACKUP_NAME}-${ts}.${backup_extension}"
    log INFO "backing up content in ${SRC_DIR} to ${outFile}"

    # shellcheck disable=SC2086
    if tar "${excludes[@]}" -czf "${outFile}" -C "${SRC_DIR}" .; then
      log INFO "successfully backed up"
    else
      log ERROR "backup failed"
    fi

    retry 20 10s rcon-cli save-on
    # Remove our exit trap now
    trap EXIT
  else
    log ERROR "Unable to turn saving off. Is the server running?"
    exit 1
  fi

  if (( PRUNE_BACKUPS_DAYS > 0 )) && [ -n "$(find_old_backups -print -quit)" ]; then
    log INFO "pruning backup files older than ${PRUNE_BACKUPS_DAYS} days"
    find_old_backups -print -delete | log INFO
  fi

  # If BACKUP_INTERVAL is not a valid number (i.e. 24h), we want to sleep.
  # Only raw numeric value <= 0 will break
  if (( BACKUP_INTERVAL <= 0 )) &>/dev/null; then
    break
  else
    log INFO "sleeping ${BACKUP_INTERVAL}..."
    # shellcheck disable=SC2086
    sleep ${BACKUP_INTERVAL}
  fi
done
