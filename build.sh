#!/bin/bash

# RfCgraTrans one-shot build script
# Automates the build process according to README.md
# Author: generated from README

set -e  # exit on error
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
LLVM_BUILD_DIR="$PROJECT_ROOT/llvm/build"
MLIR_CLANG_DIR="$PROJECT_ROOT/mlir-clang"
PLUTO_DIR="$PROJECT_ROOT/pluto"
RF_CGRAMAP_DIR="$PROJECT_ROOT/RF_CGRAMap"
LLVM_BUILT=false
PLUTO_FILECHECK_DIR="$BUILD_DIR/.pluto-filecheck"
PLUTO_LLVM_LIB_DIR=""
PLUTO_LLVM_PREFIX="$PROJECT_ROOT/../llvm-9"

prepend_path_var() {
    local var_name="$1"
    local new_dir="$2"
    local current_value="${!var_name:-}"

    if [[ -z "$new_dir" ]]; then
        return 0
    fi

    case ":$current_value:" in
        *":$new_dir:"*)
            ;;
        *)
            if [[ -n "$current_value" ]]; then
                printf -v "$var_name" '%s:%s' "$new_dir" "$current_value"
            else
                printf -v "$var_name" '%s' "$new_dir"
            fi
            export "$var_name"
            ;;
    esac
}

bootstrap_local_toolchain_path() {
    local local_bins=(
        "$PROJECT_ROOT/../llvm-9/bin"
    )

    local bin_dir
    for bin_dir in "${local_bins[@]}"; do
        if [[ -d "$bin_dir" ]]; then
            prepend_path_var PATH "$bin_dir"
        fi
    done
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -y, --yes      Skip confirmation prompts and proceed"
    echo "  --prebuild-external  Prebuild ExternalProject dependencies (PLuTo/RF_CGRAMap)"
    echo "  --clean        Clean all build artifacts and generated files"
    echo "  --clean-build  Clean only the build directory"
    echo "  --clean-pluto  Clean only PLuTo build artifacts"
    echo "  --clean-llvm   Clean only LLVM build artifacts"
    echo "  --clean-mlir   Clean only mlir-clang build artifacts"
    echo "  --clean-rf     Clean only RF_CGRAMap build artifacts"
    echo "  --skip-deps    Skip dependency checks"
    echo "  --skip-pluto   Skip PLuTo build"
    echo "  --skip-mlir    Skip mlir-clang build"
    echo "  --skip-llvm    Skip LLVM build"
    echo "  --skip-rf      Skip RF_CGRAMap build"
    echo "  --skip-project Skip main project build"
    echo ""
    echo "One-shot build for the RfCgraTrans project; automates the process described in README.md."
    echo "By default this checks system dependencies and suggests installation if missing."
    echo ""
    echo "Cleanup examples:"
    echo "  $0 --clean          # Clean all build artifacts"
    echo "  $0 --clean-build    # Clean main project build directory only"
    echo "  $0 --clean-pluto    # Clean PLuTo build artifacts only"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' not found; please install it and re-run the script"
        return 1
    fi
    return 0
}

check_dependencies() {
    log_info "Checking system dependencies..."

    local deps=("cmake" "ninja" "clang-9" "git" "make" "autoconf" "pkg-config" "flex" "bison")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null && ! dpkg -l | grep -q "$dep"; then
            log_warn "Dependency '$dep' is not installed"
            log_warn "Please install dependencies with the following commands:"
            echo "sudo apt update"
            echo "sudo apt install apt-utils tzdata build-essential libtool autoconf pkg-config flex bison libgmp-dev clang-9 libclang-9-dev texinfo cmake ninja-build git texlive-full numactl"
            echo "Then run the following to set alternatives:"
            echo "sudo update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-9 100"
            echo "sudo update-alternatives --install /usr/bin/FileCheck FileCheck /usr/bin/FileCheck-9 100"
            echo "sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-9 100"
            echo "sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-9 100"
            return 1
        fi
    done

    log_info "System dependency check passed"
    return 0
}

