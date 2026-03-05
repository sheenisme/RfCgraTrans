#!/bin/bash

# RfCgraTrans一键编译脚本
# 根据README.md自动化编译过程
# 作者: 根据README生成

set -e  # 遇到错误退出
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
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -y, --yes      跳过确认提示，自动继续"
    echo "  --prebuild-external  预先编译ExternalProject依赖(PLuTo/RF_CGRAMap)"
    echo "  --clean        清理所有构建产物和生成文件"
    echo "  --clean-build  仅清理build目录"
    echo "  --clean-pluto  仅清理PLuTo构建产物"
    echo "  --clean-llvm   仅清理LLVM构建产物"
    echo "  --clean-mlir   仅清理mlir-clang构建产物"
    echo "  --clean-rf     仅清理RF_CGRAMap构建产物"
    echo "  --skip-deps    跳过依赖检查"
    echo "  --skip-pluto   跳过PLuTo编译"
    echo "  --skip-mlir    跳过mlir-clang编译"
    echo "  --skip-llvm    跳过LLVM编译"
    echo "  --skip-rf      跳过RF_CGRAMap编译"
    echo "  --skip-project 跳过主项目编译"
    echo ""
    echo "一键编译RfCgraTrans项目，根据README.md自动化整个过程。"
    echo "默认情况下会检查系统依赖，如果缺失会提示安装。"
    echo ""
    echo "清理示例:"
    echo "  $0 --clean          # 清理所有构建产物"
    echo "  $0 --clean-build    # 仅清理主项目构建目录"
    echo "  $0 --clean-pluto    # 仅清理PLuTo构建产物"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 '$1' 未找到，请安装后再运行脚本"
        return 1
    fi
    return 0
}

check_dependencies() {
    log_info "检查系统依赖..."

    local deps=("cmake" "ninja" "clang-9" "clang++-9" "llvm-config-9" "FileCheck-9" "git" "make" "autoconf" "pkg-config" "flex" "bison")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null && ! dpkg -l | grep -q "$dep"; then
            log_warn "依赖 '$dep' 未安装"
            log_warn "请运行以下命令安装依赖:"
            echo "sudo apt update"
            echo "sudo apt install apt-utils tzdata build-essential libtool autoconf pkg-config flex bison libgmp-dev clang-9 libclang-9-dev texinfo cmake ninja-build git texlive-full numactl"
            echo "然后运行:"
            echo "sudo update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-9 100"
            echo "sudo update-alternatives --install /usr/bin/FileCheck FileCheck /usr/bin/FileCheck-9 100"
            echo "sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-9 100"
            echo "sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-9 100"
            return 1
        fi
    done

    log_info "系统依赖检查通过"
    return 0
}

build_pluto() {
    log_info "编译PLuTo..."

    if [[ ! -d "$PLUTO_DIR" ]]; then
        log_error "PLuTo目录不存在: $PLUTO_DIR"
        return 1
    fi

    cd "$PLUTO_DIR"

    log_info "清理构建..."
    make distclean 2>/dev/null || true

    log_info "运行autogen.sh..."
    ./autogen.sh || { log_error "autogen.sh失败"; return 1; }

    log_info "运行configure (安装到 $BUILD_DIR/pluto)..."
    ./configure --prefix="$BUILD_DIR/pluto" || { log_error "configure失败"; return 1; }

    log_info "编译PLuTo (使用$(nproc)个核心)..."
    make -j$(nproc) || { log_error "编译PLuTo失败"; return 1; }

    log_info "安装PLuTo到项目目录..."
    make install || { log_error "安装PLuTo失败"; return 1; }

    cd "$PROJECT_ROOT"
    log_info "PLuTo编译完成"
}

build_mlir_clang() {
    log_info "编译mlir-clang (Polygeist)..."

    if [[ ! -d "$MLIR_CLANG_DIR" ]]; then
        log_info "克隆Polygeist仓库..."
        git clone -b main-042621 --single-branch https://github.com/wsmoses/Polygeist "$MLIR_CLANG_DIR" || {
            log_error "克隆Polygeist失败";
            return 1;
        }
    else
        log_info "mlir-clang目录已存在，跳过克隆"
    fi

    cd "$MLIR_CLANG_DIR"

    if [[ ! -d "build" ]]; then
        mkdir build
    fi

    cd build

    log_info "清理CMake缓存文件..."
    rm -f CMakeCache.txt cmake_install.cmake install_manifest.txt 2>/dev/null || true
    rm -rf CMakeFiles 2>/dev/null || true

    log_info "配置mlir-clang..."
    cmake -G Ninja ../llvm \
        -DLLVM_ENABLE_PROJECTS="mlir;polly;clang;openmp" \
        -DLLVM_BUILD_EXAMPLES=ON \
        -DLLVM_TARGETS_TO_BUILD="host" \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_ENABLE_ASSERTIONS=ON || { log_error "cmake配置失败"; return 1; }

    log_info "编译mlir-clang (使用$(nproc)个核心)..."
    ninja -j $(nproc) || { log_error "编译mlir-clang失败"; return 1; }

    cd "$PROJECT_ROOT"
    log_info "mlir-clang编译完成"
}

