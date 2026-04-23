#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm1/vm1.env"}

. "$ROOT_DIR/scripts/lib/common.sh"
load_env_file "$ENV_FILE"
require_root

TODO_DATA_DIR=${TODO_DATA_DIR:-/srv/ndjson-todo/data}
TODO_LOG_DIR=${TODO_LOG_DIR:-/srv/ndjson-todo/logs}
NGINX_LOG_DIR=${NGINX_LOG_DIR:-/srv/ndjson-todo/logs/nginx}

mkdir -p "$TODO_DATA_DIR" "$TODO_LOG_DIR" "$NGINX_LOG_DIR"
chmod 0777 "$TODO_DATA_DIR" "$TODO_LOG_DIR" "$NGINX_LOG_DIR"
