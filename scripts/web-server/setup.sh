#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/web-server/web-server.env"}
EXAMPLE_ENV_FILE="$ROOT_DIR/scripts/web-server/web-server.env.example"

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
    mkdir -p "$TODO_DATA_DIR" "$TODO_LOG_DIR" "$NGINX_LOG_DIR"
    chmod 0777 "$TODO_DATA_DIR" "$TODO_LOG_DIR" "$NGINX_LOG_DIR"
}

install_backup_cron() {
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
    if ! command -v podman-compose >/dev/null 2>&1; then
        echo "podman-compose is required but not installed." >&2
        exit 1
    fi

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
