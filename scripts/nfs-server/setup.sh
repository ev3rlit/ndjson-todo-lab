#!/bin/sh
set -eu

# NFS 백업 서버 환경을 한 번에 준비한다.
# 이 스크립트는 NFS 패키지 설치, export 디렉터리 생성, export 설정,
# 방화벽 오픈까지 담당한다.
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/nfs-server/nfs-server.env"}
EXAMPLE_ENV_FILE="$ROOT_DIR/scripts/nfs-server/nfs-server.env.example"

# 로그와 후속 명령에서 같은 env 경로를 쓰도록 상대 경로를 절대 경로로 바꾼다.
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

NFS_EXPORT_ROOT=${NFS_EXPORT_ROOT:-/srv/nfs/ndjson-todo}
NFS_CLIENT_CIDR=${NFS_CLIENT_CIDR:-192.168.56.0/24}
NFS_EXPORT_OPTIONS=${NFS_EXPORT_OPTIONS:-rw,sync,no_subtree_check,no_root_squash}

# NFSv4 root export로 쓰기 위해 fsid=0을 항상 포함시킨다.
case ",$NFS_EXPORT_OPTIONS," in
    *,fsid=0,*)
        ;;
    *)
        NFS_EXPORT_OPTIONS="${NFS_EXPORT_OPTIONS},fsid=0"
        ;;
esac

# 배포 대상 OS에 따라 패키지명과 systemd 서비스명이 다르다.
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
    # NFS 서버 패키지를 설치하고 부팅 후에도 자동 시작되도록 등록한다.
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
    # 백업 데이터가 들어갈 export root와 하위 디렉터리를 만든다.
    # 실습에서는 client 쓰기 실패를 줄이기 위해 권한을 넓게 열어 둔다.
    mkdir -p "$NFS_EXPORT_ROOT" "$NFS_EXPORT_ROOT/backups/data" "$NFS_EXPORT_ROOT/backups/logs"
    chmod 0777 "$NFS_EXPORT_ROOT" "$NFS_EXPORT_ROOT/backups" "$NFS_EXPORT_ROOT/backups/data" "$NFS_EXPORT_ROOT/backups/logs"

    # VM 전체가 아니라 지정한 client CIDR에서만 접근할 수 있게 export한다.
    cat > /etc/exports.d/ndjson-todo.exports <<EOF
$NFS_EXPORT_ROOT $NFS_CLIENT_CIDR($NFS_EXPORT_OPTIONS)
EOF

    exportfs -rav
    systemctl restart "$nfs_service"
}

open_nfs_firewall() {
    # OS별 방화벽 도구가 있으면 NFS 관련 포트를 열고, 없으면 수동 조치를 안내한다.
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
