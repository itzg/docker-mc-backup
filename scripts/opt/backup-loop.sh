#!/bin/bash

set -euo pipefail

function isTrue() {
  [ "${1,,}" == "true" ]
}
function isDebug() {
  isTrue "$DEBUG"
}

: "${DEBUG:=false}"
if isDebug; then
  set -x
fi

: "${SRC_DIR:=/data}"
: "${DEST_DIR:=/backups}"
: "${BACKUP_NAME:=world}"
: "${INITIAL_DELAY:=2m}"
: "${BACKUP_INTERVAL:=${INTERVAL_SEC:-24h}}"
: "${BACKUP_ON_STARTUP:=true}"
: "${PAUSE_IF_NO_PLAYERS:=false}"
: "${PLAYERS_ONLINE_CHECK_INTERVAL:=5m}"
: "${BACKUP_METHOD:=tar}" # currently one of tar, restic, rsync
: "${TAR_COMPRESS_METHOD:=gzip}"  # bzip2 gzip lzip lzma lzop xz compress zstd
: "${TAR_PARAMETERS:=}"
: "${PRUNE_BACKUPS_DAYS:=7}"
: "${PRUNE_BACKUPS_COUNT:=}"
: "${PRUNE_RESTIC_RETENTION:=--keep-within ${PRUNE_BACKUP_DAYS:-7}d}"
: "${RCON_HOST:=localhost}"
: "${RCON_PORT:=25575}"
: "${SERVER_HOST:=${RCON_HOST}}"
: "${SERVER_PORT:=25565}"

: "${RCON_RETRIES:=5}"
: "${RCON_RETRY_INTERVAL:=10s}"
: "${ENABLE_SAVE_ALL:=true}"
: "${ENABLE_SYNC:=true}"
: "${EXCLUDES=*.jar,cache,logs,*.tmp}" # Comma separated list of glob(3) patterns
: "${EXCLUDES_FILE:=}" # Path to file containing list of glob(3) patterns
: "${LINK_LATEST:=false}"
: "${RESTIC_ADDITIONAL_TAGS=mc_backups}" # Space separated list of restic tags
: "${RESTIC_HOSTNAME:=$(hostname)}"
: "${RESTIC_VERBOSE:=false}"
: "${RESTIC_LIMIT_UPLOAD:=0}"
: "${RESTIC_RETRY_LOCK:=1m}" # Max time restic will retry to acquire a repository lock before failing
: "${XDG_CONFIG_HOME:=/config}" # for rclone's base config path
: "${ONE_SHOT:=false}"
: "${TZ:=Etc/UTC}"
: "${RCLONE_COMPRESS_METHOD:=gzip}"
: "${RCLONE_REMOTE:=}"
: "${RCLONE_DEST_DIR:=}"
: "${PRE_SAVE_ALL_SCRIPT:=}"
: "${PRE_BACKUP_SCRIPT:=}"
: "${PRE_SAVE_ON_SCRIPT:=}"
: "${POST_BACKUP_SCRIPT:=}"
: "${PRE_SAVE_ALL_SCRIPT_FILE:=}"
: "${PRE_BACKUP_SCRIPT_FILE:=}"
: "${PRE_SAVE_ON_SCRIPT_FILE:=}"
: "${POST_BACKUP_SCRIPT_FILE:=}"
export TZ

export RCON_HOST
export RCON_PORT
export XDG_CONFIG_HOME
export SRC_DIR
export DEST_DIR
export BACKUP_NAME

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

