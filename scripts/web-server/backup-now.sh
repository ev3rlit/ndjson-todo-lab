#!/bin/sh
set -eu

# 웹서버 환경의 data/log 디렉터리를 NFS 백업 경로로 복사한다.
# cron에서 호출되기도 하고, 장애 확인을 위해 수동으로 실행할 수도 있다.
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
    # 백업 로그는 다른 앱 로그와 섞어 보기 쉽게 UTC JSON 라인으로 남긴다.
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

# NFS가 빠진 상태에서 로컬 디렉터리에 백업하는 실수를 막는다.
if ! mountpoint -q "$(dirname "$BACKUP_TARGET_DIR")"; then
    log_error "nfs mount is not active"
    exit 1
fi

log_info "backup started"

# --delete를 사용해 백업 대상이 현재 data/log 상태와 같아지게 맞춘다.
if ! rsync -a --delete "$TODO_DATA_DIR"/ "$BACKUP_TARGET_DIR/data/"; then
    log_error "data backup failed"
    exit 1
fi

if ! rsync -a --delete "$TODO_LOG_DIR"/ "$BACKUP_TARGET_DIR/logs/"; then
    log_error "logs backup failed"
    exit 1
fi

log_info "backup finished"
