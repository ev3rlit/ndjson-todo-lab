#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm2/vm2.env"}

. "$ROOT_DIR/scripts/lib/common.sh"
load_env_file "$ENV_FILE"
require_root

service_name=$(nfs_server_service)
systemctl stop "$service_name"

if [ -f /etc/exports.d/ndjson-todo.exports ]; then
    rm -f /etc/exports.d/ndjson-todo.exports
    exportfs -rav
fi
