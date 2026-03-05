#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR"
BUILD_DIR="$SOURCE_DIR/build"

# Parse command-line arguments for optional prefix
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

# If no prefix provided, default to source directory
if [[ -z "$PREFIX" ]]; then
    PREFIX="$SOURCE_DIR"
fi

echo "Installing RF_CGRAMap to: $PREFIX"

# Start the build process
mkdir -p "$BUILD_DIR"
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -DCMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build "$BUILD_DIR" --parallel "$(nproc)"
cmake --build "$BUILD_DIR" --target install

echo "RF_CGRAMap build completed successfully"