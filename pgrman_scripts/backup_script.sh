#!/bin/bash

export TZ='Asia/Tokyo'

BACKUP_DIR="/var/lib/postgresql/backup"
DB_DIR="/var/lib/postgresql/data"
ARCHIVE_DIR="/var/lib/postgresql/archive"
MODE="$1"
RCLONE_REMOTE="onedrive"  # rcloneリモート名
RCLONE_PATH="server/backup/misskey"  # 保存先のOneDriveフォルダのパス
LOG_FILE="/var/lib/postgresql/backup/backup.log"

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

for dir in "$BACKUP_DIR" "$ARCHIVE_DIR"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chown postgres:postgres "$dir"
    fi
done

# rcloneの設定ファイルの場所を指定
export RCLONE_CONFIG="/root/.config/rclone/rclone.conf"
export PGUSER=$POSTGRES_USER
export PGDATABASE=$POSTGRES_DB

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
/usr/lib/postgresql/15/bin/pg_rman backup --backup-mode=$MODE -B $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log "Error: pg_rman backup failed."
    send_line_message "❌Misskey - Error: pg_rman backup failed."
    exit 1
fi
log "pg_rman backup --backup-mode=$MODE -b $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR finished."

# バックアップを検証
/usr/lib/postgresql/15/bin/pg_rman validate -B $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log "Error: pg_rman validate failed."
    send_line_message "❌Misskey - Error: pg_rman validate failed."
    exit 1
fi
log "/usr/lib/postgresql/15/bin/pg_rman validate -b $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR finished."

# rcloneでOneDriveにアップロード
rclone sync $BACKUP_DIR $RCLONE_REMOTE:$RCLONE_PATH >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log "Error: rclone sync failed."
    send_line_message "❌Misskey - Error: rclone sync failed."
    exit 1
fi
log "rclone sync $BACKUP_DIR $RCLONE_REMOTE:$RCLONE_PATH finished."

log "Backup script completed."

if [ "$MODE" == "full" ]; then
    send_line_notification "✅Misskey - Full backup completed."
else
    send_line_notification "✅Misskey - Incremental backup completed."
fi
