#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR"
BUILD_DIR="$SOURCE_DIR/build"

# 解析命令行参数
PREFIX=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix=*)
            PREFIX="${1#*=}"
            shift
            ;;
        --prefix)
            if [[ $# -lt 2 ]]; then
                echo "Error: --prefix requires a value" >&2
                exit 1
            fi
            PREFIX="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# 如果没有指定prefix，默认安装到RF_CGRAMap源码目录
if [[ -z "$PREFIX" ]]; then
    PREFIX="$SOURCE_DIR"
fi

echo "Installing RF_CGRAMap to: $PREFIX"

# 配置并构建
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -DCMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build "$BUILD_DIR" --parallel "$(nproc)"
cmake --build "$BUILD_DIR" --target install

echo "RF_CGRAMap build completed successfully"