#!/bin/bash

BACKUP_DIR="/var/lib/postgresql/backup"
DB_DIR="/var/lib/postgresql/data"
ARCHIVE_DIR="/var/lib/postgresql/archive"
MODE="$1"
RCLONE_REMOTE="onedrive"  # rcloneリモート名
RCLONE_PATH="server/backup/misskey"  # 保存先のOneDriveフォルダのパス

# rcloneの設定ファイルの場所を指定
export RCLONE_CONFIG="/root/.config/rclone/rclone.conf"

# pg_rmanバックアップを実行
/usr/pgsql-15/bin/pg_rman backup --backup-mode=$MODE -b $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR

# バックアップを検証
/usr/pgsql-15/bin/pg_rman validate -b $BACKUP_DIR -D $DB_DIR -A $ARCHIVE_DIR

# rcloneでOneDriveにアップロード
rclone sync $BACKUP_DIR $RCLONE_REMOTE:$RCLONE_PATH
