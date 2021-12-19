#!/bin/bash

set -euo pipefail

if [ "${DEBUG:-false}" == "true" ]; then
  set -x
fi

: "${SRC_DIR:=/data}"
: "${DEST_DIR:=/backups}"
: "${BACKUP_NAME:=world}"
: "${INITIAL_DELAY:=2m}"
: "${BACKUP_INTERVAL:=${INTERVAL_SEC:-24h}}"
: "${PAUSE_IF_NO_PLAYERS:=false}"
: "${PLAYERS_ONLINE_CHECK_INTERVAL:=5m}"
: "${BACKUP_METHOD:=tar}" # currently one of tar, restic
: "${TAR_COMPRESS_METHOD:=gzip}"  # bzip2 gzip zstd
: "${ZSTD_PARAMETERS:=-3 --long=25 --single-thread}"
: "${PRUNE_BACKUPS_DAYS:=7}"
: "${PRUNE_RESTIC_RETENTION:=--keep-within ${PRUNE_BACKUP_DAYS:-7}d}"
: "${SERVER_PORT:=25565}"
: "${RCON_HOST:=localhost}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=minecraft}"
: "${RCON_RETRIES:=5}"
: "${RCON_RETRY_INTERVAL:=10s}"
: "${EXCLUDES:=*.jar,cache,logs}" # Comma separated list of glob(3) patterns
: "${LINK_LATEST:=false}"
: "${RESTIC_ADDITIONAL_TAGS:=mc_backups}" # Space separated list of restic tags
: "${XDG_CONFIG_HOME:=/config}" # for rclone's base config path
: "${ONE_SHOT:=false}"
: "${TZ:=Etc/UTC}"
: "${RCLONE_REPOSITORY:={DEST_DIR}"
: "${RCLONE_COMPRESS_METHOD:=gzip}"
: "${RCLONE_REMOTE:=}"
export TZ

export RCON_HOST
export RCON_PORT
export RCON_PASSWORD
export XDG_CONFIG_HOME

###############
##  common   ##
## functions ##
###############

is_one_shot() {
  if [[ ${ONE_SHOT^^} = TRUE ]]; then
    return 0
  else
    return 1
  fi
}

is_elem_in_array() {
  # $1 = element
  # All remaining arguments are array to search for the element in
  if [ "$#" -lt 2 ]; then
    log INTERNALERROR "Wrong number of arguments passed to is_elem_in_array function"
    return 2
  fi
  local element="${1}"
  shift
  local e
  for e; do
    if [ "${element}" == "${e}" ]; then
      return 0
    fi
  done
  return 1
}

log() {
  if [ "$#" -lt 1 ]; then
    log INTERNALERROR "Wrong number of arguments passed to log function"
    return 2
  fi
  local level="${1}"
  shift
  local valid_levels=(
    "INFO"
    "WARN"
    "ERROR"
    "INTERNALERROR"
  )
  if ! is_elem_in_array "${level}" "${valid_levels[@]}"; then
    log INTERNALERROR "Log level ${level} is not a valid level."
    return 2
  fi
  (
    # If any arguments are passed besides log level
    if [ "$#" -ge 1 ]; then
      # then use them as log message(s)
      <<<"${*}" cat -
    else
      # otherwise read log messages from standard input
      cat -
    fi
    if [ "${level}" == "INTERNALERROR" ]; then
      echo "Please report this: https://github.com/itzg/docker-mc-backup/issues"
    fi
  ) | awk -v level="${level}" '{ printf("%s %s %s\n", strftime("%FT%T%z"), level, $0); fflush(); }'
} >&2

