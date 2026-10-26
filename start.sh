#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${MEGA_USER:?Missing MEGA_USER}"
: "${MEGA_PASS:?Missing MEGA_PASS}"
: "${MEGA_FOLDER:?Missing MEGA_FOLDER}"
: "${PRIVATE_KEY:?Missing PRIVATE_KEY}"
: "${HOSTNAME:?Missing HOSTNAME}"
: "${PATHS_BACKUP:?Missing PATHS_BACKUP}"
: "${HOURS:?Missing HOURS}"

[[ "$HOSTNAME" == *@* ]] || { echo 'HOSTNAME must be user@host' >&2; exit 1; }

key="${PRIVATE_KEY//$'\r'/}"
key="${key//\\r/}"
key="${key//\\n/$'\n'}"
key="${key#"${key%%[![:space:]]*}"}"
key="${key%"${key##*[![:space:]]}"}"
if [[ "$key" == \"*\" || "$key" == \'*\' ]]; then key="${key:1:-1}"; fi

mkdir -p /root/.ssh /backups
chmod 700 /root/.ssh
printf '%s\n' "$key" > /root/.ssh/id_backup
chmod 600 /root/.ssh/id_backup
ssh-keygen -y -P '' -f /root/.ssh/id_backup >/dev/null 2>&1 || { echo 'Invalid or encrypted PRIVATE_KEY' >&2; exit 1; }
unset key PRIVATE_KEY

rclone config create mega mega user "$MEGA_USER" pass "$MEGA_PASS" --obscure --no-output

IFS=, read -ra hours <<< "$HOURS"
validHours=,
for hour in "${hours[@]}"; do
  [[ "$hour" =~ ^(0?[0-9]|1[0-9]|2[0-3])$ ]] || { echo "Invalid hour: $hour" >&2; exit 1; }
  validHours+="$((10#$hour)),"
done

backupPid=''
shutdown() {
  trap - INT TERM HUP
  if [[ -n "$backupPid" ]]; then
    kill -TERM "$backupPid" 2>/dev/null || true
    wait "$backupPid" || true
  fi
  exit 143
}
trap shutdown INT TERM HUP

lastRun=''
while true; do
  hour=$(date +%H)
  slot=$(date +%Y-%m-%d-%H)
  if [[ $(date +%M) == 00 && "$validHours" == *,"$((10#$hour))",* && "$slot" != "$lastRun" ]]; then
    lastRun="$slot"
    /usr/local/bin/backup.sh &
    backupPid=$!
    if ! wait "$backupPid"; then echo "Backup failed: $slot" >&2; fi
    backupPid=''
  fi
  sleep 20
done