is_paused() {
    [[ -e "${SRC_DIR}/.paused" ]]
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
  # temporarily disable debug mode's setting of xtrace to avoid all the debug noise of logging
  local oldState
  # The  return  status  when listing options is zero if all optnames are enabled, non- zero otherwise.
  oldState=$(shopt -po xtrace || true)
  shopt -u -o xtrace

  if [ "$#" -lt 1 ]; then
    log INTERNALERROR "Wrong number of arguments passed to log function"
    eval "$oldState"
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
    eval "$oldState"
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
  eval "$oldState"
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

load_rcon_password() {
  if ! [[ -v RCON_PASSWORD ]] && ! [[ -v RCON_PASSWORD_FILE ]] && [[ -f "${SRC_DIR}/.rcon-cli.env" ]]; then
    . "${SRC_DIR}/.rcon-cli.env"
    # shellcheck disable=SC2154
    # since it comes from rcon-cli
    RCON_PASSWORD="$password"
  elif [[ -v RCON_PASSWORD_FILE ]]; then
    if [ ! -e "${RCON_PASSWORD_FILE}" ]; then
      log ERROR "Initial RCON password file ${RCON_PASSWORD_FILE} does not seems to exist."
      log ERROR "Please ensure your configuration."
      log ERROR "If you are using Docker Secrets feature, please check this for further information: "
      log ERROR " https://docs.docker.com/engine/swarm/secrets"
      exit 1
    else
      RCON_PASSWORD=$(cat "${RCON_PASSWORD_FILE}")
    fi
  elif ! [[ -v RCON_PASSWORD ]]; then
    # Legacy default
    RCON_PASSWORD=minecraft
  fi
  export RCON_PASSWORD
}

#####################
## specific method ##
##    functions    ##
#####################
# Each function that corresponds to a name of a backup method
# Should define following functions inside them
# init() -> called before entering loop. Verify arguments, prepare for operations etc.
# backup() -> create backup. It's guaranteed that all data is already flushed to disk.
#   Passed a path to a log file that the backup tool's stdout and stderr should be written to.
# prune() -> prune old backups. PRUNE_BACKUPS_DAYS is guaranteed to be positive.


# shellcheck disable=SC2317
tar() {
  readarray -td, includes_patterns < <(printf '%s' "${INCLUDES:-.}")

  _find_old_backups() {
    find "${DEST_DIR}" -maxdepth 1 -name "*.${backup_extension}" -mmin "+$prune_backups_minutes" "${@}"
  }

  _find_extra_backups() {
  find "${DEST_DIR}" -maxdepth 1 -name "*.${backup_extension}" -exec ls -1Nt {} \+ | \
    tail -n +$((PRUNE_BACKUPS_COUNT + 1)) | \
    tr '\n' '\0'
  }

  init() {
    : "${SKIP_LOCKING:=false}"

    mkdir -p "${DEST_DIR}"

    # NOTES
    # - can't use $(( )) since bash doesn't support floating point
    # - mmin needs to be an integer operand and bc produces decimal values by default
    #   - scale=0 to set zero decimal point values
    #   - however, also need the /1 trick to truncate to an integer : https://stackoverflow.com/a/53532113/121324
    prune_backups_minutes=$(echo "scale=0; (${PRUNE_BACKUPS_DAYS} * 1440)/1"|bc)

    case "${TAR_COMPRESS_METHOD}" in
        bzip2)
        tar_parameters=("bzip2")
        readonly backup_extension="tar.bz2"
        ;;

        gzip)
        tar_parameters=("gzip")
        readonly backup_extension="tar.gz"
        ;;

        lzip)
        tar_parameters=("lzip")
        readonly backup_extension="tar.lz"
        ;;

        lzma)
        tar_parameters=("lzma")
        readonly backup_extension="tar.lzma"
        ;;

        lzop)
        tar_parameters=("lzop")
        readonly backup_extension="tar.lzo"
        ;;

        xz)
        tar_parameters=("xz")
        readonly backup_extension="tar.xz"
        ;;

        compress)
        tar_parameters=("compress")
        readonly backup_extension="tar.Z"
        ;;

        zstd)
        tar_parameters=("zstd")
        readonly backup_extension="tar.zst"
        ;;

        *)
        log ERROR 'TAR_COMPRESS_METHOD is not valid!'
        exit 1
        ;;
    esac

    tar_parameters+=("${TAR_PARAMETERS[@]}")
    readonly tar_parameters
  }
  backup() {
    if [[ ! $1 ]]; then
      log INTERNALERROR "Backup log path not passed to tar.backup! Aborting"
      exit 1
    fi

    ts=$(date +"%Y%m%d-%H%M%S")
    outFile="${DEST_DIR}/${BACKUP_NAME}-${ts}.${backup_extension}"
    log INFO "Backing up content in ${SRC_DIR} to ${outFile}"
    exitCode=0
    command tar "${excludes[@]}" --use-compress-program "${tar_parameters[@]}" -cf "${outFile}" -C "${SRC_DIR}" "${includes_patterns[@]}" 2>&1 | tee "$1" || exitCode=$?
    if [[ $exitCode -eq 1 ]]; then
      log WARN "Dat files changed as we read it"
    fi
    if [ "${LINK_LATEST^^}" == "TRUE" ]; then
      ln -sf "${BACKUP_NAME}-${ts}.${backup_extension}" "${DEST_DIR}/latest.${backup_extension}"
    fi
    return $exitCode
  }
  prune() {

    if [ -n "${PRUNE_BACKUPS_DAYS}" ] && [ "${PRUNE_BACKUPS_DAYS}" -gt 0 ]; then
      log INFO "Pruning backup files older than ${PRUNE_BACKUPS_DAYS} days"
      if [ -n "$(_find_old_backups -print -quit)" ]; then
        _find_old_backups -print -delete | awk '{ printf "Removing %s\n", $0 }' | log INFO
      fi
    fi

    if [ -n "${PRUNE_BACKUPS_COUNT}" ] && [ "${PRUNE_BACKUPS_COUNT}" -gt 0 ]; then
      log INFO "Pruning backup files to keep only the latest ${PRUNE_BACKUPS_COUNT} backups"
      _find_extra_backups | xargs -r -0 -n 1 rm -v | log INFO
    fi
  }
  call_if_function_exists "${@}"
}

