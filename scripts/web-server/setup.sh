#!/bin/sh
set -eu

# 웹서버 실행 환경을 한 번에 준비한다.
# 이 스크립트는 NFS 백업 대상 mount, 서비스 디렉터리 준비, 백업 cron 등록,
# Podman Compose 기반 웹 컨테이너 기동까지 담당한다.
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/web-server/web-server.env"}
EXAMPLE_ENV_FILE="$ROOT_DIR/scripts/web-server/web-server.env.example"

# cron에도 같은 ENV_FILE 경로를 넘기기 위해 상대 경로를 절대 경로로 바꾼다.
case "$ENV_FILE" in
    /*)
        ;;
    *)
        ENV_FILE=$(CDPATH= cd -- "$(dirname -- "$ENV_FILE")" && pwd)/$(basename -- "$ENV_FILE")
        ;;
esac

export ENV_FILE

if [ ! -f "$EXAMPLE_ENV_FILE" ]; then
    echo "Missing example env file: $EXAMPLE_ENV_FILE" >&2
    exit 1
fi

# setup은 항상 example을 기준으로 env 파일을 다시 만든다.
# 실습 환경을 반복 실행해도 같은 설정에서 출발하게 하기 위함이다.
cp -f "$EXAMPLE_ENV_FILE" "$ENV_FILE"

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root." >&2
    exit 1
fi

CONTAINER_BIND_OPTIONS=${CONTAINER_BIND_OPTIONS:-:Z}
NGINX_CONFIG_BIND_OPTIONS=${NGINX_CONFIG_BIND_OPTIONS:-:ro,Z}
TODO_DATA_DIR=${TODO_DATA_DIR:-/srv/ndjson-todo/data}
TODO_LOG_DIR=${TODO_LOG_DIR:-/srv/ndjson-todo/logs}
NGINX_LOG_DIR=${NGINX_LOG_DIR:-/srv/ndjson-todo/logs/nginx}
NFS_SERVER_HOST=${NFS_SERVER_HOST:-}
NFS_MOUNT_SOURCE=${NFS_MOUNT_SOURCE:-/}
NFS_MOUNT_DIR=${NFS_MOUNT_DIR:-/mnt/ndjson-todo-nfs}
NFS_MOUNT_OPTIONS=${NFS_MOUNT_OPTIONS:-defaults,_netdev,nofail,vers=4.2}
BACKUP_CRON_SCHEDULE=${BACKUP_CRON_SCHEDULE:-*/5 * * * *}
BACKUP_LOG_FILE=${BACKUP_LOG_FILE:-/var/log/ndjson-todo-backup.log}
BACKUP_SCRIPT="$ROOT_DIR/scripts/web-server/backup-now.sh"

install_runtime_packages() {
    # 웹서버 VM에는 NFS client, 백업 도구, rootless 컨테이너 런타임이 필요하다.
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y nfs-utils rsync podman podman-compose
        return
    fi

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y nfs-common rsync podman podman-compose
        return
    fi

    echo "Unsupported package manager. Expected dnf or apt-get." >&2
    exit 1
}

replace_fstab_entry() {
    # 같은 mount point가 이미 있으면 덧붙이지 않고 교체한다.
    # setup을 여러 번 실행해도 /etc/fstab이 중복으로 늘어나지 않게 한다.
    mount_dir=$1
    new_line=$2
    target_file=$3

    tmp_file=$(mktemp)
    if [ -f "$target_file" ]; then
        awk -v mount_dir="$mount_dir" '
            $0 ~ /^[[:space:]]*#/ { print; next }
            NF < 2 { print; next }
            $2 != mount_dir { print }
        ' "$target_file" > "$tmp_file"
    fi

    printf '%s\n' "$new_line" >> "$tmp_file"
    cat "$tmp_file" > "$target_file"
    rm -f "$tmp_file"
}

mount_nfs_backup_target() {
    # NFS 서버는 fsid=0으로 export하므로 client는 보통 "host:/" 형태로 mount한다.
    if [ -z "$NFS_SERVER_HOST" ]; then
        echo "Set NFS_SERVER_HOST in $ENV_FILE before mounting." >&2
        exit 1
    fi

    mkdir -p "$NFS_MOUNT_DIR"

    fstab_line="$NFS_SERVER_HOST:$NFS_MOUNT_SOURCE $NFS_MOUNT_DIR nfs4 $NFS_MOUNT_OPTIONS 0 0"
    replace_fstab_entry "$NFS_MOUNT_DIR" "$fstab_line" /etc/fstab
    systemctl daemon-reload

    if ! mountpoint -q "$NFS_MOUNT_DIR"; then
        mount "$NFS_MOUNT_DIR"
    fi

    mountpoint "$NFS_MOUNT_DIR" >/dev/null
}

prepare_host_paths() {
    # rootless 컨테이너가 직접 쓰는 data/log 경로다.
    # 실습에서는 권한 문제를 줄이기 위해 넓게 열어 둔다.
    mkdir -p "$TODO_DATA_DIR" "$TODO_LOG_DIR" "$NGINX_LOG_DIR"
    chmod 0777 "$TODO_DATA_DIR" "$TODO_LOG_DIR" "$NGINX_LOG_DIR"
}

install_backup_cron() {
    # 웹서버 환경의 data/log를 NFS mount 아래 backups로 주기 복사한다.
    touch "$BACKUP_LOG_FILE"
    chmod 0644 "$BACKUP_LOG_FILE"

    cat > /etc/cron.d/ndjson-todo-backup <<EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV_FILE=$ENV_FILE

$BACKUP_CRON_SCHEDULE root $BACKUP_SCRIPT >> $BACKUP_LOG_FILE 2>&1
EOF

    chmod 0644 /etc/cron.d/ndjson-todo-backup
}

start_web_stack() {
    # 이 환경은 docker compose가 아니라 podman-compose를 명시적으로 사용한다.
    if ! command -v podman-compose >/dev/null 2>&1; then
        echo "podman-compose is required but not installed." >&2
        exit 1
    fi

    # bind mount 대상이 없으면 컨테이너는 올라가도 바로 권한/경로 오류가 난다.
    for required_dir in "$TODO_DATA_DIR" "$TODO_LOG_DIR" "$NGINX_LOG_DIR"; do
        if [ ! -d "$required_dir" ]; then
            echo "Missing host path: $required_dir" >&2
            echo "Run sudo scripts/web-server/setup.sh first." >&2
            exit 1
        fi
    done

    cd "$ROOT_DIR"
    podman-compose -f docker-compose.yml -f docker-compose.web-server.yml up -d --build web1 web2 web3 lb
}

echo "[web-server] install runtime packages"
install_runtime_packages

echo "[web-server] mount nfs backup target"
mount_nfs_backup_target

echo "[web-server] prepare service directories"
prepare_host_paths

echo "[web-server] install backup cron"
install_backup_cron

echo "[web-server] start load balancer and web containers"
start_web_stack

echo "[web-server] completed"
echo "[web-server] use scripts/web-server/status.sh to inspect services"
