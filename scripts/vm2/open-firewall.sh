#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm2/vm2.env"}

. "$ROOT_DIR/scripts/lib/common.sh"
load_env_file "$ENV_FILE"
require_root

NFS_CLIENT_CIDR=${NFS_CLIENT_CIDR:-192.168.56.0/24}

if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=nfs
    firewall-cmd --permanent --add-service=mountd
    firewall-cmd --permanent --add-service=rpc-bind
    firewall-cmd --reload
    exit 0
fi

if command -v ufw >/dev/null 2>&1; then
    ufw allow from "$NFS_CLIENT_CIDR" to any port 2049 proto tcp
    ufw allow from "$NFS_CLIENT_CIDR" to any port 111 proto tcp
    ufw allow from "$NFS_CLIENT_CIDR" to any port 111 proto udp
    exit 0
fi

echo "No supported firewall manager detected. Open NFS ports manually if needed." >&2
