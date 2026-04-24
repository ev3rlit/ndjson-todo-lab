#!/bin/sh
set -eu

# NFS 서버 프로세스 상태와 현재 export 목록을 함께 확인한다.
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

# 서비스 상태 다음에 exportfs 결과를 보여 주면 server/client 설정 불일치를 찾기 쉽다.
systemctl status "$nfs_service" --no-pager
printf '\n'
exportfs -v
