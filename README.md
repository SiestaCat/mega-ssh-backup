# MEGA Backup

Automated backup via SSH using `rsync`, maximum ZIP compression (`-9`), and upload to MEGA.

## 1. Environment variables

Create a `.env` file with the following variables:

| Variable | Description and example |
| --- | --- |
| `MEGA_USER` | MEGA user: `user@example.com` |
| `MEGA_PASS` | MEGA password: `your-password` |
| `MEGA_FOLDER` | Destination folder: `backups/server1` |
| `PRIVATE_KEY` | SSH private key in plain text, with newlines represented by `\n` |
| `HOSTNAME` | SSH server: `backup@192.168.1.100` |
| `PRE_CMD` | Pre-backup remote command: `echo Starting backup` |
| `POST_CMD` | Post-backup remote command: `echo Backup finished` |
| `PATHS_BACKUP` | Folders to copy: `data,/home/folder|images,/home/user/photos` |
| `HOURS` | Daily hours: `4,21` |

`PRE_CMD` and `POST_CMD` are optional and run via SSH on the remote server. Hours use the `Europe/Madrid` timezone.

Protect credentials with `chmod 600 .env`.

## 2. Docker build

```bash
docker build -t mega-backup .

```

## 3. Docker run

```bash
mkdir -p backups config ssh

docker run -d \
  --name mega-backup \
  --restart unless-stopped \
  --stop-timeout 120 \
  --env-file .env \
  -v "$PWD/backups:/backups" \
  -v "$PWD/config:/config" \
  -v "$PWD/ssh:/root/.ssh" \
  mega-backup

```

Check logs:

```bash
docker logs -f mega-backup

```

## 4. Manual backup with running container

Immediately run a backup without waiting for the scheduled hours:

```bash
docker exec mega-backup /usr/local/bin/backup.sh

```

## 5. Manual backup without running container

Create a temporary container, configure SSH and rclone, run the backup, and exit automatically:

```bash
docker run --rm --stop-timeout 120 \
  --env-file .env \
  -v "$PWD/backups:/backups" \
  -v "$PWD/config:/config" \
  -v "$PWD/ssh:/root/.ssh" \
  mega-backup backup

```

Requires the `backup` mode in `start.sh`.

## 6. Result

Each folder generates an independent ZIP:

```text
backups/server1/
├── data-2026-10-26-21.zip
└── images-2026-10-26-21.zip
```

`PRE_CMD` runs before the download and `POST_CMD` after, even in case of manageable errors. Local files are deleted only after successfully uploading to MEGA.

**Important:** avoid running manual and scheduled backups simultaneously.

## 7. Convert private key to a single line to put it in env var

```bash
awk '{printf "%s\\n", $0}' id_rsa
```