build_llvm() {
    log_info "编译LLVM..."

    if [[ ! -d "$PROJECT_ROOT/llvm" ]]; then
        log_error "LLVM目录不存在: $PROJECT_ROOT/llvm"
        return 1
    fi

    cd "$PROJECT_ROOT/llvm"

    if [[ ! -d "build" ]]; then
        mkdir build
    fi

    cd build

    log_info "清理CMake缓存文件..."
    rm -f CMakeCache.txt cmake_install.cmake install_manifest.txt 2>/dev/null || true
    rm -rf CMakeFiles 2>/dev/null || true

    log_info "配置LLVM..."
    cmake ../llvm \
        -DLLVM_ENABLE_PROJECTS="llvm;clang;mlir" \
        -DLLVM_TARGETS_TO_BUILD="host" \
        -DLLVM_ENABLE_ASSERTIONS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_INSTALL_UTILS=ON \
        -G Ninja || { log_error "LLVM cmake配置失败"; return 1; }

    log_info "编译LLVM (使用$(nproc)个核心)..."
    ninja -j$(nproc) || { log_error "编译LLVM失败"; return 1; }

    cd "$PROJECT_ROOT"
    log_info "LLVM编译完成"
}

build_project() {
    log_info "编译RfCgraTrans项目..."

    if [[ ! -d "$BUILD_DIR" ]]; then
        mkdir -p "$BUILD_DIR"
    fi

    cd "$BUILD_DIR"

    log_info "清理CMake缓存文件..."
    rm -f CMakeCache.txt cmake_install.cmake install_manifest.txt 2>/dev/null || true
    rm -rf CMakeFiles 2>/dev/null || true

    export BUILD="$PROJECT_ROOT/llvm/build"

    if [[ ! -d "$BUILD" ]]; then
        log_error "LLVM构建目录不存在: $BUILD"
        log_error "请先编译LLVM"
        return 1
    fi

    log_info "配置RfCgraTrans..."
    cmake .. \
        -DCMAKE_BUILD_TYPE=DEBUG \
        -DMLIR_DIR="$BUILD/lib/cmake/mlir" \
        -DLLVM_DIR="$BUILD/lib/cmake/llvm" \
        -DLLVM_ENABLE_ASSERTIONS=ON \
        -DLLVM_EXTERNAL_LIT="$BUILD/bin/llvm-lit" \
        -G Ninja || { log_error "项目cmake配置失败"; return 1; }

    log_info "编译RfCgraTrans (使用$(nproc)个核心)..."
    ninja -j$(nproc) || { log_error "编译RfCgraTrans失败"; return 1; }

    cd "$PROJECT_ROOT"
    log_info "RfCgraTrans项目编译完成"
}

build_rf_cgramap() {
    log_info "编译RF_CGRAMap子模块..."

    if [[ ! -d "$RF_CGRAMAP_DIR" ]]; then
        log_error "RF_CGRAMap目录不存在: $RF_CGRAMAP_DIR"
        return 1
    fi

    log_info "调用RF_CGRAMap/build.sh进行配置、编译与安装..."
    "$RF_CGRAMAP_DIR/build.sh" --prefix="$BUILD_DIR/RF_CGRAMap" || {
        log_error "RF_CGRAMap构建脚本执行失败"
        return 1
    }

    # 安装后，文件已经位于 $BUILD_DIR/RF_CGRAMap，无需额外复制
    log_info "RF_CGRAMap已安装到 $BUILD_DIR/RF_CGRAMap"

    cd "$PROJECT_ROOT"
    log_info "RF_CGRAMap编译完成"
}

clean_pluto() {
    log_info "清理PLuTo构建产物..."
    
    if [[ ! -d "$PLUTO_DIR" ]]; then
        log_warn "PLuTo目录不存在: $PLUTO_DIR"
        return 0
    fi
    
    cd "$PLUTO_DIR"
    
    if [[ -f "Makefile" ]]; then
        log_info "运行 make distclean..."
        make distclean 2>/dev/null || make clean 2>/dev/null || true
    fi
    
    cd "$PROJECT_ROOT"
    log_info "PLuTo清理完成"
}

