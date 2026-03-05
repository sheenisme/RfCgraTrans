
#!/usr/bin/env bash
# set -o errexit
# set -o pipefail
# set -o nounset

# 如果被 sh/dash 调起，自动切换到 bash 执行，避免语法不兼容
if [ -z "${BASH_VERSION:-}" ] && [ -z "${ZSH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

# export PATH=$PROJECT_ROOT/mlir-clang/build/bin:$PROJECT_ROOT/RfCgraTrans/build/bin:$PROJECT_ROOT/RfCgraTrans/pluto:$PROJECT_ROOT/polygeist/build/bin:$PATH
export C_INCLUDE_PATH=$PROJECT_ROOT/mlir-clang/build/projects/openmp/runtime/src
export LD_LIBRARY_PATH=$PROJECT_ROOT/RfCgraTrans/build/pluto/lib:$PROJECT_ROOT/mlir-clang/build/lib:$PROJECT_ROOT/RfCgraTrans/glpk/glpk-5.0/src:$LD_LIBRARY_PATH
stdinclude="$PROJECT_ROOT/mlir-clang/llvm/../clang/lib/Headers"
CFLAGS="-march=native -I $PROJECT_ROOT/example/utilities -I $stdinclude -D POLYBENCH_TIME -D POLYBENCH_NO_FLUSH_CACHE -D EXTRALARGE_DATASET "

TOOLS="RfCgraTrans"
BASE="$(cd "$(dirname "$0")" && pwd)"
dirList=(2mm 3mm atax gemm gemver gesummv jacobi-1d jacobi-2d mvt bicg advect-3d fdtd-2d)

usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  --clean        只执行清理，不运行测试"
    echo "  --run          只运行测试，不清理"
    echo ""
    echo "默认行为: 先清理再运行测试"
}

clean_examples() {
    echo "========================================"
    echo "开始清理example目录生成文件..."
    echo "========================================"
    
    cd "$BASE" || exit 1

    # 使用find清理各种生成的文件，保留 .c 和 .h
    echo "使用find清理通用生成文件..."
    find . -type f \( \
        -name "*.out" -o \
        -name "*.txt" -o \
        -name "*.ll" -o \
        -name "*.mlir" -o \
        -name "*.cloog" -o \
        -name "*.pluto.c" -o \
        -name "*.plutopar.c" \
    \) -delete 2>/dev/null || true
    
    # 针对每个测试目录进行详细清理
    for dir in "${dirList[@]}"; 
    do
        if [[ ! -d "$BASE/$dir" ]]; then
            echo "警告: 目录不存在: $dir，跳过"
            continue
        fi
        
        echo "清理目录: $dir"

        # 使用 find 避免 zsh 的 nomatch 问题（未匹配通配符直接报错）
        find "$BASE/$dir" -maxdepth 1 -type f \( \
            -name "$dir.*.RfCgraTrans.out.mlir" -o \
            -name "*.cloog" -o \
            -name "DFGInformation.out" -o \
            -name "ScheduleInformation.out" -o \
            -name "unrollInformation.out" -o \
            -name "MapInformation.out" -o \
            -name "min_dependence_distance_schedule.out" -o \
            -name "AfterScheduleDFGInformation.out" -o \
            -name "Schedule*.out" -o \
            -name "map*.txt" -o \
            -name "simpleSchedule*.out" -o \
            -name "*.ll" -o \
            -name "*.mlir" -o \
            -name "*.pluto*" \
        \) -delete 2>/dev/null || true
    done
    
    cd "$BASE"
    echo "========================================"
    echo "清理完成！"
    echo "========================================"
}

run()
{ 
  TOOL="$1"
  TEST="$2"
  OUT=$TEST.$TOOL.ll

  case $TOOL in

    mlir-clang)
      mlir-clang $CFLAGS -emit-llvm $TEST.c -o $OUT
      ;;

    pluto)
      if [[ $2 == "adi" ]]
      then
        return
      fi
      # NOTE: in recent version pluto use --tile and --parallel as def.
      polycc --silent --tile --noparallel --noprevector --nounrolljam $TEST.c -o $TEST.$TOOL.c &> /dev/null
      clang $CFLAGS -O3 -S -emit-llvm $TEST.$TOOL.c -o - -fno-vectorize -fno-unroll-loops | sed 's/llvm.loop.unroll.disable//g' > $OUT
      ;;

    RfCgraTrans)
      mlir-clang $CFLAGS $TEST.c -o $TEST.$TOOL.in.mlir
      # RfCgraTrans-opt -reg2mem \
      # -insert-redundant-load \
      # -extract-scop-stmt \
      # -canonicalize \
      # -pluto-opt="dump-clast-after-pluto=$TEST.$TOOL.cloog" \
      # -canonicalize $TEST.$TOOL.in.mlir 2>/dev/null > $TEST.$TOOL.out.mlir
      RfCgraTrans-opt -reg2mem \
      -insert-redundant-load \
      -extract-scop-stmt \
      -canonicalize \
      -pluto-opt="dump-clast-after-pluto=$TEST.$TOOL.cloog" \
      -canonicalize $TEST.$TOOL.in.mlir 2>/dev/null > $TEST.$TOOL.out.mlir

      mlir-opt -lower-affine -convert-scf-to-std -canonicalize -convert-std-to-llvm $TEST.$TOOL.out.mlir > $OUT 2>&1
      #mlir-translate -mlir-to-llvmir > $OUT
      ;;

    *)
      echo "Illegal tool $TOOL"
      exit 1
      ;;
  esac	
}

run_tests() {
    echo "========================================"
    echo "开始运行测试..."
    echo "========================================"
    
    for dir in "${dirList[@]}"; 
    do
        if [[ ! -d "$BASE/$dir" ]]; then
            echo "警告: 目录不存在: $dir，跳过"
            continue
        fi
        
        echo "----------------------------------------"
        echo "运行测试: $dir"
        echo "----------------------------------------"
        cd "$BASE/$dir" || exit 1
        
        for t in $TOOLS; 
        do
            echo "使用工具: $t"
            run $t $dir
        done
    done
    
    cd "$BASE"
    echo "========================================"
    echo "测试运行完成！"
    echo "========================================"
}

# 主程序
main() {
    DO_CLEAN=true
    DO_RUN=true
    
    # 解析命令行参数
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            --clean)
                DO_CLEAN=true
                DO_RUN=false
                shift
                ;;
            --run)
                DO_CLEAN=false
                DO_RUN=true
                shift
                ;;
            *)
                echo "未知选项: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # 执行操作
    if [ "$DO_CLEAN" = true ]; then
        clean_examples
    fi
    
    if [ "$DO_RUN" = true ]; then
        run_tests
    fi
}

# 执行主函数
main "$@"
