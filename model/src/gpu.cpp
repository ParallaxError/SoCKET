/*
 * @file /src/gpu.cpp
 * @brief
 * Implementation for the main GPU model.
 * 
 * -----
 */

// Includes
#include <algorithm>
#include <iostream>
#include "gpu.h"

GPU::GPU(Framestore& framestore)
    : transformationMatrix(), framestore(framestore), triangleCount(0), vertexIndex(0)
{
}

GPU::~GPU()
{
}

// Input a vertex to the GPU
void GPU::inputVertex(const vertex_t& vertex)
{
    // If we have less than 2 vertices buffered, just store the vertex
    if (vertexIndex < 2) {
        vertexBuffer[vertexIndex] = vertex;
        vertexIndex++;
    } else {
        // We have 2 vertices buffered, so we can form a triangle
        triangle_t triangle;
        triangle.v0 = transformVertex(vertexBuffer[0]);
        triangle.v1 = transformVertex(vertexBuffer[1]);
        // Quick copy, ew
        vertex_t vert = vertex;
        triangle.v2 = transformVertex(vert);
        triangle.triangleIndex = triangleCount;
        // Rasterize the triangle
        rasterizeTriangle(triangle);

        // Reset vertex buffer
        vertexIndex = 0;
        triangleCount++;
    }
}

// Multiply a vertex by the transformation matrix and perform perspective division
vertex_t& GPU::transformVertex(vertex_t& vertex)
{
    // First multiply by transformation matrix
    FixedPoint<11, 9> x = transformationMatrix.m[0][0] * vertex.x +
                           transformationMatrix.m[0][1] * vertex.y +
                           transformationMatrix.m[0][2] * vertex.z +
                           transformationMatrix.m[0][3];
    FixedPoint<11, 9> y = transformationMatrix.m[1][0] * vertex.x +
                           transformationMatrix.m[1][1] * vertex.y +
                           transformationMatrix.m[1][2] * vertex.z +
                           transformationMatrix.m[1][3];
    FixedPoint<11, 9> z = transformationMatrix.m[2][0] * vertex.x +
                           transformationMatrix.m[2][1] * vertex.y +
                           transformationMatrix.m[2][2] * vertex.z +
                           transformationMatrix.m[2][3];
    FixedPoint<11, 9> w = transformationMatrix.m[3][0] * vertex.x +
                           transformationMatrix.m[3][1] * vertex.y +
                           transformationMatrix.m[3][2] * vertex.z +
                           transformationMatrix.m[3][3];

    // Now perform perspective division
    vertex.x = x / w;
    vertex.y = y / w;
    vertex.z = z / w;

    // Multiply x and y by viewport dimensions, and invrt y
    vertex.x = vertex.x * FixedPoint<11, 9>(this->framestore.width);
    vertex.y = FixedPoint<11, 9>(this->framestore.height) - (vertex.y * FixedPoint<11, 9>(this->framestore.height));

    // Return transformed vertex
    return vertex;
}

FixedPoint<18, 18> edgeFunction(const vertex_t& a, const vertex_t& b, const FixedPoint<11, 9>& c_x, const FixedPoint<11, 9>& c_y)
{
    // Promote all to FixedPoint<18,18> for precision
    // In Verilog this is
    /*
    function automatic fixed_wide_t from_fixed(fixed_t f);
        fixed_wide_t w;
        localparam int SHIFT = FIXED_WIDE_FRAC - FIXED_FRAC;

        // Sign-extend the input fixed point value since the point is in a new position
        logic signed [FIXED_WIDE_WIDTH-1:0] ext;
        ext = {{(FIXED_WIDE_WIDTH-FIXED_WIDTH){f.value[FIXED_WIDTH-1]}}, f.value};

        w.value = ext <<< SHIFT;
        return w;
    endfunction
    */

    // TODO Magic
    constexpr int SHIFT = 18 - 9;
    int64_t ax_raw = (static_cast<int64_t>(a.x.value) << SHIFT);
    FixedPoint<18, 18> ax; ax.value = ax_raw;
    int64_t ay_raw = (static_cast<int64_t>(a.y.value) << SHIFT);
    FixedPoint<18, 18> ay; ay.value = ay_raw;
    int64_t bx_raw = (static_cast<int64_t>(b.x.value) << SHIFT);
    FixedPoint<18, 18> bx; bx.value = bx_raw;
    int64_t by_raw = (static_cast<int64_t>(b.y.value) << SHIFT);
    FixedPoint<18, 18> by; by.value = by_raw;
    int64_t cx_raw = (static_cast<int64_t>(c_x.value) << SHIFT);
    FixedPoint<18, 18> cx; cx.value = cx_raw;
    int64_t cy_raw = (static_cast<int64_t>(c_y.value) << SHIFT);
    FixedPoint<18, 18> cy; cy.value = cy_raw;

    return (cx - ax) * (by - ay) - (cy - ay) * (bx - ax);
}

