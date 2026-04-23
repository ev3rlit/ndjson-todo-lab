#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm1/vm1.env"}

. "$ROOT_DIR/scripts/lib/common.sh"
load_env_file "$ENV_FILE"
require_root

NFS_SERVER_HOST=${NFS_SERVER_HOST:-}
NFS_EXPORT_ROOT=${NFS_EXPORT_ROOT:-/srv/nfs/ndjson-todo}
NFS_MOUNT_SOURCE=${NFS_MOUNT_SOURCE:-/}
NFS_MOUNT_DIR=${NFS_MOUNT_DIR:-/mnt/ndjson-todo-nfs}
NFS_MOUNT_OPTIONS=${NFS_MOUNT_OPTIONS:-defaults,_netdev,nofail,vers=4.2}

if [ -z "$NFS_SERVER_HOST" ]; then
    echo "Set NFS_SERVER_HOST in $ENV_FILE before mounting." >&2
    exit 1
fi

mkdir -p "$NFS_MOUNT_DIR"

fstab_line="$NFS_SERVER_HOST:$NFS_MOUNT_SOURCE $NFS_MOUNT_DIR nfs4 $NFS_MOUNT_OPTIONS 0 0"
ensure_line_in_file "$fstab_line" /etc/fstab
systemctl daemon-reload

if ! mountpoint -q "$NFS_MOUNT_DIR"; then
    mount "$NFS_MOUNT_DIR"
fi

mountpoint "$NFS_MOUNT_DIR" >/dev/null