# shellcheck disable=SC2317
rsync() {
  _find_old_backups() {
    find "${DEST_DIR}" -maxdepth 1 -type d -mtime "+${PRUNE_BACKUPS_DAYS}" "${@}"
  }

  _find_extra_backups() {
    find "${DEST_DIR}" -maxdepth 1 -type d ! -path "${DEST_DIR}" -print0  -exec ls -NtAd {} \+ | \
    tail -n +$((PRUNE_BACKUPS_COUNT + 1)) | \
    tr '\n' '\0'
  }

  init() {
    : "${SKIP_LOCKING:=false}"

    mkdir -p "${DEST_DIR}"
  }
  backup() {
    if [[ ! $1 ]]; then
      log INTERNALERROR "Backup log path not passed to rsync.backup! Aborting"
      exit 1
    fi

    ts=$(date +"%Y%m%d-%H%M%S")
    outFile="${DEST_DIR}/${BACKUP_NAME}-${ts}"
    if [ -d "${DEST_DIR}/latest" ]; then
      log INFO "Latest found so using it for link"
      link_dest=("--link-dest" "${DEST_DIR}/latest")
    elif [ $(ls "${DEST_DIR}" | wc -l ) -lt 1 ]; then
      log INFO "No previous backups. Running full"
      link_dest=()
    else
      log INFO "Searching for latest backup to link with"
      link_dest=("--link-dest" $(ls -td "${DEST_DIR}/${BACKUP_NAME}-"*|head -1))
    fi
    log INFO "Backing up content in ${SRC_DIR} to ${outFile}"
    mkdir -p $outFile
    exitCode=0
    command rsync -a "${link_dest[@]}" "${excludes[@]}" "${SRC_DIR}/" "${outFile}/" 2>&1 | tee "$1" || exitCode=$?
    if [[ $exitCode -eq 0 ]]; then
      touch "${outFile}"
      true
    elif [[ $exitCode -eq 1 ]]; then
      log WARN "Dat files changed as we read it"
    fi
    if [ "${LINK_LATEST^^}" == "TRUE" ]; then
      ln -sfT "${BACKUP_NAME}-${ts}" "${DEST_DIR}/latest"
    fi
    return $exitCode
  }
  prune() {

    if [ -n "${PRUNE_BACKUPS_DAYS}" ] && [ "${PRUNE_BACKUPS_DAYS}" -gt 0 ]; then
      if [ -n "$(_find_old_backups -print -quit)" ]; then
      log INFO "Pruning backup files older than ${PRUNE_BACKUPS_DAYS} days"
        _find_old_backups -print -exec rm -r {} + | awk '{ printf "Removing %s\n", $0 }' | log INFO
      fi
    fi

    if [ -n "${PRUNE_BACKUPS_COUNT}" ] && [ "${PRUNE_BACKUPS_COUNT}" -gt 0 ]; then
      log INFO "Pruning backup files to keep only the latest ${PRUNE_BACKUPS_COUNT} backups"
      _find_extra_backups | xargs -r -0 -I {} rm -rv {} | awk -v dest_dir="${DEST_DIR}" '
  {
    sub(/removed directory /, "")
    if ($0 !~ dest_dir "/.*/.*") {
      printf "Removing %s\n", $0
    }
  }'| log INFO
    fi
  }
  call_if_function_exists "${@}"
}


