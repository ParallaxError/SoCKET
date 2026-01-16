/*
 * @file /src/bitmap/bitmap.h
 * @brief
 * Bitmap writing utilities to dump GPU output to a file.
 * Mostly from https://dev.to/muiz6/c-how-to-write-a-bitmap-image-from-scratch-1k6m
 * 
 * -----
 */

#ifndef TB_BITMAP_BITMAP_H
#define TB_BITMAP_BITMAP_H

// Includes
#include <cstdint>
#include <fstream>
#include <string>

constexpr uint32_t BMP_HEADER_SIZE = 54;

constexpr uint32_t BMP_WIDTH = 640;
constexpr uint32_t BMP_HEIGHT = 480;

constexpr uint32_t COLOUR_DEPTH = 3; // 1 byte per colour RGB

#pragma pack(push, 1)

/**
 * @brief Bitmap file header structure
 * 
 * @details Two characters for file magic, size of file, no reserved bytes, size of header
 */
struct BmpHeader {
    char bitmapSignatureBytes[2] = {'B', 'M'};
    uint32_t sizeOfBitmapFile = BMP_HEADER_SIZE + (BMP_WIDTH * BMP_HEIGHT * COLOUR_DEPTH);
    uint32_t reservedBytes = 0;
    uint32_t pixelDataOffset = BMP_HEADER_SIZE;
};

/**
 * @brief Bitmap info header structure
 * 
 * @details Size of this header, width and height in pixels, number of color planes,
 * color depth (bits per pixel), compression method, raw bitmap data size,
 * horizontal and vertical resolution (pixels per meter), number of colors in color table,
 * important colors.
 */
struct BmpInfoHeader {
    uint32_t sizeOfThisHeader = 40;
    int32_t width = BMP_WIDTH; // in pixels
    int32_t height = BMP_HEIGHT; // in pixels
    uint16_t numberOfColorPlanes = 1; // must be 1
    uint16_t colorDepth = COLOUR_DEPTH * 8; // bits per pixel
    uint32_t compressionMethod = 0;
    uint32_t rawBitmapDataSize = 0; // generally ignored
    int32_t horizontalResolution = 3780; // in pixel per meter
    int32_t verticalResolution = 3780; // in pixel per meter
    uint32_t colorTableEntries = 0;
    uint32_t importantColors = 0;
};

#pragma pack(pop)

/**
 * @brief Write out a bitmap file from raw RGB data
 * 
 * @param filename Output filename
 * @param pixelData Raw pixel data in RGB format
 */
void writeBitmapFile(std::string filename, const uint8_t* framestore);

#endif // TB_BITMAP_BITMAP_H