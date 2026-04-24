#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/nfs-server/nfs-server.env"}
EXAMPLE_ENV_FILE="$ROOT_DIR/scripts/nfs-server/nfs-server.env.example"

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

if command -v dnf >/dev/null 2>&1; then
    nfs_package=nfs-utils
    nfs_service=nfs-server
elif command -v apt-get >/dev/null 2>&1; then
    nfs_package=nfs-kernel-server
    nfs_service=nfs-kernel-server
else
    echo "Unsupported package manager. Expected dnf or apt-get." >&2
    exit 1
fi

install_nfs_server() {
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y "$nfs_package"
        systemctl enable --now "$nfs_service"
        return
    fi

    apt-get update
    apt-get install -y "$nfs_package"
    systemctl enable --now "$nfs_service"
}

configure_nfs_export() {
    mkdir -p "$NFS_EXPORT_ROOT" "$NFS_EXPORT_ROOT/backups/data" "$NFS_EXPORT_ROOT/backups/logs"
    chmod 0777 "$NFS_EXPORT_ROOT" "$NFS_EXPORT_ROOT/backups" "$NFS_EXPORT_ROOT/backups/data" "$NFS_EXPORT_ROOT/backups/logs"

    cat > /etc/exports.d/ndjson-todo.exports <<EOF
$NFS_EXPORT_ROOT $NFS_CLIENT_CIDR($NFS_EXPORT_OPTIONS)
EOF

    exportfs -rav
    systemctl restart "$nfs_service"
}

open_nfs_firewall() {
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-service=nfs
        firewall-cmd --permanent --add-service=mountd
        firewall-cmd --permanent --add-service=rpc-bind
        firewall-cmd --reload
        return
    fi

    if command -v ufw >/dev/null 2>&1; then
        ufw allow from "$NFS_CLIENT_CIDR" to any port 2049 proto tcp
        ufw allow from "$NFS_CLIENT_CIDR" to any port 111 proto tcp
        ufw allow from "$NFS_CLIENT_CIDR" to any port 111 proto udp
        return
    fi

    echo "No supported firewall manager detected. Open NFS ports manually if needed." >&2
}

echo "[nfs-server] install and enable nfs server"
install_nfs_server

echo "[nfs-server] configure nfs export"
configure_nfs_export

echo "[nfs-server] open firewall for nfs"
open_nfs_firewall

echo "[nfs-server] completed"
echo "[nfs-server] use scripts/nfs-server/status.sh to inspect nfs status"
