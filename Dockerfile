FROM rclone/rclone:latest

RUN apk add --no-cache bash openssh-client rsync zip

COPY start.sh backup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

ENTRYPOINT ["/usr/local/bin/start.sh"]