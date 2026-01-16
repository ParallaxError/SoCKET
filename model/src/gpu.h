/*
 * @file /src/gpu.h
 * @brief
 * The main GPU model class header file.
 * Simply exposes a single method to take a vertex as input.
 * Once three vertices have been input, the triangle is rasterized and the framestore updated.
 * 
 * -----
 */

#ifndef GPU_H
#define GPU_H

// Includes
#include <array>

#include "framestore.h"
#include "fixed_point.h"

/**
 * @struct vertex_t
 * Represents a single vertex with position and color attributes.
 */
struct vertex_t
{
    FixedPoint<11, 9> x;
    FixedPoint<11, 9> y;
    FixedPoint<11, 9> z;
    uint8_t r;
    uint8_t g;
    uint8_t b;
};

/**
 * @struct triangle_t
 * Represents a triangle composed of three vertices.
 */
struct triangle_t
{
    vertex_t v0;
    vertex_t v1;
    vertex_t v2;

    // Debug
    int triangleIndex;
};

/**
 * @struct matrix_t
 * Represents a 4x4 transformation matrix.
 */
struct matrix_t
{
    FixedPoint<11, 9> m[4][4];
};

/**
 * @class GPU
 * Represents the main GPU model.
 * 
 * Provides a method to input vertices and handles triangle rasterization and framestore updates.
 */
class GPU
{
public:
    GPU(Framestore& framestore);
    ~GPU();

    void inputVertex(const vertex_t& vertex);
    matrix_t transformationMatrix;
private:
    Framestore& framestore;
    std::array<vertex_t, 2> vertexBuffer;
    int triangleCount;
    int vertexIndex;

    vertex_t& transformVertex(vertex_t& vertex);
    void rasterizeTriangle(const triangle_t& triangle);
};

#endif // GPU_H