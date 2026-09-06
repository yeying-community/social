#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MODULE_DIR="$(realpath "${SCRIPT_DIR}/..")"

log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

fail() {
    log_err "$*"
    exit 1
}

main() {
    if [[ $# -ne 1 ]]; then
        fail "usage: $0 <target-directory-full-path>"
    fi

    local target_dir="$1"
    local source_config="${MODULE_DIR}/config"
    local target_config="${target_dir}/config"

    [[ "$target_dir" = /* ]] || fail "target directory must be an absolute path: $target_dir"
    [[ -d "$target_dir" ]] || fail "target directory not found: $target_dir"
    [[ -d "$source_config" ]] || fail "source config directory not found: $source_config"

    rm -rf "$target_config" || fail "failed to remove target config directory: $target_config"
    cp -a "$source_config" "$target_config" || fail "failed to copy config directory to target: $target_config"

    exit 0
}

main "$@"
