#include "RfCgraTrans/Transforms/PerfProfiling.h"

#include "mlir/Analysis/AffineAnalysis.h"
#include "mlir/Analysis/AffineStructures.h"
#include "mlir/Analysis/SliceAnalysis.h"
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/BlockAndValueMapping.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/Passes.h"
#include "mlir/Transforms/RegionUtils.h"
#include "mlir/Transforms/Utils.h"


using namespace mlir;
using namespace llvm;
using namespace RfCgraTrans;

namespace {

struct EvaluatePerfProfiling : public OpRewritePattern<FuncOp> {
  using OpRewritePattern<FuncOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(FuncOp op, PatternRewriter &rewriter) const override {
    errs() << "已经遍历该function: " << op.getName() << "\n";
    // 或者使用 mlir::emitRemark（需要指定位置，这里简单示例）
    // op.emitRemark("已经遍历该function");
    return failure();
  }
};

struct PerProfilingPass
    : public mlir::PassWrapper<PerProfilingPass, OperationPass<mlir::ModuleOp>> {
  void runOnOperation() override {
    MLIRContext *context = &getContext();

    RewritePatternSet patterns(context);
    patterns.add<EvaluatePerfProfiling>(context);

    if (failed(applyPatternsAndFoldGreedily(getOperation(), std::move(patterns))))
      signalPassFailure();
  }
};

}// namespace
void RfCgraTrans::registerPerProfilingPass() {
  PassRegistration<PerProfilingPass>(
      "select-solution", "select a optimized soluton from Pluto-based loop transformation.");
}