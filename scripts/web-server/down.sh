#!/bin/sh
set -eu

# 웹서버 실행 환경의 컨테이너만 중지하고 제거한다.
# NFS mount, host data/log 디렉터리, 백업 cron은 건드리지 않는다.
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/web-server/web-server.env"}

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

if ! command -v podman-compose >/dev/null 2>&1; then
    echo "podman-compose is required but not installed." >&2
    exit 1
fi

# compose 파일 두 개를 합쳐서 로컬 기본값에 웹서버 환경용 bind mount를 덮어쓴다.
cd "$ROOT_DIR"
podman-compose -f docker-compose.yml -f docker-compose.web-server.yml stop lb web1 web2 web3
podman-compose -f docker-compose.yml -f docker-compose.web-server.yml rm -f lb web1 web2 web3
