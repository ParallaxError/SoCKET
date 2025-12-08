#include <iostream>
#include <fstream>
#include <vector>
#include <algorithm>
#include <cstring>

#include "Vtop_tb.h"
#include "verilated.h"
#include "verilated_fst_c.h"

#include "bitmap/bitmap.h"

#define PIXELS 640 /* screen width  */
#define LINES  480 /* screen height */

unsigned char framebuffer[PIXELS * LINES * 3];

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Clear framebuffer
    std::fill(framebuffer, framebuffer + sizeof(framebuffer), 0);

    // Create the design instance
    Vtop_tb* tb = new Vtop_tb;
#if VM_TRACE
    Verilated::traceEverOn(true);

    VerilatedFstC* tfp = new VerilatedFstC;
    tb->trace(tfp, 99);       // 99 = all levels of hierarchy
    tfp->open("wave/top_tb.fst");
#endif // VM_TRACE

    // Run until $finish is called
    while (!Verilated::gotFinish()) {
        tb->eval();
        if (main_time % 100000 == 0) {
            std::cout << "Simulation time: " << main_time << "\n";
        }
#if VM_TRACE
        tfp->dump(main_time);  // dump signals
#endif // VM_TRACE
        main_time++;
    }

     // Write BMP output
    writeBitmapFile("out.bmp", framebuffer);

    std::cout << "Simulation finished after " << main_time << " time units. Image written to out.bmp\n";

    delete tb;
#if VM_TRACE
    delete tfp;
#endif // VM_TRACE
    return 0;
}

extern "C" void writescreen(int R, int G, int B, int x, int y)
{
    if (x < 0 || x >= PIXELS || y < 0 || y >= LINES) return;

    // Invert y since (0, 0) in BMP is bottom-left
    int idx = ((BMP_HEIGHT - 1 - y) * PIXELS + x) * 3;

    framebuffer[idx + 0] = std::min(255, std::max(0, B << 3));
    framebuffer[idx + 1] = std::min(255, std::max(0, G << 2));
    framebuffer[idx + 2] = std::min(255, std::max(0, R << 3));
}
