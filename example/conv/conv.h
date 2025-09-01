#ifndef _CONV_GEMM_H
#define _CONV_GEMM_H

/* 默认使用超大数据集，可通过编译选项覆盖（如 -DMINI_DATASET） */
#if !defined(MINI_DATASET) && !defined(SMALL_DATASET) && !defined(MEDIUM_DATASET) && !defined(LARGE_DATASET) && !defined(EXTRALARGE_DATASET)
#define EXTRALARGE_DATASET
#endif

/* 未定义问题规模时，根据数据集类型定义默认值 */
#if !defined(NIMG) && !defined(NIFM) && !defined(NOFM) && !defined(IFH) && !defined(IFW) && \
    !defined(KH) && !defined(KW) && !defined(OFH) && !defined(OFW) && !defined(STRIDE_H) && \
    !defined(STRIDE_W) && !defined(GEMM_BLOCK)

/* 迷你数据集（用于快速测试） */
#ifdef MINI_DATASET
#define NIMG 1         /* 图像数量 */
#define NIFM 16        /* 输入通道数（需为GEMM_BLOCK的整数倍） */
#define NOFM 16        /* 输出通道数（需为GEMM_BLOCK的整数倍） */
#define IFH 16         /* 输入特征图高度 */
#define IFW 16         /* 输入特征图宽度 */
#define KH 3           /* 卷积核高度 */
#define KW 3           /* 卷积核宽度 */
#define OFH 8          /* 输出特征图高度 = (IFH - KH)/STRIDE_H + 1 */
#define OFW 8          /* 输出特征图宽度 = (IFW - KW)/STRIDE_W + 1 */
#define STRIDE_H 2     /* 高度方向步长 */
#define STRIDE_W 2     /* 宽度方向步长 */
#define GEMM_BLOCK 4   /* GEMM分块大小 */
#endif

/* 小数据集 */
#ifdef SMALL_DATASET
#define NIMG 2
#define NIFM 32
#define NOFM 32
#define IFH 32
#define IFW 32
#define KH 3
#define KW 3
#define OFH 16
#define OFW 16
#define STRIDE_H 2
#define STRIDE_W 2
#define GEMM_BLOCK 8
#endif

/* 中数据集 */
#ifdef MEDIUM_DATASET
#define NIMG 4
#define NIFM 64
#define NOFM 64
#define IFH 64
#define IFW 64
#define KH 3
#define KW 3
#define OFH 32
#define OFW 32
#define STRIDE_H 2
#define STRIDE_W 2
#define GEMM_BLOCK 16
#endif

/* 大数据集 */
#ifdef LARGE_DATASET
#define NIMG 8
#define NIFM 128
#define NOFM 128
#define IFH 128
#define IFW 128
#define KH 3
#define KW 3
#define OFH 64
#define OFW 64
#define STRIDE_H 2
#define STRIDE_W 2
#define GEMM_BLOCK 32
#endif

/* 超大数据集 */
#ifdef EXTRALARGE_DATASET
#define NIMG 16
#define NIFM 256
#define NOFM 256
#define IFH 256
#define IFW 256
#define KH 3
#define KW 3
#define OFH 128
#define OFW 128
#define STRIDE_H 2
#define STRIDE_W 2
#define GEMM_BLOCK 64
#endif

#endif /* 问题规模定义结束 */

/* 循环边界绑定（适配PolyBench宏） */
#define _PB_NIMG POLYBENCH_LOOP_BOUND(NIMG, nImg)
#define _PB_NIFM POLYBENCH_LOOP_BOUND(NIFM, nIfm)
#define _PB_NOFM POLYBENCH_LOOP_BOUND(NOFM, nOfm)
#define _PB_IFH POLYBENCH_LOOP_BOUND(IFH, ifh)
#define _PB_IFW POLYBENCH_LOOP_BOUND(IFW, ifw)
#define _PB_KH POLYBENCH_LOOP_BOUND(KH, kh)
#define _PB_KW POLYBENCH_LOOP_BOUND(KW, kw)
#define _PB_OFH POLYBENCH_LOOP_BOUND(OFH, ofh)
#define _PB_OFW POLYBENCH_LOOP_BOUND(OFW, ofw)
#define _PB_STRIDE_H POLYBENCH_LOOP_BOUND(STRIDE_H, STRIDE_H)
#define _PB_STRIDE_W POLYBENCH_LOOP_BOUND(STRIDE_W, STRIDE_W)
#define _PB_GEMM_BLOCK POLYBENCH_LOOP_BOUND(GEMM_BLOCK, GEMM_BLOCK)

/* 数据类型配置（默认双精度浮点，可通过编译选项切换） */
#if !defined(DATA_TYPE_IS_INT) && !defined(DATA_TYPE_IS_FLOAT) && !defined(DATA_TYPE_IS_DOUBLE)
#define DATA_TYPE_IS_DOUBLE
#endif

#ifdef DATA_TYPE_IS_INT
#define DATA_TYPE int
#define DATA_PRINTF_MODIFIER "%d "
#define SCALAR_VAL(x) (x)
#endif

#ifdef DATA_TYPE_IS_FLOAT
#define DATA_TYPE float
#define DATA_PRINTF_MODIFIER "%0.2f "
#define SCALAR_VAL(x) (x##f)
#define SQRT_FUN(x) sqrtf(x)
#define EXP_FUN(x) expf(x)
#define POW_FUN(x,y) powf(x,y)
#endif

#ifdef DATA_TYPE_IS_DOUBLE
#define DATA_TYPE double
#define DATA_PRINTF_MODIFIER "%0.2lf "
#define SCALAR_VAL(x) (x)
#define SQRT_FUN(x) sqrt(x)
#define EXP_FUN(x) exp(x)
#define POW_FUN(x,y) pow(x,y)
#endif

#endif /* _CONV_GEMM_H */
    