/*
 * @file /src/fixed_point.h
 * @brief
 * Verilog-accurate fixed-point arithmetic utilities for the GPU model.
 * 
 * Allows template-based fixed-point number representation with configurable bit widths for the integral and fractional
 * parts. Has normal arithmetic operators overloaded to mimic Verilog fixed-point behavior, notably division as 
 * Newton-Raphson iteration.
 * 
 * -----
 */

#ifndef FIXED_POINT_H
#define FIXED_POINT_H

// Includes
#include <cstdint>

template <int INT_BITS, int FRAC_BITS>
class FixedPoint {
public:
    FixedPoint();
    FixedPoint(double value);

    FixedPoint operator+(const FixedPoint& other) const;
    FixedPoint operator-(const FixedPoint& other) const;
    FixedPoint operator*(const FixedPoint& other) const;
    FixedPoint operator/(const FixedPoint& other) const;

    // Debug method
    double toDouble() const;
    int64_t value; // Underlying representation
};

#endif // FIXED_POINT_H