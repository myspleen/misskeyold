#!/bin/bash

export TZ='Asia/Tokyo'

BASE_BACKUP_DIR="/var/lib/postgresql/backup"
DATE=$(date +"%Y-%m-%d_%H%M%S")
MODE="$1" # "full" or "incremental"
BACKUP_SUBDIR="${BASE_BACKUP_DIR}/${DATE}_$MODE"
ARCHIVE_DIR="/var/lib/postgresql/archive"
RCLONE_REMOTE="onedrive"
RCLONE_PATH="server/backup/misskey"
LOG_FILE="/var/lib/postgresql/backup/backup.log"

# rcloneの設定ファイルの場所を指定
export RCLONE_CONFIG="/root/.config/rclone/rclone.conf"
export PGUSER=$POSTGRES_USER
export PGDATABASE=$POSTGRES_DB

# Line通知スクリプト
send_line_message() {
    message=$1
    response=$(curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${CHANNEL_ACCESS_TOKEN}" \
        -d '{
            "to": "'"${USER_ID}"'",
            "messages": [
                {
                    "type": "text",
                    "text": "'"$message"'"
                }
            ]
        }' https://api.line.me/v2/bot/message/push 2>&1)
}

# Ensure backup and archive directories exist
for dir in "$BACKUP_SUBDIR" "$ARCHIVE_DIR"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chown postgres:postgres "$dir"
    fi
done

# Ensure log directory exists
if [ ! -d "$(dirname $LOG_FILE)" ]; then
  mkdir -p "$(dirname $LOG_FILE)"
fi

# ログを取る
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') $1" >> $LOG_FILE
}

log "Backup script started."

# pg_rmanバックアップを実行
/usr/lib/postgresql/15/bin/pg_rman backup --backup-mode=$MODE -B $BASE_BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log "Error: pg_rman backup failed."
    send_line_message "❌Misskey - Error: pg_rman backup failed."
    exit 1
fi

# バックアップを検証
/usr/lib/postgresql/15/bin/pg_rman validate -B $BACKUP_SUBDIR -D $DB_DIR -A $ARCHIVE_DIR >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log "Error: pg_rman validate failed."
    send_line_message "❌Misskey - Error: pg_rman validate failed."
    exit 1
fi

# 圧縮
COMPRESSED_BACKUP="${BACKUP_SUBDIR}.tar.gz"
log "Compressing the backup directory."
tar cf - $BACKUP_SUBDIR | pigz > $COMPRESSED_BACKUP
if [ $? -ne 0 ]; then
    log "Error: Compression using pigz failed."
    send_line_message "❌Misskey - Error: Compression using pigz failed."
    exit 1
fi

# rcloneでOneDriveにアップロード
rclone copy $COMPRESSED_BACKUP $RCLONE_REMOTE:$RCLONE_PATH >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log "Error: rclone sync failed."
    send_line_message "❌Misskey - Error: rclone sync failed."
    exit 1
fi

log "Backup script completed."

if [ "$MODE" == "full" ]; then
    send_line_message "✅Misskey - Full backup completed."
else
    send_line_message "✅Misskey - Incremental backup completed."
fi

# Cleanup 
rm -rf "$BACKUP_SUBDIR"
