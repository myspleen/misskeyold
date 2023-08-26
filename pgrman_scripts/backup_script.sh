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
RCLONE_REMOTE="onedrive"  # rcloneリモート名
RCLONE_BASE_PATH="server/backup/misskey"  # 保存先の基本のOneDriveフォルダのパス
rclone_dest_path="$RCLONE_BASE_PATH"
LOG_FILE="/var/lib/postgresql/backup/backup.log"

timestamp=$(date +"%Y%m%d%H%M%S")
compressed_backup_file="${BACKUP_DIR}/backup_${MODE}_${timestamp}.tar.gz"

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

# バックアップ実行前に容量を確認
REQUIRED_SPACE=52428800  # 50GB (Change this based on your needs)
AVAILABLE_SPACE=$(df "$BACKUP_DIR" | tail -1 | awk '{print $4}')

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    log "Error: Not enough disk space for backup."
    send_line_message "❌Misskey - Error: Not enough disk space for backup."
    exit 1
fi

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

# バックアップをpigzで圧縮
tar -cf - -C "$BACKUP_DIR" . | pigz > "$compressed_backup_file"
if [ $? -ne 0 ]; then
    log "Error: Backup compression using pigz failed."
    send_line_message "❌Misskey - Error: Backup compression using pigz failed."
    exit 1
fi
log "Backup compression using pigz completed."

# rcloneでOneDriveにアップロード
if rclone copy "$compressed_backup_file" "$RCLONE_REMOTE:$rclone_dest_path" >> $LOG_FILE 2>&1; then
    log "File uploaded successfully to OneDrive."
else
    log "Error: Failed to upload file to OneDrive."
    send_line_message "❌Misskey - Error: Failed to upload backup to OneDrive."
    exit 1
fi

# rcloneでアップロードを確認
uploaded_file_size=$(rclone ls "$RCLONE_REMOTE:$rclone_dest_path" | grep "$(basename $compressed_backup_file)" | awk '{print $1}')

if [ "$uploaded_file_size" -ne $(stat -c%s "$compressed_backup_file") ]; then
    log "Error: Uploaded file size does not match the original. Upload might have failed."
    send_line_message "❌Misskey - Error: Uploaded file size mismatch."
    exit 1
fi

# 圧縮ファイルを削除
rm -f "$compressed_backup_file"
if [ $? -ne 0 ]; then
    log "Error: Failed to delete compressed backup file."
    send_line_message "❌Misskey - Error: Failed to delete compressed backup file."
    exit 1
fi
log "Temporary compressed backup file $compressed_backup_file deleted."


log "Backup script completed."

if [ "$MODE" == "full" ]; then
    send_line_message "✅Misskey - Full backup completed."
else
    send_line_message "✅Misskey - Incremental backup completed."
fi