find_filecheck_binary() {
    local candidates=(
        "$(command -v FileCheck 2>/dev/null || true)"
        "$(command -v FileCheck-9 2>/dev/null || true)"
        "$PROJECT_ROOT/../llvm-9/bin/FileCheck"
        "$PROJECT_ROOT/../llvm-9/bin/FileCheck-9"
        "$PROJECT_ROOT/../llvm-10/bin/FileCheck"
        "$PROJECT_ROOT/../llvm-10/bin/FileCheck-10"
        "$PROJECT_ROOT/../llvm-12/bin/FileCheck"
        "$PROJECT_ROOT/../llvm-12/bin/FileCheck-12"
        "$PROJECT_ROOT/llvm/build/bin/FileCheck"
        "$PROJECT_ROOT/llvm/build/bin/FileCheck-9"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

ensure_filecheck_for_pluto() {
    local filecheck_bin=""
    local wrapper_bin=""

    filecheck_bin="$(find_filecheck_binary 2>/dev/null || true)"
    if [[ -n "$filecheck_bin" ]]; then
        mkdir -p "$PLUTO_FILECHECK_DIR"
        wrapper_bin="$PLUTO_FILECHECK_DIR/FileCheck"
        ln -sf "$filecheck_bin" "$wrapper_bin"
        export PATH="$PLUTO_FILECHECK_DIR:$PATH"
        if [[ -z "$PLUTO_LLVM_LIB_DIR" ]]; then
            if [[ -x "$(command -v llvm-config 2>/dev/null || true)" ]]; then
                PLUTO_LLVM_LIB_DIR="$(llvm-config --libdir 2>/dev/null || true)"
            fi
            if [[ -z "$PLUTO_LLVM_LIB_DIR" ]]; then
                local resolved_filecheck resolved_llvm_bin
                resolved_filecheck="$(readlink -f "$filecheck_bin" 2>/dev/null || printf '%s' "$filecheck_bin")"
                resolved_llvm_bin="$(cd "$(dirname "$resolved_filecheck")" && pwd)"
                PLUTO_LLVM_LIB_DIR="$(cd "$resolved_llvm_bin/.." && pwd)/lib"
            fi
        fi
        if [[ -d "$PLUTO_LLVM_LIB_DIR" ]]; then
            prepend_path_var LD_LIBRARY_PATH "$PLUTO_LLVM_LIB_DIR"
            prepend_path_var LIBRARY_PATH "$PLUTO_LLVM_LIB_DIR"
            log_info "Using LLVM library path for PLuTo: $PLUTO_LLVM_LIB_DIR"
        fi
        log_info "Using FileCheck for PLuTo: $filecheck_bin"
        return 0
    fi

    log_warn "No FileCheck found on PATH or in local LLVM tool directories"

    if [[ "$SKIP_LLVM" == true ]]; then
        log_error "FileCheck is required for PLuTo, but LLVM build is skipped and no fallback FileCheck was found"
        return 1
    fi

    if [[ ! -d "$PROJECT_ROOT/llvm" ]]; then
        log_error "LLVM source directory not found: $PROJECT_ROOT/llvm"
        return 1
    fi

    log_info "Building LLVM first so PLuTo can use its generated FileCheck..."
    build_llvm || return 1

    filecheck_bin="$(find_filecheck_binary 2>/dev/null || true)"
    if [[ -z "$filecheck_bin" ]]; then
        log_error "LLVM build completed, but FileCheck was still not found"
        return 1
    fi

    mkdir -p "$PLUTO_FILECHECK_DIR"
    wrapper_bin="$PLUTO_FILECHECK_DIR/FileCheck"
    ln -sf "$filecheck_bin" "$wrapper_bin"
    export PATH="$PLUTO_FILECHECK_DIR:$PATH"
    if [[ -z "$PLUTO_LLVM_LIB_DIR" ]]; then
        if [[ -x "$(command -v llvm-config 2>/dev/null || true)" ]]; then
            PLUTO_LLVM_LIB_DIR="$(llvm-config --libdir 2>/dev/null || true)"
        fi
        if [[ -z "$PLUTO_LLVM_LIB_DIR" ]]; then
            local resolved_filecheck resolved_llvm_bin
            resolved_filecheck="$(readlink -f "$filecheck_bin" 2>/dev/null || printf '%s' "$filecheck_bin")"
            resolved_llvm_bin="$(cd "$(dirname "$resolved_filecheck")" && pwd)"
            PLUTO_LLVM_LIB_DIR="$(cd "$resolved_llvm_bin/.." && pwd)/lib"
        fi
    fi
    if [[ -d "$PLUTO_LLVM_LIB_DIR" ]]; then
        prepend_path_var LD_LIBRARY_PATH "$PLUTO_LLVM_LIB_DIR"
        prepend_path_var LIBRARY_PATH "$PLUTO_LLVM_LIB_DIR"
        log_info "Using LLVM library path for PLuTo: $PLUTO_LLVM_LIB_DIR"
    fi
    log_info "Using LLVM-built FileCheck for PLuTo: $filecheck_bin"
    return 0
}

build_pluto() {
    log_info "Building PLuTo..."

    if [[ ! -d "$PLUTO_DIR" ]]; then
        log_error "PLuTo directory not found: $PLUTO_DIR"
        return 1
    fi

    cd "$PLUTO_DIR"

    if [[ ! -d "$PLUTO_LLVM_PREFIX/bin" ]]; then
        log_error "Required LLVM 9 toolchain not found: $PLUTO_LLVM_PREFIX/bin"
        return 1
    fi

    export CC="$PLUTO_LLVM_PREFIX/bin/clang-9"
    export CXX="$PLUTO_LLVM_PREFIX/bin/clang++-9"

    log_info "Cleaning build..."
    make distclean 2>/dev/null || true

    log_info "Running autogen.sh..."
    ./autogen.sh || { log_error "autogen.sh failed"; return 1; }

    log_info "Running configure (install to $BUILD_DIR/pluto)..."
    ./configure \
        --prefix="$BUILD_DIR/pluto" \
        --with-clang-prefix="$PLUTO_LLVM_PREFIX" \
        --with-clang-exec-prefix="$PLUTO_LLVM_PREFIX" || { log_error "configure failed"; return 1; }

    log_info "Building PLuTo (using $(nproc) cores)..."
    make -j$(nproc) || { log_error "PLuTo build failed"; return 1; }

    log_info "Installing PLuTo into project directory..."
    make install || { log_error "PLuTo install failed"; return 1; }

    cd "$PROJECT_ROOT"
    log_info "PLuTo build complete"
}

build_mlir_clang() {
    log_info "Building mlir-clang (Polygeist)..."

    if [[ ! -d "$MLIR_CLANG_DIR" ]]; then
        log_info "Cloning Polygeist repository..."
        git clone -b main-042621 --single-branch https://github.com/wsmoses/Polygeist "$MLIR_CLANG_DIR" || {
            log_error "Failed to clone Polygeist";
            return 1;
        }
    else
        log_info "mlir-clang directory exists, skipping clone"
    fi

    cd "$MLIR_CLANG_DIR"

    if [[ ! -d "build" ]]; then
        mkdir build
    fi

    cd build

    log_info "Cleaning CMake cache files..."
    rm -f CMakeCache.txt cmake_install.cmake install_manifest.txt 2>/dev/null || true
    rm -rf CMakeFiles 2>/dev/null || true

    log_info "Configuring mlir-clang..."
    cmake -G Ninja ../llvm \
        -DLLVM_ENABLE_PROJECTS="mlir;polly;clang;openmp" \
        -DLLVM_BUILD_EXAMPLES=ON \
        -DLLVM_TARGETS_TO_BUILD="host" \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_ENABLE_ASSERTIONS=ON || { log_error "cmake configuration failed"; return 1; }

    log_info "Building mlir-clang (using $(nproc) cores)..."
    ninja -j $(nproc) || { log_error "mlir-clang build failed"; return 1; }

    cd "$PROJECT_ROOT"
    log_info "mlir-clang build complete"
}

build_llvm() {
    log_info "Building LLVM..."

    if [[ ! -d "$PROJECT_ROOT/llvm" ]]; then
        log_error "LLVM directory not found: $PROJECT_ROOT/llvm"
        return 1
    fi

    cd "$PROJECT_ROOT/llvm"

    if [[ ! -d "build" ]]; then
        mkdir build
    fi

    cd build

    log_info "Cleaning CMake cache files..."
    rm -f CMakeCache.txt cmake_install.cmake install_manifest.txt 2>/dev/null || true
    rm -rf CMakeFiles 2>/dev/null || true

    log_info "Configuring LLVM..."
    cmake ../llvm \
        -DLLVM_ENABLE_PROJECTS="llvm;clang;mlir" \
        -DLLVM_TARGETS_TO_BUILD="host" \
        -DLLVM_ENABLE_ASSERTIONS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_INSTALL_UTILS=ON \
        -G Ninja || { log_error "LLVM cmake configuration failed"; return 1; }

    log_info "Building LLVM (using $(nproc) cores)..."
    ninja -j$(nproc) || { log_error "LLVM build failed"; return 1; }

    cd "$PROJECT_ROOT"
    LLVM_BUILT=true
    log_info "LLVM build complete"
}

build_project() {
    log_info "Building RfCgraTrans project..."

    if [[ ! -d "$BUILD_DIR" ]]; then
        mkdir -p "$BUILD_DIR"
    fi

    cd "$BUILD_DIR"

    log_info "Cleaning CMake cache files..."
    rm -f CMakeCache.txt cmake_install.cmake install_manifest.txt 2>/dev/null || true
    rm -rf CMakeFiles 2>/dev/null || true

    export BUILD="$PROJECT_ROOT/llvm/build"

    if [[ ! -d "$BUILD" ]]; then
        log_error "LLVM build directory not found: $BUILD"
        log_error "Please build LLVM first"
        return 1
    fi

    log_info "Configuring RfCgraTrans..."
    cmake .. \
        -DCMAKE_BUILD_TYPE=DEBUG \
        -DCMAKE_EXE_LINKER_FLAGS=-no-pie \
        -DMLIR_DIR="$BUILD/lib/cmake/mlir" \
        -DLLVM_DIR="$BUILD/lib/cmake/llvm" \
        -DLLVM_ENABLE_ASSERTIONS=ON \
        -DLLVM_EXTERNAL_LIT="$BUILD/bin/llvm-lit" \
        -G Ninja || { log_error "Project cmake configuration failed"; return 1; }

    log_info "Building RfCgraTrans (using $(nproc) cores)..."
    ninja -j$(nproc) || { log_error "RfCgraTrans build failed"; return 1; }

    cd "$PROJECT_ROOT"
    log_info "RfCgraTrans project build complete"
}

build_rf_cgramap() {
    log_info "Building RF_CGRAMap submodule..."

    if [[ ! -d "$RF_CGRAMAP_DIR" ]]; then
        log_error "RF_CGRAMap directory not found: $RF_CGRAMAP_DIR"
        return 1
    fi

    log_info "Calling RF_CGRAMap/build.sh to configure, build and install..."
    "$RF_CGRAMAP_DIR/build.sh" --prefix="$BUILD_DIR/RF_CGRAMap" || {
        log_error "RF_CGRAMap build script failed"
        return 1
    }

    # After install, files are located under $BUILD_DIR/RF_CGRAMap; no extra copy needed
    log_info "RF_CGRAMap installed to $BUILD_DIR/RF_CGRAMap"

    cd "$PROJECT_ROOT"
    log_info "RF_CGRAMap build complete"
}

clean_pluto() {
    log_info "Cleaning PLuTo build artifacts..."
    
    if [[ ! -d "$PLUTO_DIR" ]]; then
        log_warn "PLuTo directory not found: $PLUTO_DIR"
        return 0
    fi
    
    cd "$PLUTO_DIR"
    
    if [[ -f "Makefile" ]]; then
        log_info "Running make distclean..."
        make distclean 2>/dev/null || make clean 2>/dev/null || true
    fi
    
    cd "$PROJECT_ROOT"
    log_info "PLuTo cleanup complete"
}

clean_llvm() {
    log_info "Cleaning LLVM build artifacts..."
    
    if [[ -d "$LLVM_BUILD_DIR" ]]; then
        log_info "Removing $LLVM_BUILD_DIR ..."
        rm -rf "$LLVM_BUILD_DIR"
        log_info "LLVM build directory removed"
    else
        log_warn "LLVM build directory not found: $LLVM_BUILD_DIR"
    fi
}

clean_mlir() {
    log_info "Cleaning mlir-clang build artifacts..."
    
    local MLIR_BUILD_DIR="$MLIR_CLANG_DIR/build"
    if [[ -d "$MLIR_BUILD_DIR" ]]; then
        log_info "Removing $MLIR_BUILD_DIR ..."
        rm -rf "$MLIR_BUILD_DIR"
        log_info "mlir-clang build directory removed"
    else
        log_warn "mlir-clang build directory not found: $MLIR_BUILD_DIR"
    fi
}

clean_rf() {
    log_info "Cleaning RF_CGRAMap build artifacts..."
    
    local RF_BUILD_DIR="$RF_CGRAMAP_DIR/build"
    if [[ -d "$RF_BUILD_DIR" ]]; then
        log_info "Removing $RF_BUILD_DIR ..."
        rm -rf "$RF_BUILD_DIR"
    fi
    
    # Also clean RF_CGRAMap installed under the main build directory
    if [[ -d "$BUILD_DIR/RF_CGRAMap" ]]; then
        log_info "Removing $BUILD_DIR/RF_CGRAMap ..."
        rm -rf "$BUILD_DIR/RF_CGRAMap"
    fi
    
    log_info "RF_CGRAMap cleanup complete"
}

clean_build() {
    log_info "Cleaning main project build directory..."
    
    if [[ -d "$BUILD_DIR" ]]; then
        log_info "Removing $BUILD_DIR ..."
        rm -rf "$BUILD_DIR"
        log_info "Main project build directory removed"
    else
        log_warn "Main project build directory not found: $BUILD_DIR"
    fi
}

clean_examples() {
    log_info "Cleaning generated files in example directory..."
    
    local EXAMPLE_DIR="$PROJECT_ROOT/example"
    if [[ ! -d "$EXAMPLE_DIR" ]]; then
        log_warn "example directory not found"
        return 0
    fi
    
    cd "$EXAMPLE_DIR"
    
    # Clean generated files, keep .c and .h
    log_info "Removing generated files: *.out, *.txt, *.ll, *.mlir, *.cloog, etc..."
    find . -type f \( \
        -name "*.out" -o \
        -name "*.txt" -o \
        -name "*.ll" -o \
        -name "*.mlir" -o \
        -name "*.cloog" -o \
        -name "*.pluto.c" -o \
        -name "*.plutopar.c" -o \
        -name "DFGInformation.out" -o \
        -name "MapInformation.out" \
    \) -delete 2>/dev/null || true
    
    cd "$PROJECT_ROOT"
    log_info "example cleanup complete"
}

clean_all() {
    log_warn "About to clean all build artifacts and generated files!"
    log_warn "This will remove the following:"
    echo "  - $BUILD_DIR"
    echo "  - $LLVM_BUILD_DIR"
    echo "  - $MLIR_CLANG_DIR/build"
    echo "  - PLuTo build artifacts"
    echo "  - RF_CGRAMap build artifacts"
    echo "  - generated files in example directory"
    
    if [[ "$AUTO_YES" == false ]]; then
        read -p "Confirm to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleaning cancelled"
            return 0
        fi
    fi
    
    clean_build
    clean_pluto
    clean_llvm
    clean_mlir
    clean_rf
    clean_examples
    
    # Remove generated environment file
    if [[ -f "$PROJECT_ROOT/env.sh" ]]; then
        log_info "Removing env.sh ..."
        rm -f "$PROJECT_ROOT/env.sh"
    fi
    
    log_info "========================================"
    log_info "Cleanup complete!"
    log_info "========================================"
}

main() {
    # Defaults
    SKIP_DEPS=false
    SKIP_PLUTO=false
    SKIP_MLIR=false
    SKIP_LLVM=false
    SKIP_RF=false
    SKIP_PROJECT=false
    AUTO_YES=false
    DO_CLEAN=false
    CLEAN_MODE=""
    PREBUILD_EXTERNAL=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            --prebuild-external)
                PREBUILD_EXTERNAL=true
                shift
                ;;
            --clean)
                DO_CLEAN=true
                CLEAN_MODE="all"
                shift
                ;;
            --clean-build)
                DO_CLEAN=true
                CLEAN_MODE="build"
                shift
                ;;
            --clean-pluto)
                DO_CLEAN=true
                CLEAN_MODE="pluto"
                shift
                ;;
            --clean-llvm)
                DO_CLEAN=true
                CLEAN_MODE="llvm"
                shift
                ;;
            --clean-mlir)
                DO_CLEAN=true
                CLEAN_MODE="mlir"
                shift
                ;;
            --clean-rf)
                DO_CLEAN=true
                CLEAN_MODE="rf"
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --skip-pluto)
                SKIP_PLUTO=true
                shift
                ;;
            --skip-mlir)
                SKIP_MLIR=true
                shift
                ;;
            --skip-llvm)
                SKIP_LLVM=true
                shift
                ;;
            --skip-rf)
                SKIP_RF=true
                shift
                ;;
            --skip-project)
                SKIP_PROJECT=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # If running in clean mode, perform cleaning then exit
    if [[ "$DO_CLEAN" == true ]]; then
        case $CLEAN_MODE in
            all)
                clean_all
                ;;
            build)
                clean_build
                ;;
            pluto)
                clean_pluto
                ;;
            llvm)
                clean_llvm
                ;;
            mlir)
                clean_mlir
                ;;
            rf)
                clean_rf
                ;;
        esac
        exit 0
    fi

    log_info "Starting RfCgraTrans build..."
    log_info "Project root: $PROJECT_ROOT"

    bootstrap_local_toolchain_path

    # Check dependencies
    if [[ "$SKIP_DEPS" == false ]]; then
        check_dependencies || {
            log_warn "Dependency check failed; please install missing dependencies and re-run the script"
            if [[ "$AUTO_YES" == false ]]; then
                read -p "Continue? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            else
                log_info "Continuing automatically..."
            fi
        }
    else
        log_info "Skipping dependency checks"
    fi

    # Build PLuTo
    if [[ "$SKIP_PLUTO" == false ]]; then
        ensure_filecheck_for_pluto || {
            log_error "Unable to prepare FileCheck for PLuTo, aborting"
            exit 1
        }

        if [[ "$PREBUILD_EXTERNAL" == true ]]; then
            build_pluto || {
                    log_error "PLuTo build failed, aborting"
                exit 1
            }
        else
            log_info "PLuTo will be built by ExternalProject during the main project build; skipping prebuild"
        fi
    else
        log_info "Skipping PLuTo build"
    fi

    # Build mlir-clang
    if [[ "$SKIP_MLIR" == false ]]; then
        build_mlir_clang || {
            log_error "mlir-clang build failed, aborting"
            exit 1
        }
    else
        log_info "Skipping mlir-clang build"
    fi

    # Build LLVM
    if [[ "$SKIP_LLVM" == false ]]; then
        if [[ "$LLVM_BUILT" == true ]]; then
            log_info "LLVM was already built for FileCheck; skipping duplicate LLVM build"
        else
            build_llvm || {
                log_error "LLVM build failed, aborting"
                exit 1
            }
        fi
    else
        log_info "Skipping LLVM build"
    fi

    # Build RF_CGRAMap submodule
    if [[ "$SKIP_RF" == false ]]; then
        if [[ "$PREBUILD_EXTERNAL" == true ]]; then
            build_rf_cgramap || {
                log_warn "RF_CGRAMap build failed, continuing main project build"
            }
        else
            log_info "RF_CGRAMap will be built by ExternalProject during the main project build; skipping prebuild"
        fi
    else
        log_info "Skipping RF_CGRAMap build"
    fi

    # Build main project
    if [[ "$SKIP_PROJECT" == false ]]; then
        build_project || {
            log_error "Main project build failed"
            exit 1
        }
    else
        log_info "Skipping main project build"
    fi

    log_info "Generating environment configuration file..."
    ENV_FILE="$PROJECT_ROOT/env.sh"
    cat > "$ENV_FILE" << 'EOF'
