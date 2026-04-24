#!/bin/sh
set -eu

# NFS 서버 서비스를 멈추고 이 실습에서 만든 export 설정만 제거한다.
# export root에 저장된 백업 파일은 삭제하지 않는다.
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/nfs-server/nfs-server.env"}

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root." >&2
    exit 1
fi

# OS에 따라 NFS systemd 서비스명이 다르다.
if command -v dnf >/dev/null 2>&1; then
    nfs_service=nfs-server
elif command -v apt-get >/dev/null 2>&1; then
    nfs_service=nfs-kernel-server
else
    echo "Unsupported package manager. Expected dnf or apt-get." >&2
    exit 1
fi

systemctl stop "$nfs_service"

# 이 repo가 만든 export 파일만 제거한다.
if [ -f /etc/exports.d/ndjson-todo.exports ]; then
    rm -f /etc/exports.d/ndjson-todo.exports
    exportfs -rav
fi
