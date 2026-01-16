/*
 * @file /src/main.cpp
 * @brief
 * Entrypoint and main execution for the GPU model.
 * Reads in the input vertex data file specified as the first command line argument and dumps
 * the expected framestore and debug information to a file to compare to the RTL implementation.
 * 
 * -----
 */

// Includes
#include <iostream>
#include <fstream>

#include "framestore.h"
#include "fixed_point.h"
#include "gpu.h"

int main(int argc, char* argv[])
{
    Framestore framestore(640, 480);
    GPU gpu(framestore);

    // Read first input file
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <input_vertex_file>\n";
        return 1;
    }

    std::ifstream inputFile(argv[1]);
    if (!inputFile.is_open()) {
        std::cerr << "Failed to open " << argv[1] << "\n";
        return 1;
    }

    // First line: number of vertices
    int numVertices;
    inputFile >> numVertices;

    // First 4 lines, 4 doubles each for transformation matrix
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            double val;
            inputFile >> val;
            gpu.transformationMatrix.m[i][j] = FixedPoint<11, 9>(val);
        }
    }

    // Read vertices
    for (int i = 0; i < numVertices; i++) {
        double x, y, z;
        int r, g, b;
        inputFile >> x >> y >> z >> r >> g >> b;
        vertex_t vertex;
        vertex.x = FixedPoint<11, 9>(x);
        vertex.y = FixedPoint<11, 9>(y);
        vertex.z = FixedPoint<11, 9>(z);
        vertex.r = static_cast<uint8_t>(r);
        vertex.g = static_cast<uint8_t>(g);
        vertex.b = static_cast<uint8_t>(b);

        gpu.inputVertex(vertex);
    }

    // Dump framestore contents
    framestore.dumpAsBitmap("output.bmp");
    
    return 0;
}