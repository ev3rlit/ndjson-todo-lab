#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm1/vm1.env"}

. "$ROOT_DIR/scripts/lib/common.sh"
load_env_file "$ENV_FILE"
require_root

BACKUP_CRON_SCHEDULE=${BACKUP_CRON_SCHEDULE:-*/5 * * * *}
BACKUP_LOG_FILE=${BACKUP_LOG_FILE:-/var/log/ndjson-todo-backup.log}
BACKUP_SCRIPT="$ROOT_DIR/scripts/vm1/backup-now.sh"

touch "$BACKUP_LOG_FILE"
chmod 0644 "$BACKUP_LOG_FILE"

cat > /etc/cron.d/ndjson-todo-backup <<EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV_FILE=$ENV_FILE

$BACKUP_CRON_SCHEDULE root $BACKUP_SCRIPT >> $BACKUP_LOG_FILE 2>&1
EOF

chmod 0644 /etc/cron.d/ndjson-todo-backup
