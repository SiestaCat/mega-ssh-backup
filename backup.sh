
#!/usr/bin/env bash
set -euo pipefail
umask 077

sshArgs=(-i /root/.ssh/id_backup -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
postPending=false
childPid=''

run() {
  "$@" &
  childPid=$!
  local status=0
  wait "$childPid" || status=$?
  childPid=''
  return "$status"
}

onSignal() {
  local status=$1
  trap - INT TERM HUP
  if [[ -n "$childPid" ]]; then
    kill -TERM "$childPid" 2>/dev/null || true
    wait "$childPid" 2>/dev/null || true
  fi
  exit "$status"
}

runPost() {
  if [[ "$postPending" == true ]]; then
    if ssh "${sshArgs[@]}" "$HOSTNAME" "$POST_CMD"; then
      postPending=false
    else
      return 1
    fi
  fi
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM HUP
  if [[ "$postPending" == true ]]; then
    echo 'Running POST_CMD during cleanup' >&2
    if ! runPost; then
      echo 'ERROR: POST_CMD failed. Check the remote server immediately.' >&2
      status=1
    fi
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'onSignal 130' INT
trap 'onSignal 143' TERM
trap 'onSignal 129' HUP

if [[ -n ${POST_CMD:-} ]]; then postPending=true; fi

IFS='|' read -ra entries <<< "$PATHS_BACKUP"
for entry in "${entries[@]}"; do
  name=${entry%%,*}
  source=${entry#*,}
  [[ "$entry