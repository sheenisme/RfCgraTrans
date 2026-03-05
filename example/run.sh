
#!/usr/bin/env bash
# set -o errexit
# set -o pipefail
# set -o nounset

# If bash or zsh is not detected, re-exec with bash
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
    echo "Usage: $0 [Options]"
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --clean        Only clean generated files, don't run tests"
    echo "  --run          Only run tests, don't clean (default)"
    echo ""
    echo "Default behavior: Clean and then run tests"
}

clean_examples() {
    echo "========================================"
    echo "Starting to clean generated files in example directory..."
    echo "========================================"
    
    cd "$BASE" || exit 1

    # Look for common generated file patterns in the entire example directory and delete them
    echo "Using find to clean common generated files..."
    find . -type f \( \
        -name "*.out" -o \
        -name "*.txt" -o \
        -name "*.ll" -o \
        -name "*.mlir" -o \
        -name "*.cloog" -o \
        -name "*.pluto.c" -o \
        -name "*.plutopar.c" \
    \) -delete 2>/dev/null || true
    
    # Look for specific generated files in each test directory and delete them
    for dir in "${dirList[@]}"; 
    do
        if [[ ! -d "$BASE/$dir" ]]; then
            echo "Warning: Directory does not exist: $dir, skipping"
            continue
        fi
        
        echo "Cleaning directory: $dir"

        # Use find to avoid zsh's nomatch issue (unmatched glob patterns cause errors)
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
    echo "Cleaning completed!"
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
      polycc --silent --tile --noparallel --noprevector --nounrolljam $TEST.c -o $TEST.$TOOL.c &> $TEST.$TOOL.log
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
      -canonicalize $TEST.$TOOL.in.mlir 2>$TEST.$TOOL.log > $TEST.$TOOL.out.mlir

      # mlir-opt -lower-affine -convert-scf-to-std -canonicalize -convert-std-to-llvm $TEST.$TOOL.out.mlir > $OUT 2>&1
      #mlir-translate -mlir-to-llvmir > $OUT
    
      # display latency
      latency=$(tail -1 $TEST.$TOOL.log | awk '{print $NF}')
      echo "Latency: $latency cycles"
      ;;

    *)
      echo "Illegal tool $TOOL"
      exit 1
      ;;
  esac	
}

run_tests() {
    echo "========================================"
    echo "Starting to run tests..."
    echo "========================================"
    
    for dir in "${dirList[@]}"; 
    do
        if [[ ! -d "$BASE/$dir" ]]; then
            echo "Warning: Directory does not exist: $dir, skipping"
            continue
        fi
        
        echo "----------------------------------------"
        echo "Running test: $dir"
        echo "----------------------------------------"
        cd "$BASE/$dir" || exit 1
        
        for t in $TOOLS; 
        do
            echo "Using tool: $t"
            run $t $dir
        done
    done
    
    cd "$BASE"
    echo "========================================"
    echo "Tests completed!"
    echo "========================================"
}

# Main function to parse arguments and execute actions
main() {
    DO_CLEAN=true
    DO_RUN=true
    
    # Parse command-line arguments
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
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Execute actions
    if [ "$DO_CLEAN" = true ]; then
        clean_examples
    fi
    
    if [ "$DO_RUN" = true ]; then
        run_tests
    fi
}

# Execute main function
main "$@"
