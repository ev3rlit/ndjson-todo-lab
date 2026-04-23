#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT_DIR/scripts/vm1/vm1.env"}

. "$ROOT_DIR/scripts/lib/common.sh"
load_env_file "$ENV_FILE"

cd "$ROOT_DIR"
run_compose -f docker-compose.yml -f docker-compose.vm1.yml stop lb web1 web2 web3
run_compose -f docker-compose.yml -f docker-compose.vm1.yml rm -f lb web1 web2 web3
