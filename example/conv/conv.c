/**
 * This version is adapted from PolyBench 3mm.c format
 *
 * Contact:
 *   Louis-Noel Pouchet <pouchet.ohio-state.edu>
 *   Tomofumi Yuki <tomofumi.yuki.fr>
 *
 * Web address: http://polybench.sourceforge.net
 */
/* conv_gemm.c: this file is part of PolyBench/C (adapted for GEMM-based Convolution) */

#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <math.h>

/* Include polybench common header. */
#include <polybench.h>

/* Include benchmark-specific header (需自行定义问题规模宏，如 nImg、nOfm 等) */
#include "conv_gemm.h"

/* 数组初始化：为输入(input)、滤波器(filter)初始化随机值，输出(output)初始化为0 */
static void init_array(int nImg, int nIfm, int nOfm, int ifh, int ifw, 
                       int kh, int kw, int ofh, int ofw, int GEMM_BLOCK,
                       DATA_TYPE POLYBENCH_6D(input, NIMG, NIFM_TILE, IFH, IFW, IFM_BLOCK, nImg, nIfm/GEMM_BLOCK, ifh, ifw, GEMM_BLOCK),
                       DATA_TYPE POLYBENCH_6D(filter, NOFM_TILE, NIFM_TILE, KH, KW, IFM_BLOCK, OFM_BLOCK, nOfm/GEMM_BLOCK, nIfm/GEMM_BLOCK, kh, kw, GEMM_BLOCK, GEMM_BLOCK),
                       DATA_TYPE POLYBENCH_5D(output, NIMG, NOFM_TILE, OFH, OFW, OFM_BLOCK, nImg, nOfm/GEMM_BLOCK, ofh, ofw, GEMM_BLOCK))
{
    int img, ifm_tile, ifm, i, j, ofm_tile, ofm, kj, ki;

    /* 初始化输入特征图 input: [img][ifm_tile][h][w][ifm] */
    for (img = 0; img < nImg; img++)
        for (ifm_tile = 0; ifm_tile < nIfm / GEMM_BLOCK; ifm_tile++)
            for (i = 0; i < ifh; i++)
                for (j = 0; j < ifw; j++)
                    for (ifm = 0; ifm < GEMM_BLOCK; ifm++)
                        input[img][ifm_tile][i][j][ifm] = (DATA_TYPE)((img * ifm + i * j + 1) % ifh) / (5.0 * ifh);

    /* 初始化滤波器 filter: [ofm_tile][ifm_tile][kj][ki][ifm][ofm] */
    for (ofm_tile = 0; ofm_tile < nOfm / GEMM_BLOCK; ofm_tile++)
        for (ifm_tile = 0; ifm_tile < nIfm / GEMM_BLOCK; ifm_tile++)
            for (kj = 0; kj < kh; kj++)
                for (ki = 0; ki < kw; ki++)
                    for (ifm = 0; ifm < GEMM_BLOCK; ifm++)
                        for (ofm = 0; ofm < GEMM_BLOCK; ofm++)
                            filter[ofm_tile][ifm_tile][kj][ki][ifm][ofm] = (DATA_TYPE)((ofm_tile * ifm_tile + kj * ki + 2) % kw) / (5.0 * kw);

    /* 初始化输出特征图 output 为 0 */
    for (img = 0; img < nImg; img++)
        for (ofm_tile = 0; ofm_tile < nOfm / GEMM_BLOCK; ofm_tile++)
            for (i = 0; i < ofh; i++)
                for (j = 0; j < ofw; j++)
                    for (ofm = 0; ofm < GEMM_BLOCK; ofm++)
                        output[img][ofm_tile][i][j][ofm] = SCALAR_VAL(0.0);
}

