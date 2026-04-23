#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm2/vm2.env"}
EXAMPLE_ENV_FILE="$ROOT_DIR/scripts/vm2/vm2.env.example"
export ENV_FILE

. "$ROOT_DIR/scripts/lib/common.sh"
overwrite_env_from_example "$EXAMPLE_ENV_FILE" "$ENV_FILE"

echo "[vm2] install and enable nfs server"
sh "$ROOT_DIR/scripts/vm2/install-nfs-server.sh"

echo "[vm2] configure nfs export"
sh "$ROOT_DIR/scripts/vm2/configure-nfs-export.sh"

echo "[vm2] open firewall for nfs"
sh "$ROOT_DIR/scripts/vm2/open-firewall.sh"

echo "[vm2] completed"
echo "[vm2] use scripts/vm2/status.sh to inspect nfs status"
