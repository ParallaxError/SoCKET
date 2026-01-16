/*
 * @file /src/bitmap/bitmap.cpp
 * @brief
 * Definitions for bitmap writing utilities to dump GPU output to a file.
 * 
 * -----
 */


#include "bitmap.h"

void writeBitmapFile(std::string filename, const uint8_t* framestore) 
{
    // Default values should be good
    BmpHeader bmpHeader;
    BmpInfoHeader bmpInfoHeader;

    std::ofstream fileOutputStream(filename, std::ios::out | std::ios::binary);
    if (!fileOutputStream) {
        throw std::ios_base::failure("Failed to open file for writing: " + filename);
    }

    // Write headers
    fileOutputStream.write(reinterpret_cast<const char*>(&bmpHeader), sizeof(BmpHeader));
    fileOutputStream.write(reinterpret_cast<const char*>(&bmpInfoHeader), sizeof(BmpInfoHeader));
    // Write pixel data
    fileOutputStream.write(reinterpret_cast<const char*>(framestore), BMP_WIDTH * BMP_HEIGHT * COLOUR_DEPTH);
}