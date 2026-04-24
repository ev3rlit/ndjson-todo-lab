#!/bin/sh
set -eu

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

cd "$ROOT_DIR"
podman-compose -f docker-compose.yml -f docker-compose.web-server.yml stop lb web1 web2 web3
podman-compose -f docker-compose.yml -f docker-compose.web-server.yml rm -f lb web1 web2 web3