/* DCE 代码：扫描输出数组防止死代码消除，同时可验证结果正确性 */
static void print_array(int nImg, int nOfm, int ofh, int ofw, int GEMM_BLOCK,
                        DATA_TYPE POLYBENCH_5D(output, NIMG, NOFM_TILE, OFH, OFW, OFM_BLOCK, nImg, nOfm/GEMM_BLOCK, ofh, ofw, GEMM_BLOCK))
{
    int img, ofm_tile, oj, oi, ofm;
    int count = 0;

    POLYBENCH_DUMP_START;
    POLYBENCH_DUMP_BEGIN("output");
    for (img = 0; img < nImg; img++)
        for (ofm_tile = 0; ofm_tile < nOfm / GEMM_BLOCK; ofm_tile++)
            for (oj = 0; oj < ofh; oj++)
                for (oi = 0; oi < ofw; oi++)
                    for (ofm = 0; ofm < GEMM_BLOCK; ofm++)
                    {
                        if (count % 20 == 0)  /* 每20个元素换行，保持格式整洁 */
                            fprintf(POLYBENCH_DUMP_TARGET, "\n");
                        fprintf(POLYBENCH_DUMP_TARGET, DATA_PRINTF_MODIFIER, output[img][ofm_tile][oj][oi][ofm]);
                        count++;
                    }
    POLYBENCH_DUMP_END("output");
    POLYBENCH_DUMP_FINISH;
}

/* 主计算内核：替换为指定的多层嵌套循环（含 GEMM 操作），整个函数会被计时 */
static void kernel_conv_gemm(int nImg, int nIfm, int nOfm, int ifh, int ifw, 
                             int kh, int kw, int ofh, int ofw, int STRIDE_H, int STRIDE_W, int GEMM_BLOCK,
                             DATA_TYPE POLYBENCH_5D(output, NIMG, NOFM_TILE, OFH, OFW, OFM_BLOCK, nImg, nOfm/GEMM_BLOCK, ofh, ofw, GEMM_BLOCK),
                             DATA_TYPE POLYBENCH_6D(input, NIMG, NIFM_TILE, IFH, IFW, IFM_BLOCK, nImg, nIfm/GEMM_BLOCK, ifh, ifw, GEMM_BLOCK),
                             DATA_TYPE POLYBENCH_6D(filter, NOFM_TILE, NIFM_TILE, KH, KW, IFM_BLOCK, OFM_BLOCK, nOfm/GEMM_BLOCK, nIfm/GEMM_BLOCK, kh, kw, GEMM_BLOCK, GEMM_BLOCK))
{
    int img, ofm_tile, ifm_tile, oj, ij, kj, ki, oi, ii, ofm, ifm;

#pragma scop  /* PolyBench 标记：内核计算区域开始（用于编译优化定位） */
    /* 核心循环：按 img -> ofm_tile -> ifm_tile -> 空间维度 -> GEMM 维度展开 */
    for (img = 0; img < _PB_NIMG; ++img) {
        for (ofm_tile = 0; ofm_tile < _PB_NOFM / _PB_GEMM_BLOCK; ++ofm_tile) {
            for (ifm_tile = 0; ifm_tile < _PB_NIFM / _PB_GEMM_BLOCK; ++ifm_tile) {
                for (oj = 0; oj < _PB_OFH; ++oj) {
                    ij = oj * _PB_STRIDE_H;  /* 输入特征图的高度维度坐标（步幅映射） */
                    for (kj = 0; kj < _PB_KH; ++kj) {  /* 滤波器高度维度遍历 */
                        for (ki = 0; ki < _PB_KW; ++ki) {  /* 滤波器宽度维度遍历 */

                            /* GEMM operation begins：GEMM 核心计算（输入-滤波器乘加） */
                            for (oi = 0; oi < _PB_OFW; ++oi) {
                                ii = oi * _PB_STRIDE_W;  /* 输入特征图的宽度维度坐标（步幅映射） */
                                for (ofm = 0; ofm < _PB_GEMM_BLOCK; ++ofm) {  /* 输出特征图通道块遍历 */
                                    for (ifm = 0; ifm < _PB_GEMM_BLOCK; ++ifm) {  /* 输入特征图通道块遍历 */
                                        /* 输出累加：output = output + filter * input（按维度匹配乘加） */
                                        output[img][ofm_tile][oj][oi][ofm] +=
                                            filter[ofm_tile][ifm_tile][kj][ki][ifm][ofm] * 
                                            input[img][ifm_tile][ij + kj][ii + ki][ifm];
                                    }
                                }
                            }
                            /* GEMM operation ends */

                        }
                    }
                }
            }
        }
    }
#pragma endscop  /* PolyBench 标记：内核计算区域结束 */
}