retry() {
  if [ "$#" -lt 3 ]; then
    log INTERNALERROR "Wrong number of arguments passed to retry function"
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

is_function() {
  if [ "${#}" -ne 1 ]; then
    log INTERNALERROR "is_function expects 1 argument, received ${#}"
  fi
  name="${1}"
  [ "$(type -t "${name}")" == "function" ]
}

call_if_function_exists() {
  if [ "${#}" -lt 1 ]; then
    log INTERNALERROR "call_if_function_exists expects at least 1 argument, received ${#}"
    return 2
  fi
  function_name="${1}"
  if is_function "${function_name}"; then
    "${@}"
  else
    log INTERNALERROR "${function_name} is not a valid function!"
    return 2
  fi
}

#####################
## specific method ##
##    functions    ##
#####################
# Each function that corresponds to a name of a backup method
# Should define following functions inside them
# init() -> called before entering loop. Verify arguments, prepare for operations etc.
# backup() -> create backup. It's guaranteed that all data is already flushed to disk.
# prune() -> prune old backups. PRUNE_BACKUPS_DAYS is guaranteed to be positive.


tar() {
  _find_old_backups() {
    find "${DEST_DIR}" -maxdepth 1 -name "*.${backup_extension}" -mtime "+${PRUNE_BACKUPS_DAYS}" "${@}"
  }

  init() {
    mkdir -p "${DEST_DIR}"
    case "${TAR_COMPRESS_METHOD}" in
        gzip)
        readonly tar_parameters=("--gzip")
        readonly backup_extension="tgz"
        ;;

        bzip2)
        readonly tar_parameters=("--bzip2")
        readonly backup_extension="bz2"
        ;;

        zstd)
        readonly tar_parameters=("--use-compress-program" "zstd ${ZSTD_PARAMETERS}")
        readonly backup_extension="tar.zst"
        ;;

        *)
        log ERROR 'TAR_COMPRESS_METHOD is not valid!'
        exit 1
        ;;
    esac
  }
  backup() {
    ts=$(date +"%Y%m%d-%H%M%S")
    outFile="${DEST_DIR}/${BACKUP_NAME}-${ts}.${backup_extension}"
    log INFO "Backing up content in ${SRC_DIR} to ${outFile}"
    command tar "${excludes[@]}" "${tar_parameters[@]}" -cf "${outFile}" -C "${SRC_DIR}" . || exitCode=$?
    if [ ${exitCode:-0} -eq 1 ]; then
      log WARN "tar exited with code 1. Ignoring"
    fi
    if [ ${exitCode:-0} -gt 1 ]; then
      log ERROR "tar exited with code ${exitCode}! Aborting"
      exit 1
    fi
    if [ "${LINK_LATEST^^}" == "TRUE" ]; then
      ln -sf "${BACKUP_NAME}-${ts}.${backup_extension}" "${DEST_DIR}/latest.${backup_extension}"
    fi
  }
  prune() {
    if [ -n "$(_find_old_backups -print -quit)" ]; then
      log INFO "Pruning backup files older than ${PRUNE_BACKUPS_DAYS} days"
      _find_old_backups -print -delete | awk '{ printf "Removing %s\n", $0 }' | log INFO
    fi
  }
  call_if_function_exists "${@}"
}