# shellcheck disable=SC2317
restic() {
  readarray -td, includes_patterns < <(printf '%s' "${INCLUDES:-${SRC_DIR}}")

  _delete_old_backups() {
    # shellcheck disable=SC2086
    command restic --retry-lock "${RESTIC_RETRY_LOCK}" forget --host "${RESTIC_HOSTNAME}" --tag "${restic_tags_filter}" ${PRUNE_RESTIC_RETENTION} "${@}"
  }

  _unlock() {
  if ! [ -z "${output=$(command restic list locks 2>&1)}" ];then
     log WARN "Confirmed stale lock on repo, unlocking..."
     if [[ unlock=$(command restic unlock 2>&1) == *"success"* ]]; then
        log INFO "Successfully unlocked the repo"
     else
        log ERROR "Unable to unlock the repo. Is there another process running?"
        return 1
     fi
  fi
  }

  _check() {
      if ! output="$(command restic --retry-lock "${RESTIC_RETRY_LOCK}" check 2>&1)"; then
        log ERROR "Repository contains error! Aborting"
        <<<"${output}" log ERROR
        return 1
      fi
  }

  init() {
    : "${SKIP_LOCKING:=true}"

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

    # Duplicate stdout to a first unused file descriptor (fd) 5 which will be used later
    exec 5>&1

    # Run restic, prefix each line and redirect output to fd 5 in a subshell (so it can be shown in realtime).
    # And finally capture the whole output for later processing
    # printf("%s %s %s\n", strftime("%FT%T%z"), level, $0);
    if output="$(command restic cat config 2>&1 >/dev/null | stdbuf -oL awk '{printf("%s restic cat config: %s\n", strftime("%FT%T%z"), $0);}' | tee >(cat - >&5))"; then
      log INFO "Repository already initialized"
      log INFO "Checking for stale locks"
      _unlock
      log INFO "Checking repo integrity"
      _check
    elif <<<"${output}" grep -q 'Fatal: unable to open config file: Stat: 400 Bad Request$'; then
      <<<"${output}" log ERROR
      log ERROR "Unable to open config file. Please check restic configuration"
      return 1
    elif <<<"${output}" grep -q 'Is there a repository at the following location?$'; then
      log INFO "Initializing new restic repository..."
      command restic init | log INFO
    elif <<<"${output}" grep -q 'wrong password'; then
      <<<"${output}" log ERROR
      log ERROR "Wrong password provided to an existing repository?"
      return 1
    elif <<<"${output}" grep -q 'repository is already locked exclusively'; then
      <<<"${output}" log ERROR
      log INFO "Detected stale lock, confirming..."
      _unlock
      log INFO "Checking repo integrity"
      _check
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
    if [[ ! $1 ]]; then
      log INTERNALERROR "Backup log path not passed to restic.backup! Aborting"
      exit 1
    fi

    log INFO "Backing up content in ${SRC_DIR} as host ${RESTIC_HOSTNAME}"
    args=(
      --retry-lock "${RESTIC_RETRY_LOCK}"
      --host "${RESTIC_HOSTNAME}"
      --limit-upload "${RESTIC_LIMIT_UPLOAD}"
    )
    if isDebug || isTrue "$RESTIC_VERBOSE"; then
      args+=(-vv)
    fi
    (cd "$SRC_DIR" &&
          command restic backup "${args[@]}" "${restic_tags_arguments[@]}" "${excludes[@]}" "${includes_patterns[@]}" 2>&1 | tee "$1" | log INFO
    )
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


# shellcheck disable=SC2317
rclone() {
  readarray -td, includes_patterns < <(printf '%s' "${INCLUDES:-.}")

  _find_old_backups() {
    command rclone lsf --format "tp" "${RCLONE_REMOTE}:${RCLONE_DEST_DIR}" | grep ${BACKUP_NAME} | awk \
            -v PRUNE_DATE="$(date '+%Y-%m-%d %H:%M:%S' --date="${PRUNE_BACKUPS_DAYS} days ago")" \
            -v DESTINATION="${RCLONE_DEST_DIR%/}" \
            'BEGIN { FS=";" } $1 < PRUNE_DATE { printf "%s/%s\n", DESTINATION, $2 }'
  }
  init() {
    : "${SKIP_LOCKING:=false}"

    # Check if rclone is installed and configured correctly
    mkdir -p "${DEST_DIR}"
    case "${RCLONE_COMPRESS_METHOD}" in
        bzip2)
        tar_parameters=("bzip2")
        readonly backup_extension="tar.bz2"
        ;;

        gzip)
        tar_parameters=("gzip")
        readonly backup_extension="tar.gz"
        ;;

        lzip)
        tar_parameters=("lzip")
        readonly backup_extension="tar.lz"
        ;;

        lzma)
        tar_parameters=("lzma")
        readonly backup_extension="tar.lzma"
        ;;

        lzop)
        tar_parameters=("lzop")
        readonly backup_extension="tar.lzo"
        ;;

        xz)
        tar_parameters=("xz")
        readonly backup_extension="tar.xz"
        ;;

        compress)
        tar_parameters=("compress")
        readonly backup_extension="tar.Z"
        ;;

        zstd)
        tar_parameters=("zstd")
        readonly backup_extension="tar.zst"
        ;;

        *)
        log ERROR 'TAR_COMPRESS_METHOD is not valid!'
        exit 1
        ;;
    esac

    tar_parameters+=("${TAR_PARAMETERS[@]}")
    readonly tar_parameters
  }

  backup() {
    if [[ ! $1 ]]; then
      log INTERNALERROR "Backup log path not passed to rsync.backup! Aborting"
      exit 1
    fi

    ts=$(date +"%Y%m%d-%H%M%S")
    outFile="${DEST_DIR}/${BACKUP_NAME}-${ts}.${backup_extension}"
    log INFO "Backing up content in ${SRC_DIR} to ${outFile}"
    command tar "${excludes[@]}" --use-compress-program "${tar_parameters[@]}" -cf "${outFile}" -C "${SRC_DIR}" "${includes_patterns[@]}" || exitCode=$?
    if [ ${exitCode:-0} -eq 0 ]; then
      true
    elif [ ${exitCode:-0} -eq 1 ]; then
      log WARN "Dat files changed as we read it"
    elif [ ${exitCode:-0} -gt 1 ]; then
      log ERROR "tar exited with code ${exitCode}! Aborting"
      exit 1
    fi

    exitCode=0
    command rclone copy "${outFile}" "${RCLONE_REMOTE}:${RCLONE_DEST_DIR}" 2>&1 | tee "$1" || exitCode=$?
    rm "${outFile}"
    return $exitCode
  }
  prune() {
    if [ -n "$(_find_old_backups)" ]; then
      log INFO "Pruning backup files older than ${PRUNE_BACKUPS_DAYS} days"
      _find_old_backups | tee \
            >(awk '{ printf "Removing %s\n", $0 }' | log INFO) \
            >(while read -r path; do command rclone deletefile "${RCLONE_REMOTE}:${path}"; done)
    fi
  }
  call_if_function_exists "${@}"
}