int main(int argc, char **argv)
{
    /* Retrieve problem size：从 conv_gemm.h 中获取预定义的问题规模宏 */
    int nImg = _PB_NIMG;    /* 图像数量 */
    int nIfm = _PB_NIFM;    /* 输入特征图通道数 */
    int nOfm = _PB_NOFM;    /* 输出特征图通道数 */
    int ifh = _PB_IFH;      /* 输入特征图高度 */
    int ifw = _PB_IFW;      /* 输入特征图宽度 */
    int kh = _PB_KH;        /* 滤波器高度 */
    int kw = _PB_KW;        /* 滤波器宽度 */
    int ofh = _PB_OFH;      /* 输出特征图高度 */
    int ofw = _PB_OFW;      /* 输出特征图宽度 */
    int STRIDE_H = _PB_STRIDE_H;  /* 高度方向步幅 */
    int STRIDE_W = _PB_STRIDE_W;  /* 宽度方向步幅 */
    int GEMM_BLOCK = _PB_GEMM_BLOCK;  /* GEMM 分块大小（通道维度分块） */

    /* Variable declaration/allocation：PolyBench 风格的多维数组声明（适配宏定义） */
    POLYBENCH_5D_ARRAY_DECL(output, DATA_TYPE, NIMG, NOFM_TILE, OFH, OFW, OFM_BLOCK, 
                            nImg, nOfm/GEMM_BLOCK, ofh, ofw, GEMM_BLOCK);
    POLYBENCH_6D_ARRAY_DECL(input, DATA_TYPE, NIMG, NIFM_TILE, IFH, IFW, IFM_BLOCK, 
                            nImg, nIfm/GEMM_BLOCK, ifh, ifw, GEMM_BLOCK);
    POLYBENCH_6D_ARRAY_DECL(filter, DATA_TYPE, NOFM_TILE, NIFM_TILE, KH, KW, IFM_BLOCK, OFM_BLOCK, 
                            nOfm/GEMM_BLOCK, nIfm/GEMM_BLOCK, kh, kw, GEMM_BLOCK, GEMM_BLOCK);

    /* Initialize array(s)：调用初始化函数，为输入和滤波器赋值 */
    init_array(nImg, nIfm, nOfm, ifh, ifw, kh, kw, ofh, ofw, GEMM_BLOCK,
               POLYBENCH_ARRAY(input),
               POLYBENCH_ARRAY(filter),
               POLYBENCH_ARRAY(output));

    /* Start timer：PolyBench 计时器启动（用于性能测试） */
    polybench_start_instruments;

    /* Run kernel：调用主计算内核（核心逻辑执行） */
    kernel_conv_gemm(nImg, nIfm, nOfm, ifh, ifw, kh, kw, ofh, ofw, STRIDE_H, STRIDE_W, GEMM_BLOCK,
                     POLYBENCH_ARRAY(output),
                     POLYBENCH_ARRAY(input),
                     POLYBENCH_ARRAY(filter));

    /* Stop and print timer：停止计时器并打印性能数据（如执行时间） */
    polybench_stop_instruments;
    polybench_print_instruments;

    /* Prevent dead-code elimination：打印输出数组，防止编译器优化掉计算逻辑 */
    polybench_prevent_dce(print_array(nImg, nOfm, ofh, ofw, GEMM_BLOCK, POLYBENCH_ARRAY(output)));

    /* Be clean：释放数组内存（PolyBench 宏定义的内存释放） */
    POLYBENCH_FREE_ARRAY(output);
    POLYBENCH_FREE_ARRAY(input);
    POLYBENCH_FREE_ARRAY(filter);

    return 0;
}