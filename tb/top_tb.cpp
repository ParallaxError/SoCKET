#include <iostream>
#include <fstream>
#include <vector>
#include <algorithm>
#include <cstring>

#include "Vtop_tb.h"
#include "verilated.h"
#include "verilated_fst_c.h"

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

     // Write PPM output
    std::ofstream out("out.ppm", std::ios::binary);
    out << "P6\n" << PIXELS << " " << LINES << "\n255\n";
    out.write((const char*)framebuffer, sizeof(framebuffer));
    out.close();

    std::cout << "Simulation finished after " << main_time << " time units. Image written to out.ppm\n";

    delete tb;
#if VM_TRACE
    delete tfp;
#endif // VM_TRACE
    return 0;
}

extern "C" void writescreen(int R, int G, int B, int x, int y)
{
    if (x < 0 || x >= PIXELS || y < 0 || y >= LINES) return;

    int idx = (y * PIXELS + x) * 3;

    framebuffer[idx + 0] = std::min(255, std::max(0, R));
    framebuffer[idx + 1] = std::min(255, std::max(0, G));
    framebuffer[idx + 2] = std::min(255, std::max(0, B));
}
