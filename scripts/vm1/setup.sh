#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm1/vm1.env"}
EXAMPLE_ENV_FILE="$ROOT_DIR/scripts/vm1/vm1.env.example"
export ENV_FILE

. "$ROOT_DIR/scripts/lib/common.sh"
overwrite_env_from_example "$EXAMPLE_ENV_FILE" "$ENV_FILE"

echo "[vm1] install nfs client"
sh "$ROOT_DIR/scripts/vm1/install-nfs-client.sh"

echo "[vm1] mount nfs export"
sh "$ROOT_DIR/scripts/vm1/mount-nfs.sh"

echo "[vm1] prepare service directories"
sh "$ROOT_DIR/scripts/vm1/prepare-host-paths.sh"

echo "[vm1] install backup cron"
sh "$ROOT_DIR/scripts/vm1/install-backup-cron.sh"

echo "[vm1] start load balancer and web containers"
sh "$ROOT_DIR/scripts/vm1/up.sh"

echo "[vm1] completed"
echo "[vm1] use scripts/vm1/status.sh to inspect services"
