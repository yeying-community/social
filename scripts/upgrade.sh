#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
    printf 'Usage: %s <prepare|copy-config|post-copy|finalize> <current-dir> <target-dir>\n' "$0" >&2
    exit 1
fi

phase=$1
current_dir=$2
target_dir=$3

case "$phase" in
    prepare|post-copy|finalize)
        exit 0
        ;;
    copy-config)
        [[ -d "${current_dir}/config" ]] || { printf 'Missing config directory: %s/config\n' "$current_dir" >&2; exit 1; }
        [[ -d "$target_dir" ]] || { printf 'Missing target directory: %s\n' "$target_dir" >&2; exit 1; }
        rm -rf "${target_dir}/config"
        cp -a "${current_dir}/config" "${target_dir}/config"
        ;;
    *)
        printf 'Unsupported upgrade phase: %s\n' "$phase" >&2
        exit 1
        ;;
esac
