#!/bin/sh

set -eu

load_env_file() {
    env_file=$1
    if [ -f "$env_file" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$env_file"
        set +a
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Run this script as root." >&2
        exit 1
    fi
}

detect_package_manager() {
    if command -v dnf >/dev/null 2>&1; then
        echo dnf
        return
    fi
    if command -v apt-get >/dev/null 2>&1; then
        echo apt
        return
    fi

    echo "Unsupported package manager. Expected dnf or apt-get." >&2
    exit 1
}

install_packages() {
    pkg_manager=$(detect_package_manager)

    case "$pkg_manager" in
        dnf)
            dnf install -y "$@"
            ;;
        apt)
            apt-get update
            apt-get install -y "$@"
            ;;
    esac
}

nfs_server_package() {
    pkg_manager=$(detect_package_manager)

    case "$pkg_manager" in
        dnf)
            echo nfs-utils
            ;;
        apt)
            echo nfs-kernel-server
            ;;
    esac
}

nfs_client_package() {
    pkg_manager=$(detect_package_manager)

    case "$pkg_manager" in
        dnf)
            echo nfs-utils
            ;;
        apt)
            echo nfs-common
            ;;
    esac
}

nfs_server_service() {
    pkg_manager=$(detect_package_manager)

    case "$pkg_manager" in
        dnf)
            echo nfs-server
            ;;
        apt)
            echo nfs-kernel-server
            ;;
    esac
}

ensure_line_in_file() {
    expected_line=$1
    target_file=$2

    touch "$target_file"
    if ! grep -Fqx "$expected_line" "$target_file"; then
        printf '%s\n' "$expected_line" >> "$target_file"
    fi
}

container_engine() {
    echo "${CONTAINER_ENGINE:-docker}"
}

run_compose() {
    engine=$(container_engine)

    case "$engine" in
        docker|podman)
            "$engine" compose "$@"
            ;;
        *)
            echo "Unsupported container engine: $engine" >&2
            exit 1
            ;;
    esac
}