clean_llvm() {
    log_info "清理LLVM构建产物..."
    
    if [[ -d "$LLVM_BUILD_DIR" ]]; then
        log_info "删除 $LLVM_BUILD_DIR ..."
        rm -rf "$LLVM_BUILD_DIR"
        log_info "LLVM构建目录已删除"
    else
        log_warn "LLVM构建目录不存在: $LLVM_BUILD_DIR"
    fi
}

clean_mlir() {
    log_info "清理mlir-clang构建产物..."
    
    local MLIR_BUILD_DIR="$MLIR_CLANG_DIR/build"
    if [[ -d "$MLIR_BUILD_DIR" ]]; then
        log_info "删除 $MLIR_BUILD_DIR ..."
        rm -rf "$MLIR_BUILD_DIR"
        log_info "mlir-clang构建目录已删除"
    else
        log_warn "mlir-clang构建目录不存在: $MLIR_BUILD_DIR"
    fi
}

clean_rf() {
    log_info "清理RF_CGRAMap构建产物..."
    
    local RF_BUILD_DIR="$RF_CGRAMAP_DIR/build"
    if [[ -d "$RF_BUILD_DIR" ]]; then
        log_info "删除 $RF_BUILD_DIR ..."
        rm -rf "$RF_BUILD_DIR"
    fi
    
    # 也清理安装在主构建目录中的RF_CGRAMap
    if [[ -d "$BUILD_DIR/RF_CGRAMap" ]]; then
        log_info "删除 $BUILD_DIR/RF_CGRAMap ..."
        rm -rf "$BUILD_DIR/RF_CGRAMap"
    fi
    
    log_info "RF_CGRAMap清理完成"
}

clean_build() {
    log_info "清理主项目构建目录..."
    
    if [[ -d "$BUILD_DIR" ]]; then
        log_info "删除 $BUILD_DIR ..."
        rm -rf "$BUILD_DIR"
        log_info "主项目构建目录已删除"
    else
        log_warn "主项目构建目录不存在: $BUILD_DIR"
    fi
}

clean_examples() {
    log_info "清理example目录生成文件..."
    
    local EXAMPLE_DIR="$PROJECT_ROOT/example"
    if [[ ! -d "$EXAMPLE_DIR" ]]; then
        log_warn "example目录不存在"
        return 0
    fi
    
    cd "$EXAMPLE_DIR"
    
    # 清理各种生成的文件，保留 .c 和 .h
    log_info "清理 *.out, *.txt, *.ll, *.mlir, *.cloog 等生成文件..."
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
    log_info "example清理完成"
}

clean_all() {
    log_warn "即将清理所有构建产物和生成文件！"
    log_warn "这将删除以下内容:"
    echo "  - $BUILD_DIR"
    echo "  - $LLVM_BUILD_DIR"
    echo "  - $MLIR_CLANG_DIR/build"
    echo "  - PLuTo构建产物"
    echo "  - RF_CGRAMap构建产物"
    echo "  - example目录生成文件"
    
    if [[ "$AUTO_YES" == false ]]; then
        read -p "确认继续? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "取消清理操作"
            return 0
        fi
    fi
    
    clean_build
    clean_pluto
    clean_llvm
    clean_mlir
    clean_rf
    clean_examples
    
    # 删除生成的环境变量文件
    if [[ -f "$PROJECT_ROOT/env.sh" ]]; then
        log_info "删除 env.sh ..."
        rm -f "$PROJECT_ROOT/env.sh"
    fi
    
    log_info "========================================"
    log_info "清理完成！"
    log_info "========================================"
}

