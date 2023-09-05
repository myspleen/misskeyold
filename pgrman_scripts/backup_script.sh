#!/bin/bash

export TZ='Asia/Tokyo'

set -e
clean_up() {
    rm -f "$compressed_backup_file"
}
trap clean_up EXIT

BACKUP_DIR="/var/lib/postgresql/backup"
DB_DIR="/var/lib/postgresql/data"
ARCHIVE_DIR="/var/lib/postgresql/archive"
MODE="$1"
RSYNC_DEST_PATH="/var/lib/mbackup/"
LOG_FILE="/var/lib/postgresql/backup/backup.log"

timestamp=$(date +"%Y%m%d%H%M%S")
compressed_backup_file="${BACKUP_DIR}/backup_${MODE}_${timestamp}.tar.gz"

send_line_message() {
    message=$1
    curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${CHANNEL_ACCESS_TOKEN}" \
        -d '{
            "to": "'"${USER_ID}"'",
            "messages": [
                {
                    "type": "text",
                    "text": "'"$message"'"
                }
            ]
        }' https://api.line.me/v2/bot/message/push 2>&1
}

for dir in "$BACKUP_DIR" "$ARCHIVE_DIR"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chown postgres:postgres "$dir"
    fi
done

if [ ! -d "$RSYNC_DEST_PATH" ]; then
  mkdir -p "$RSYNC_DEST_PATH"
fi

export PGUSER=$POSTGRES_USER
export PGDATABASE=$POSTGRES_DB

if [ ! -d "$(dirname $LOG_FILE)" ]; then
  mkdir -p "$(dirname $LOG_FILE)"
fi

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') $1" >> $LOG_FILE
}

log "Backup script started."

REQUIRED_SPACE=52428800
AVAILABLE_SPACE=$(df "$BACKUP_DIR" | tail -1 | awk '{print $4}')

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    log "Error: Not enough disk space for backup."
    send_line_message "❌Misskey - Error: Not enough disk space for backup."
    exit 1
fi

/usr/lib/postgresql/15/bin/pg_rman backup --backup-mode=$MODE -B $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log "Error: pg_rman backup failed."
    send_line_message "❌Misskey - Error: pg_rman backup failed."
    exit 1
fi

/usr/lib/postgresql/15/bin/pg_rman validate -B $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log "Error: pg_rman validate failed."
    send_line_message "❌Misskey - Error: pg_rman validate failed."
    exit 1
fi

tar -cf - -C "$BACKUP_DIR" . | pigz > "$compressed_backup_file"
if [ $? -ne 0 ]; then
    log "Error: Backup compression using pigz failed."
    send_line_message "❌Misskey - Error: Backup compression using pigz failed."
    exit 1
fi

rsync -av "$compressed_backup_file" "$RSYNC_DEST_PATH" >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log "Error: Failed to rsync backup to $RSYNC_DEST_PATH."
    send_line_message "❌Misskey - Error: Failed to rsync backup to host OS."
    exit 1
fi

if [ ! -f "${RSYNC_DEST_PATH}/$(basename $compressed_backup_file)" ] || \
   [ $(stat -c%s "${RSYNC_DEST_PATH}/$(basename $compressed_backup_file)") -ne $(stat -c%s "$compressed_backup_file") ]; then
    log "Error: Rsynced file size does not match the original or file doesn't exist."
    send_line_message "❌Misskey - Error: Rsynced file size mismatch or file doesn't exist."
    exit 1
fi

rm -f "$compressed_backup_file"

log "Backup script completed."
