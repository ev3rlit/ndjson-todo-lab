#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm2/vm2.env"}
export ENV_FILE

. "$ROOT_DIR/scripts/lib/common.sh"
load_env_file "$ENV_FILE"
require_root

sh "$ROOT_DIR/scripts/vm2/install-nfs-server.sh"
sh "$ROOT_DIR/scripts/vm2/configure-nfs-export.sh"
sh "$ROOT_DIR/scripts/vm2/open-firewall.sh"

echo "VM2 NFS setup completed."
