#!/bin/bash
export TZ='Asia/Tokyo'

BACKUP_DIR="/var/lib/postgresql/backup"
DB_DIR="/var/lib/postgresql/data"
ARCHIVE_DIR="/var/lib/postgresql/archive"
MODE="$1"
RCLONE_REMOTE="onedrive"  # rcloneリモート名
RCLONE_PATH="server/backup/misskey"  # 保存先のOneDriveフォルダのパス
LOG_FILE="/var/lib/postgresql/backup/backup.log"
# Linebotへ通知
CHANNEL_ACCESS_TOKEN=${CHANNEL_ACCESS_TOKEN}
CHANNEL_SECRET=${CHANNEL_SECRET}
USER_ID=${USER_ID}

# Line通知スクリプト
send_line_message() {
    message=$1
    curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $CHANNEL_ACCESS_TOKEN" \
        -d '{
            "to": "'$USER_ID'",
            "messages": [
                {
                    "type": "text",
                    "text": "'$message'"
                }
            ]
        }' https://api.line.me/v2/bot/message/push
}

#アーカイブディレクトリの作成
if [ ! -d "/var/lib/postgresql/archive" ]; then
  mkdir -p /var/lib/postgresql/archive/
  chown postgres:postgres /var/lib/postgresql/archive/
fi
#バックアップディレクトリの作成
if [ ! -d "/var/lib/postgresql/backup" ]; then
  mkdir -p /var/lib/postgresql/backup/
  chown postgres:postgres /var/lib/postgresql/backup/
fi

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
send_line_message "Misskey -  Backup script started."

# pg_rmanバックアップを実行
/usr/lib/postgresql/15/bin/pg_rman backup --backup-mode=$MODE -B $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
  log "Error: pg_rman backup failed."
  send_line_message "Misskey - Error: pg_rman backup failed."
  exit 1
fi
log "pg_rman backup --backup-mode=$MODE -b $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR finished."

# バックアップを検証
/usr/lib/postgresql/15/bin/pg_rman validate -B $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
  log "Error: pg_rman validate failed."
  exit 1
fi
log "/usr/lib/postgresql/15/bin/pg_rman validate -b $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR finished."

# rcloneでOneDriveにアップロード
rclone sync $BACKUP_DIR $RCLONE_REMOTE:$RCLONE_PATH >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
  log "Error: rclone sync failed."
  exit 1
fi
log "rclone sync $BACKUP_DIR $RCLONE_REMOTE:$RCLONE_PATH finished."

log "Backup script completed."

if [ "$MODE" == "full" ]; then
    log "Full backup script completed."
    send_line_message "Misskey - Full backup script completed."
else
    log "Incremental backup script completed."
    send_line_message "Misskey - Incremental backup script completed."
fi
