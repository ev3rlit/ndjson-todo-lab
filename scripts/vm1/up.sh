#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm1/vm1.env"}

. "$ROOT_DIR/scripts/lib/common.sh"
load_env_file "$ENV_FILE"

TODO_DATA_DIR=${TODO_DATA_DIR:-/srv/ndjson-todo/data}
TODO_LOG_DIR=${TODO_LOG_DIR:-/srv/ndjson-todo/logs}
NGINX_LOG_DIR=${NGINX_LOG_DIR:-/srv/ndjson-todo/logs/nginx}
LB_PORT=${LB_PORT:-8080}

for required_dir in "$TODO_DATA_DIR" "$TODO_LOG_DIR" "$NGINX_LOG_DIR"; do
    if [ ! -d "$required_dir" ]; then
        echo "Missing host path: $required_dir" >&2
        echo "Run sudo scripts/vm1/prepare-host-paths.sh first." >&2
        exit 1
    fi
done

cd "$ROOT_DIR"
docker compose -f docker-compose.yml -f docker-compose.vm1.yml up -d --build web1 web2 web3 lb