// Rasterize a triangle and update the framestore
void GPU::rasterizeTriangle(const triangle_t& triangle)
{
    // Find bounding box
    int minX = std::min({triangle.v0.x.toDouble(), triangle.v1.x.toDouble(), triangle.v2.x.toDouble()});
    int maxX = std::max({triangle.v0.x.toDouble(), triangle.v1.x.toDouble(), triangle.v2.x.toDouble()});
    int minY = std::min({triangle.v0.y.toDouble(), triangle.v1.y.toDouble(), triangle.v2.y.toDouble()});
    int maxY = std::max({triangle.v0.y.toDouble(), triangle.v1.y.toDouble(), triangle.v2.y.toDouble()});

    // Iterate over bounding box, finding pixels inside the triangle
    for (int y = minY; y <= maxY; y++) {
        for (int x = minX; x <= maxX; x++) {
            // Check if the pixel is inside the triangle using edge functions
            FixedPoint<18, 18> w0 = edgeFunction(triangle.v1, triangle.v2, FixedPoint<11, 9>(x), FixedPoint<11, 9>(y));
            FixedPoint<18, 18> w1 = edgeFunction(triangle.v2, triangle.v0, FixedPoint<11, 9>(x), FixedPoint<11, 9>(y));
            FixedPoint<18, 18> w2 = edgeFunction(triangle.v0, triangle.v1, FixedPoint<11, 9>(x), FixedPoint<11, 9>(y));

            if (w0.toDouble() >= 0 && w1.toDouble() >= 0 && w2.toDouble() >= 0) {
                // Inside the triangle, write pixel to framestore
                pixel_t pixel;
                
                // Barycentric coordinates for color interpolation
                FixedPoint<18, 18> area = edgeFunction(triangle.v0, triangle.v1, triangle.v2.x, triangle.v2.y);
                FixedPoint<18, 18> lambda0 = w0 / area;
                FixedPoint<18, 18> lambda1 = w1 / area;
                FixedPoint<18, 18> lambda2 = w2 / area;

                pixel.r = static_cast<unsigned char>(lambda0.toDouble() * triangle.v0.r +
                                                    lambda1.toDouble() * triangle.v1.r +
                                                    lambda2.toDouble() * triangle.v2.r);
                pixel.g = static_cast<unsigned char>(lambda0.toDouble() * triangle.v0.g +
                                                    lambda1.toDouble() * triangle.v1.g +
                                                    lambda2.toDouble() * triangle.v2.g);
                pixel.b = static_cast<unsigned char>(lambda0.toDouble() * triangle.v0.b +
                                                    lambda1.toDouble() * triangle.v1.b +
                                                    lambda2.toDouble() * triangle.v2.b);

                // Truncate to 8 bit colour (3 3 2)
                pixel.r = (pixel.r >> 5) << 5;
                pixel.g = (pixel.g >> 5) << 5;
                pixel.b = (pixel.b >> 6) << 6;

                framestore.writePixel(x, y, pixel);
                framestore.setTriangleIndex(x, y, triangle.triangleIndex);
            }
        }
    }
}