do_backup() {
  if [[ $PRE_SAVE_ALL_SCRIPT_FILE ]]; then
    "$PRE_SAVE_ALL_SCRIPT_FILE"
  fi

  if retry ${RCON_RETRIES} ${RCON_RETRY_INTERVAL} rcon-cli save-off; then
    # No matter what we were doing, from now on if the script crashes
    # or gets shut down, we want to make sure saving is on
    trap 'retry 5 5s rcon-cli save-on' EXIT

    if isTrue "$ENABLE_SAVE_ALL"; then
      retry ${RCON_RETRIES} ${RCON_RETRY_INTERVAL} rcon-cli save-all flush

      if isTrue "$ENABLE_SYNC"; then
        retry ${RCON_RETRIES} ${RCON_RETRY_INTERVAL} sync
      fi
    fi

    if [[ $PRE_BACKUP_SCRIPT_FILE ]]; then
      "$PRE_BACKUP_SCRIPT_FILE"
    fi

    backup_status=0
    "${BACKUP_METHOD}" backup "$backup_log" || backup_status=$?

    if [[ $backup_status -ne 0 ]]; then
      log ERROR "Backup failed with exit code $backup_status"
    fi

    if [[ $PRE_SAVE_ON_SCRIPT_FILE ]]; then
      "$PRE_SAVE_ON_SCRIPT_FILE" $backup_status "$backup_log"
    fi

    retry ${RCON_RETRIES} ${RCON_RETRY_INTERVAL} rcon-cli save-on

    # Remove our exit trap now
    trap EXIT

    if [[ $POST_BACKUP_SCRIPT_FILE ]]; then
      "$POST_BACKUP_SCRIPT_FILE" $backup_status "$backup_log"
    fi
  else
    log ERROR "Unable to turn saving off. Is the server running?"
    exit 1
  fi
}

##########
## main ##
##########