restic() {
  _delete_old_backups() {
    # shellcheck disable=SC2086
    command restic forget --tag "${restic_tags_filter}" ${PRUNE_RESTIC_RETENTION} "${@}"
  }
  _check() {
      if ! output="$(command restic check 2>&1)"; then
        log ERROR "Repository contains error! Aborting"
        <<<"${output}" log ERROR
        return 1
      fi
  }
  init() {
    if [ -z "${RESTIC_PASSWORD:-}" ] \
        && [ -z "${RESTIC_PASSWORD_FILE:-}" ] \
        && [ -z "${RESTIC_PASSWORD_COMMAND:-}" ]; then
      log ERROR "At least one of" RESTIC_PASSWORD{,_FILE,_COMMAND} "needs to be set!"
      return 1
    fi
    if [ -z "${RESTIC_REPOSITORY:-}" ]; then
      log ERROR "RESTIC_REPOSITORY is not set!"
      return 1
    fi
    if output="$(command restic snapshots 2>&1 >/dev/null)"; then
      log INFO "Repository already initialized"
      _check
    elif <<<"${output}" grep -q '^Is there a repository at the following location?$'; then
      log INFO "Initializing new restic repository..."
      command restic init | log INFO
    elif <<<"${output}" grep -q 'wrong password'; then
      <<<"${output}" log ERROR
      log ERROR "Wrong password provided to an existing repository?"
      return 1
    else
      <<<"${output}" log ERROR
      log INTERNALERROR "Unhandled restic repository state."
      return 2
    fi

    # Used to construct tagging arguments and filters for snapshots
    read -ra restic_tags <<< ${RESTIC_ADDITIONAL_TAGS}
    restic_tags+=("${BACKUP_NAME}")
    readonly restic_tags

    # Arguments to use to tag the snapshots with
    restic_tags_arguments=()
    local tag
    for tag in "${restic_tags[@]}"; do
        restic_tags_arguments+=( --tag "$tag")
    done
    readonly restic_tags_arguments
    # Used for filtering backups to only match ours
    restic_tags_filter="$(IFS=,; echo "${restic_tags[*]}")"
    readonly restic_tags_filter
  }
  backup() {
    log INFO "Backing up content in ${SRC_DIR}"
    command restic backup "${restic_tags_arguments[@]}" "${excludes[@]}" "${SRC_DIR}" | log INFO
  }
  prune() {
    # We cannot use `grep -q` here - see https://github.com/restic/restic/issues/1466
    if _delete_old_backups --dry-run | grep '^remove [[:digit:]]* snapshots:$' >/dev/null; then
      log INFO "Pruning snapshots using ${PRUNE_RESTIC_RETENTION}"
      _delete_old_backups --prune | log INFO
      _check | log INFO
    fi
  }
  call_if_function_exists "${@}"
}

rclone() {
  _find_old_backups() {
    command rclone lsf --format "tp" "${RCLONE_REMOTE}:${DEST_DIR}" | grep ${BACKUP_NAME} | awk \
            -v DESTINATION="${DEST_DIR}" \
            -v PRUNE_DATE="$(date '+%Y-%m-%d %H:%M:%S' --date="${PRUNE_BACKUPS_DAYS} days ago")" \
            'BEGIN { FS=";" } $1 < PRUNE_DATE { printf "%s/%s\n", DESTINATION, $2 }'
  }
  init() {
    # Check if rclone is installed and configured correctly
    mkdir -p "${DEST_DIR}"
    case "${RCLONE_COMPRESS_METHOD}" in
        gzip)
        readonly tar_parameters=("--gzip")
        readonly backup_extension="tgz"
        ;;

        bzip2)
        readonly tar_parameters=("--bzip2")
        readonly backup_extension="bz2"
        ;;

        zstd)
        readonly tar_parameters=("--use-compress-program" "zstd ${ZSTD_PARAMETERS}")
        readonly backup_extension="tar.zst"
        ;;

        *)
        log ERROR 'RCLONE_COMPRESS_METHOD is not valid!'
        exit 1
        ;;
    esac
  }
  backup() {
    ts=$(date +"%Y%m%d-%H%M%S")
    outFile="${BACKUP_NAME}-${ts}.${backup_extension}"
    log INFO "Backing up content in ${SRC_DIR} to ${outFile}"
    command tar "${excludes[@]}" "${tar_parameters[@]}" -cf "${outFile}" -C "${SRC_DIR}" . || exitCode=$?
    if [ ${exitCode:-0} -eq 1 ]; then
      log WARN "tar exited with code 1. Ignoring"
    fi
    if [ ${exitCode:-0} -gt 1 ]; then
      log ERROR "tar exited with code ${exitCode}! Aborting"
      exit 1
    fi

    command rclone copy "${outFile}" "${RCLONE_REMOTE}:${DEST_DIR}"
    rm "${outFile}"
  }
  prune() {
    if [ -n "$(_find_old_backups)" ]; then
      log INFO "Pruning backup files older than ${PRUNE_BACKUPS_DAYS} days"
      _find_old_backups | tee \
            >(awk '{ printf "Removing %s\n", $0 }' | log INFO) \
            >(while read -r path; do command rclone purge "${path}"; done)
    fi
  }
  call_if_function_exists "${@}"
}

