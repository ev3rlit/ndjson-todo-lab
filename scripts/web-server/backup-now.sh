#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/web-server/web-server.env"}

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

TODO_DATA_DIR=${TODO_DATA_DIR:-/srv/ndjson-todo/data}
TODO_LOG_DIR=${TODO_LOG_DIR:-/srv/ndjson-todo/logs}
BACKUP_TARGET_DIR=${BACKUP_TARGET_DIR:-/mnt/ndjson-todo-nfs/backups}

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log_info() {
    printf '{"ts":"%s","level":"INFO","msg":"%s","data_source":"%s","logs_source":"%s","target":"%s"}\n' \
        "$(timestamp)" "$1" "$TODO_DATA_DIR" "$TODO_LOG_DIR" "$BACKUP_TARGET_DIR"
}

log_error() {
    printf '{"ts":"%s","level":"ERROR","msg":"%s","data_source":"%s","logs_source":"%s","target":"%s"}\n' \
        "$(timestamp)" "$1" "$TODO_DATA_DIR" "$TODO_LOG_DIR" "$BACKUP_TARGET_DIR" >&2
}

mkdir -p "$BACKUP_TARGET_DIR/data" "$BACKUP_TARGET_DIR/logs"

if ! mountpoint -q "$(dirname "$BACKUP_TARGET_DIR")"; then
    log_error "nfs mount is not active"
    exit 1
fi

log_info "backup started"

if ! rsync -a --delete "$TODO_DATA_DIR"/ "$BACKUP_TARGET_DIR/data/"; then
    log_error "data backup failed"
    exit 1
fi

if ! rsync -a --delete "$TODO_LOG_DIR"/ "$BACKUP_TARGET_DIR/logs/"; then
    log_error "logs backup failed"
    exit 1
fi

log_info "backup finished"