if [[ $PRE_SAVE_ALL_SCRIPT ]]; then
  PRE_SAVE_ALL_SCRIPT_FILE=/tmp/pre-save-all
  printf '#!/bin/bash\n\n%s' "$PRE_SAVE_ALL_SCRIPT" > "$PRE_SAVE_ALL_SCRIPT_FILE"
  chmod 700 "$PRE_SAVE_ALL_SCRIPT_FILE"
fi

if [[ $PRE_BACKUP_SCRIPT ]]; then
  PRE_BACKUP_SCRIPT_FILE=/tmp/pre-backup
  printf '#!/bin/bash\n\n%s' "$PRE_BACKUP_SCRIPT" > "$PRE_BACKUP_SCRIPT_FILE"
  chmod 700 "$PRE_BACKUP_SCRIPT_FILE"
fi

if [[ $PRE_SAVE_ON_SCRIPT ]]; then
  PRE_SAVE_ON_SCRIPT_FILE=/tmp/pre-save-on
  printf '#!/bin/bash\n\n%s' "$PRE_SAVE_ON_SCRIPT" > "$PRE_SAVE_ON_SCRIPT_FILE"
  chmod 700 "$PRE_SAVE_ON_SCRIPT_FILE"
fi

if [[ $POST_BACKUP_SCRIPT ]]; then
  POST_BACKUP_SCRIPT_FILE=/tmp/post-backup
  printf '#!/bin/bash\n\n%s' "$POST_BACKUP_SCRIPT" > "$POST_BACKUP_SCRIPT_FILE"
  chmod 700 "$POST_BACKUP_SCRIPT_FILE"
fi

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

excludes=()

# We unfortunately can't use a here-string, as it inserts new line at the end
readarray -td, excludes_patterns < <(printf '%s' "${EXCLUDES}")

for pattern in "${excludes_patterns[@]}"; do
  excludes+=(--exclude "${pattern}")
done

if [[ $EXCLUDES_FILE ]]; then
  if [ ! -e ${EXCLUDES_FILE} ]; then
    log WARN "Excludes file ${EXCLUDES_FILE} does not seems to exist."
  else
    while read -r pattern; do
      if [ -n "${pattern}" ]; then
        excludes+=(--exclude "${pattern}")
      fi
    done < "${EXCLUDES_FILE}"
  fi
fi

"${BACKUP_METHOD}" init

if ! is_one_shot; then
  log INFO "waiting initial delay of ${INITIAL_DELAY}..."
  # shellcheck disable=SC2086
  sleep ${INITIAL_DELAY}
fi

first_run=TRUE
backup_log="$(mktemp)"

##########
## loop ##
##########

while true; do

  if [[ $first_run == TRUE && ${ONE_SHOT^^} = FALSE && ${BACKUP_ON_STARTUP^^} = FALSE ]]; then
    log INFO "Skipping backup on startup"
    first_run=false
  elif ! is_paused; then

    load_rcon_password

    log INFO "waiting for rcon readiness..."
    retry ${RCON_RETRIES} ${RCON_RETRY_INTERVAL} rcon-cli save-on

    if isTrue "${SKIP_LOCKING}" || ! [[ -w "$DEST_DIR" ]]; then
      do_backup
    else

      lockfile="$DEST_DIR/.mc-backup-lock"
      # open lock file
      exec 4<>"$lockfile"
      flock 4
      do_backup
      # close lock file, which also releases lock
      exec 4<&-

    fi
  else # paused
    log INFO "Server is paused, proceeding with backup"

    if [[ $PRE_BACKUP_SCRIPT_FILE ]]; then
      "$PRE_BACKUP_SCRIPT_FILE"
    fi

    backup_status=0
    "${BACKUP_METHOD}" backup "$backup_log" || backup_status=$?

    if [[ $backup_status -ne 0 ]]; then
      log WARN "Backup failed with exit code $backup_status"
    fi

    if [[ $POST_BACKUP_SCRIPT_FILE ]]; then
      "$POST_BACKUP_SCRIPT_FILE" $backup_status "$backup_log"
    fi
  fi

  rm "$backup_log"

  if (( PRUNE_BACKUPS_DAYS > 0 )) || [[ -n "$PRUNE_BACKUPS_COUNT" ]]; then
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
      if is_paused; then
        log INFO "Server is paused, waiting ${PLAYERS_ONLINE_CHECK_INTERVAL}..."
        sleep "${PLAYERS_ONLINE_CHECK_INTERVAL}"
      elif ! PLAYERS_ONLINE=$(mc-monitor status --host "${SERVER_HOST}" --port "${SERVER_PORT}" --show-player-count 2>&1); then
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
