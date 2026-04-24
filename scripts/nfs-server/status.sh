#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/nfs-server/nfs-server.env"}

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

if command -v dnf >/dev/null 2>&1; then
    nfs_service=nfs-server
elif command -v apt-get >/dev/null 2>&1; then
    nfs_service=nfs-kernel-server
else
    echo "Unsupported package manager. Expected dnf or apt-get." >&2
    exit 1
fi

systemctl status "$nfs_service" --no-pager
printf '\n'
exportfs -v