main() {
    # 默认值
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

    # 解析命令行参数
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
                log_error "未知选项: $1"
                usage
                exit 1
                ;;
        esac
    done

    # 如果是清理模式，执行清理后退出
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

    log_info "开始编译RfCgraTrans项目..."
    log_info "项目根目录: $PROJECT_ROOT"

    # 检查依赖
    if [[ "$SKIP_DEPS" == false ]]; then
        check_dependencies || {
            log_warn "依赖检查未通过，请手动安装依赖后重新运行脚本"
            if [[ "$AUTO_YES" == false ]]; then
                read -p "是否继续? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            else
                log_info "自动继续..."
            fi
        }
    else
        log_info "跳过依赖检查"
    fi

    # 编译PLuTo
    if [[ "$SKIP_PLUTO" == false ]]; then
        if [[ "$PREBUILD_EXTERNAL" == true ]]; then
            build_pluto || {
                log_error "编译PLuTo失败，中止"
                exit 1
            }
        else
            log_info "PLuTo由ExternalProject在主项目编译阶段自动构建，跳过预编译"
        fi
    else
        log_info "跳过PLuTo编译"
    fi

    # 编译mlir-clang
    if [[ "$SKIP_MLIR" == false ]]; then
        build_mlir_clang || {
            log_error "编译mlir-clang失败，中止"
            exit 1
        }
    else
        log_info "跳过mlir-clang编译"
    fi

    # 编译LLVM
    if [[ "$SKIP_LLVM" == false ]]; then
        build_llvm || {
            log_error "编译LLVM失败，中止"
            exit 1
        }
    else
        log_info "跳过LLVM编译"
    fi

    # 编译RF_CGRAMap子模块
    if [[ "$SKIP_RF" == false ]]; then
        if [[ "$PREBUILD_EXTERNAL" == true ]]; then
            build_rf_cgramap || {
                log_warn "编译RF_CGRAMap失败，但继续主项目编译"
            }
        else
            log_info "RF_CGRAMap由ExternalProject在主项目编译阶段自动构建，跳过预编译"
        fi
    else
        log_info "跳过RF_CGRAMap编译"
    fi

    # 编译主项目
    if [[ "$SKIP_PROJECT" == false ]]; then
        build_project || {
            log_error "编译主项目失败"
            exit 1
        }
    else
        log_info "跳过主项目编译"
    fi

    log_info "生成环境变量配置文件..."
    ENV_FILE="$PROJECT_ROOT/env.sh"
    cat > "$ENV_FILE" << 'EOF'
#!/bin/bash
# RfCgraTrans 环境变量配置
# 使用: source env.sh

# 检查是否被source而不是直接执行
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "错误: 请使用 'source env.sh' 或 '. env.sh' 来执行此脚本"
    echo "直接运行不会设置当前shell的环境变量"
    exit 1
fi

# 计算项目根目录 - 纯shell实现，不依赖外部命令
_script="${BASH_SOURCE[0]}"
# 获取脚本所在目录
if [[ "$_script" == */* ]]; then
    # 如果路径包含/，使用参数扩展获取目录部分
    _dir="${_script%/*}"
    # 切换到目录并获取绝对路径
    if cd "$_dir" 2>/dev/null; then
        export PROJECT_ROOT="$PWD"
        cd - >/dev/null 2>&1
    else
        # 如果目录不可访问，使用当前目录
        export PROJECT_ROOT="$PWD"
    fi
else
    # 如果路径不包含/，脚本在当前目录
    export PROJECT_ROOT="$PWD"
fi

export BUILD="$PROJECT_ROOT/llvm/build"
export LD_LIBRARY_PATH="$PROJECT_ROOT/build/RF_CGRAMap/lib:$PROJECT_ROOT/build/pluto/lib:$LD_LIBRARY_PATH"

# 设置PATH包含所有可能的二进制目录
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
    echo "警告: 未找到任何二进制目录，PATH未修改"
fi

# 清理临时变量
unset _script _dir _bin_dirs _new_path

# 检查路径是否存在
if [[ ! -d "$BUILD" ]]; then
    echo "警告: LLVM构建目录不存在: $BUILD"
    echo "请确保已成功编译LLVM"
fi

if [[ ! -d "$PROJECT_ROOT/build/pluto/lib" ]]; then
    echo "警告: PLuTo库目录不存在"
fi

if [[ ! -d "$PROJECT_ROOT/build/RF_CGRAMap/lib" ]]; then
    echo "警告: RF_CGRAMap库目录不存在"
fi

echo "环境变量已设置:"
echo "  PROJECT_ROOT: $PROJECT_ROOT"
echo "  BUILD: $BUILD"
echo "  LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "  PATH: $PATH"
EOF

    chmod +x "$ENV_FILE"
    log_info "环境配置文件已生成: $ENV_FILE"
    log_info "使用方法: source $ENV_FILE"

    log_info "========================================"
    log_info "编译完成！"
    log_info "========================================"
    log_info "编译结果位于: $BUILD_DIR"
    log_info "已生成环境变量配置文件 env.sh"
    log_info "请使用以下命令设置环境变量:"
    echo "source $PROJECT_ROOT/env.sh"
    log_info "要运行示例，请执行:"
    echo "cd example && ./run.sh"
    log_info "========================================"
}

# 运行主函数
main "$@"