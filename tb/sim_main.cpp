// Minimal Verilator main for the self-checking testbenches (built with
// --prefix Vtop). Runs until $finish and writes coverage.dat in the cwd.
// A custom main is used because Verilator 5.020's --binary main does not
// write coverage data.
#include <memory>
#include "verilated.h"
#include "verilated_cov.h"
#include "Vtop.h"

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> ctx{new VerilatedContext};
    ctx->commandArgs(argc, argv);
    const std::unique_ptr<Vtop> top{new Vtop{ctx.get(), "TOP"}};
    while (!ctx->gotFinish()) {
        top->eval();
        if (!top->eventsPending()) break;
        ctx->time(top->nextTimeSlot());
    }
    top->final();
    ctx->coveragep()->write("coverage.dat");
    return ctx->gotFinish() ? 0 : 1;
}
