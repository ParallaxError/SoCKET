/*
 * @file /src/framestore.h
 * @brief
 * Header file for the framestore class which exposes methods to read and write to a virtual framestore used in the 
 * GPU model.
 * 
 * The framestore is the ultimate output for the model that holds the final pixel values and debug
 * information after processing the input vertex data. Its contents will be compared to the RTL output.
 * 
 * -----
 */

#ifndef FRAMESTORE_H
#define FRAMESTORE_H

// Includes
#include <vector>
#include <string>

/**
 * @struct pixel_t
 * Represents a single pixel in RGB format.
 */
struct pixel_t
{
    unsigned char r;
    unsigned char g;
    unsigned char b;
};

/**
 * @class Framestore
 * Represents a virtual framestore for the GPU model.
 * 
 * Provides methods to read and write pixel data as well as debug information.
 * Also includes methods to dump the framestore contents to a file for comparison with RTL output.
 */
class Framestore
{
public:
    Framestore(int width, int height);
    ~Framestore();

    void writePixel(int x, int y, const pixel_t& pixel);
    pixel_t readPixel(int x, int y) const;
    void setTriangleIndex(int x, int y, int triangleIndex);
    int getTriangleIndex(int x, int y) const;

    // Dump the relevant framestore data to use for RTL comparison to a file
    void dumpGoldenData(const std::string& filename) const;

    // Dump the framestore contents as a bitmap image file
    void dumpAsBitmap(const std::string& filename) const;

    int width;
    int height;
private:
    // 2D vector to hold pixel data
    std::vector<std::vector<pixel_t>> pixel_data;

    // 2D vector containing the indices of which triangle drew each pixel
    std::vector<std::vector<int>> triangle_indices;
};

#endif // FRAMESTORE_H