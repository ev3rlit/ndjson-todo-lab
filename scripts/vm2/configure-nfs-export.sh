#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm2/vm2.env"}

. "$ROOT_DIR/scripts/lib/common.sh"
load_env_file "$ENV_FILE"
require_root

NFS_EXPORT_ROOT=${NFS_EXPORT_ROOT:-/srv/nfs/ndjson-todo}
NFS_CLIENT_CIDR=${NFS_CLIENT_CIDR:-192.168.56.0/24}
NFS_EXPORT_OPTIONS=${NFS_EXPORT_OPTIONS:-rw,sync,no_subtree_check,no_root_squash}

case ",$NFS_EXPORT_OPTIONS," in
    *,fsid=0,*)
        ;;
    *)
        NFS_EXPORT_OPTIONS="${NFS_EXPORT_OPTIONS},fsid=0"
        ;;
esac

mkdir -p "$NFS_EXPORT_ROOT" "$NFS_EXPORT_ROOT/backups/data" "$NFS_EXPORT_ROOT/backups/logs"
chmod 0777 "$NFS_EXPORT_ROOT" "$NFS_EXPORT_ROOT/backups" "$NFS_EXPORT_ROOT/backups/data" "$NFS_EXPORT_ROOT/backups/logs"

cat > /etc/exports.d/ndjson-todo.exports <<EOF
$NFS_EXPORT_ROOT $NFS_CLIENT_CIDR($NFS_EXPORT_OPTIONS)
EOF

exportfs -rav

service_name=$(nfs_server_service)
systemctl restart "$service_name"
