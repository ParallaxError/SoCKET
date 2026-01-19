/*
 * @file /src/framestore.cpp
 * @brief
 * Implementation for the framestore class
 * 
 * -----
 */

// Includes
#include "framestore.h"
#include "bitmap/bitmap.h"

Framestore::Framestore(int width, int height)
    : width(width), height(height),
      pixel_data(height, std::vector<pixel_t>(width, {0, 0, 0})),
      triangle_indices(height, std::vector<int>(width, -1))
{
}

Framestore::~Framestore()
{
}

void Framestore::writePixel(int x, int y, const pixel_t& pixel)
{
    if (x >= 0 && x < width && y >= 0 && y < height) {
        pixel_data[height - 1 - y][x] = pixel;
    }
}

pixel_t Framestore::readPixel(int x, int y) const
{
    if (x >= 0 && x < width && y >= 0 && y < height) {
        return pixel_data[height - 1 - y][x];
    }
    
    throw std::out_of_range("Pixel coordinates out of bounds");
}

void Framestore::setTriangleIndex(int x, int y, int triangleIndex)
{
    if (x >= 0 && x < width && y >= 0 && y < height) {
        triangle_indices[height - 1 - y][x] = triangleIndex;
    }
}

int Framestore::getTriangleIndex(int x, int y) const
{
    if (x >= 0 && x < width && y >= 0 && y < height) {
        return triangle_indices[height - 1 - y][x];
    }
    
    throw std::out_of_range("Pixel coordinates out of bounds");
}

void Framestore::dumpGoldenData(const std::string& filename) const
{
    std::ofstream outfile(filename, std::ios::app);
    if (!outfile.is_open()) {
        throw std::runtime_error("Failed to open file for writing golden data");
    }

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const pixel_t& pixel = pixel_data[y][x];
            int triangleIndex = triangle_indices[y][x];
            outfile << x << " " << (height - 1 - y) << " "
                    << static_cast<int>(pixel.r) << " "
                    << static_cast<int>(pixel.g) << " "
                    << static_cast<int>(pixel.b) << " "
                    << triangleIndex << "\n";
        }
    }

    outfile.close();
}

void Framestore::dumpAsBitmap(const std::string& filename) const
{
    // Convert pixel data to raw RGB format
    std::vector<uint8_t> raw_framestore;
    raw_framestore.reserve(width * height * 3);
    
    for (const auto& row : pixel_data) {
        for (const auto& pixel : row) {
            raw_framestore.push_back(pixel.b);
            raw_framestore.push_back(pixel.g);
            raw_framestore.push_back(pixel.r);
        }
    }

    // Write bitmap file using utility function
    writeBitmapFile(filename, raw_framestore.data());
}