##########
## main ##
##########



if [ -n "${INTERVAL_SEC:-}" ]; then
  log WARN 'INTERVAL_SEC is deprecated. Use BACKUP_INTERVAL instead'
fi

if [ ! -d "${SRC_DIR}" ]; then
  log ERROR 'SRC_DIR does not point to an existing directory!'
  exit 1
fi

if ! is_function "${BACKUP_METHOD}"; then
  log ERROR "Invalid BACKUP_METHOD provided: ${BACKUP_METHOD}"
fi

# We unfortunately can't use a here-string, as it inserts new line at the end
readarray -td, excludes_patterns < <(printf '%s' "${EXCLUDES}")

excludes=()
for pattern in "${excludes_patterns[@]}"; do
  excludes+=(--exclude "${pattern}")
done

"${BACKUP_METHOD}" init

if ! is_one_shot; then
  log INFO "waiting initial delay of ${INITIAL_DELAY}..."
  # shellcheck disable=SC2086
  sleep ${INITIAL_DELAY}
fi

log INFO "waiting for rcon readiness..."
retry ${RCON_RETRIES} ${RCON_RETRY_INTERVAL} rcon-cli save-on


while true; do

  if retry ${RCON_RETRIES} ${RCON_RETRY_INTERVAL} rcon-cli save-off; then
    # No matter what we were doing, from now on if the script crashes
    # or gets shut down, we want to make sure saving is on
    trap 'retry 5 5s rcon-cli save-on' EXIT

    retry ${RCON_RETRIES} ${RCON_RETRY_INTERVAL} rcon-cli save-all flush
    retry ${RCON_RETRIES} ${RCON_RETRY_INTERVAL} sync

    "${BACKUP_METHOD}" backup

    retry ${RCON_RETRIES} ${RCON_RETRY_INTERVAL} rcon-cli save-on
    # Remove our exit trap now
    trap EXIT
  else
    log ERROR "Unable to turn saving off. Is the server running?"
    exit 1
  fi

  if (( PRUNE_BACKUPS_DAYS > 0 )); then
    "${BACKUP_METHOD}" prune
  fi

  if is_one_shot; then
    break
  fi

  # If BACKUP_INTERVAL is not a valid number (i.e. 24h), we want to sleep.
  # Only raw numeric value <= 0 will break
  if (( BACKUP_INTERVAL <= 0 )) &>/dev/null; then
    break
  fi

  if [[ ${PAUSE_IF_NO_PLAYERS^^} = TRUE ]]; then
    while true; do
      if ! PLAYERS_ONLINE=$(mc-monitor status --host "${RCON_HOST}" --port "${SERVER_PORT}" --show-player-count 2>&1); then
        log ERROR "Error querying the server, waiting ${PLAYERS_ONLINE_CHECK_INTERVAL}..."
        sleep "${PLAYERS_ONLINE_CHECK_INTERVAL}"
      elif [ "${PLAYERS_ONLINE}" = 0 ]; then
        log INFO "No players online, waiting ${PLAYERS_ONLINE_CHECK_INTERVAL}..."
        sleep "${PLAYERS_ONLINE_CHECK_INTERVAL}"
      else
        break
      fi
    done
  fi

  log INFO "sleeping ${BACKUP_INTERVAL}..."
  # shellcheck disable=SC2086
  sleep ${BACKUP_INTERVAL}
done
