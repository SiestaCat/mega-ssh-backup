#!/usr/bin/env bash
set -euo pipefail
umask 077

log() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') [$1] ${*:2}" >&2
}

log INFO "Starting backup script"

sshArgs=(-i /root/.ssh/id_backup -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
postPending=false
childPid=''

run() {
  log DEBUG "Executing: $*"
  "$@" &
  childPid=$!
  local status=0
  wait "$childPid" || status=$?
  childPid=''
  log DEBUG "Command finished with status $status"
  return "$status"
}

onSignal() {
  local status=$1
  log WARN "Caught signal, exiting with status $status"
  trap - INT TERM HUP
  if [[ -n "$childPid" ]]; then
    log DEBUG "Terminating child PID $childPid"
    kill -TERM "$childPid" 2>/dev/null || true
    wait "$childPid" 2>/dev/null || true
  fi
  exit "$status"
}

runPost() {
  if [[ "$postPending" == true ]]; then
    log INFO "Running POST_CMD on $HOSTNAME"
    if ssh "${sshArgs[@]}" "$HOSTNAME" "$POST_CMD"; then
      log INFO "POST_CMD completed successfully"
      postPending=false
    else
      log ERROR "POST_CMD failed"
      return 1
    fi
  fi
}

cleanup() {
  local status=$?
  log INFO "Starting cleanup (exit status: $status)"
  trap - EXIT INT TERM HUP
  if [[ "$postPending" == true ]]; then
    log WARN "Running POST_CMD during cleanup"
    if ! runPost; then
      log ERROR "POST_CMD failed. Check the remote server immediately."
      status=1
    fi
  fi
  log INFO "Cleanup finished, exiting with status $status"
  exit "$status"
}

trap cleanup EXIT
trap 'onSignal 130' INT
trap 'onSignal 143' TERM
trap 'onSignal 129' HUP

if [[ -n ${POST_CMD:-} ]]; then 
  log DEBUG "POST_CMD is defined, setting postPending=true"
  postPending=true
fi

log INFO "Validating PATHS_BACKUP entries"
IFS='|' read -ra entries <<< "$PATHS_BACKUP"
for entry in "${entries[@]}"; do
  name=${entry%%,*}
  source=${entry#*,}
  [[ "$entry" == *,* && "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ && "$source" == /* ]] || { log ERROR "Invalid PATHS_BACKUP entry: $entry"; exit 1; }
done

runDir=$(mktemp -d /backups/run.XXXXXX)
log INFO "Created temporary directory: $runDir"
stamp=$(date +%Y-%m-%d-%H)

if [[ -n ${PRE_CMD:-} ]]; then 
  log INFO "Executing PRE_CMD on $HOSTNAME"
  run ssh "${sshArgs[@]}" "$HOSTNAME" "$PRE_CMD"
fi

for entry in "${entries[@]}"; do
  name=${entry%%,*}
  source=${entry#*,}
  log INFO "Starting rsync for $name (source: $source)"
  run rsync -a -s -e 'ssh -i /root/.ssh/id_backup -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3' -- "$HOSTNAME:${source%/}/" "$runDir/$name/"
done

log INFO "Triggering runPost after successful syncs"
runPost

log INFO "Changing directory to $runDir"
cd "$runDir"

for entry in "${entries[@]}"; do
  name=${entry%%,*}
  archive="$name-$stamp.zip"
  
  log INFO "Compressing $name into $archive"
  zipCmd=(zip -q -r -9 -y)
  if [[ -n ${ZIP_PASSWORD:-} ]]; then
    zipCmd+=(-P "$ZIP_PASSWORD")
  fi
  run "${zipCmd[@]}" "$archive" "$name"
  
  log INFO "Uploading $archive to mega"
  run rclone copyto "$archive" "mega:${MEGA_FOLDER%/}/$archive"
  
  log INFO "Cleaning up local files for $name"
  rm -rf -- "$name" "$archive"
done

log INFO "Removing temporary directory $runDir"
rmdir "$runDir"
log INFO "Backup process completed successfully"