#!/bin/bash
# RfCgraTrans environment configuration
# Usage: source env.sh

# Ensure script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Error: please use 'source env.sh' or '. env.sh' to apply this file to your shell"
    echo "Running directly will not modify the current shell's environment"
    exit 1
fi

# Compute project root purely in shell without external commands
_script="${BASH_SOURCE[0]}"
# Determine script directory
if [[ "$_script" == */* ]]; then
    _dir="${_script%/*}"
    if cd "$_dir" 2>/dev/null; then
        export PROJECT_ROOT="$PWD"
        cd - >/dev/null 2>&1
    else
        # Fallback to current directory if not accessible
        export PROJECT_ROOT="$PWD"
    fi
else
    export PROJECT_ROOT="$PWD"
fi

export BUILD="$PROJECT_ROOT/llvm/build"
export LD_LIBRARY_PATH="$PROJECT_ROOT/build/RF_CGRAMap/lib:$PROJECT_ROOT/build/pluto/lib:$LD_LIBRARY_PATH"

# Add likely binary directories to PATH
_bin_dirs=(
    "$PROJECT_ROOT/build/tools"
    "$BUILD/bin"
    "$PROJECT_ROOT/build/bin"
    "$PROJECT_ROOT/mlir-clang/build/bin"
    "$PROJECT_ROOT/pluto"
)

_new_path=""
for _dir in "${_bin_dirs[@]}"; do
    if [[ -d "$_dir" ]]; then
        _new_path="$_dir:${_new_path}"
    fi
done

if [[ -n "$_new_path" ]]; then
    export PATH="${_new_path}$PATH"
else
    echo "Warning: no binary directories found; PATH unchanged"
fi

# Cleanup temporary variables
unset _script _dir _bin_dirs _new_path

# Check expected build paths
if [[ ! -d "$BUILD" ]]; then
    echo "Warning: LLVM build directory not found: $BUILD"
    echo "Please ensure LLVM was built successfully"
fi

if [[ ! -d "$PROJECT_ROOT/build/pluto/lib" ]]; then
    echo "Warning: PLuTo library directory not found"
fi

if [[ ! -d "$PROJECT_ROOT/build/RF_CGRAMap/lib" ]]; then
    echo "Warning: RF_CGRAMap library directory not found"
fi

echo "Environment variables set:"
echo "  PROJECT_ROOT: $PROJECT_ROOT"
echo "  BUILD: $BUILD"
echo "  LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "  PATH: $PATH"
EOF

    chmod +x "$ENV_FILE"
    log_info "Environment configuration file generated: $ENV_FILE"
    log_info "Usage: source $ENV_FILE"

    log_info "========================================"
    log_info "Build complete!"
    log_info "========================================"
    log_info "Build artifacts located at: $BUILD_DIR"
    log_info "Environment file env.sh generated"
    log_info "To set environment variables, run:"
    echo "source $PROJECT_ROOT/env.sh"
    log_info "To run examples, execute:"
    echo "cd example && ./run.sh"
    log_info "========================================"
}

# Run main function
main "$@"