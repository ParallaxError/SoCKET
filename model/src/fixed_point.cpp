/*
 * @file /src/fixed_point.cpp
 * @brief
 * Implementation of Verilog-accurate fixed-point arithmetic utilities for the GPU model.
 * 
 * -----
 */

// Includes
#include <array>
#include <stdexcept>
#include <iostream>
#include <bitset>

#include "fixed_point.h"

template <int INT_BITS, int FRAC_BITS>
FixedPoint<INT_BITS, FRAC_BITS>::FixedPoint() : value(0) 
{
    if (INT_BITS + FRAC_BITS > 64) {
        throw std::invalid_argument("Total bit width exceeds 64 bits");
    }
}

template <int INT_BITS, int FRAC_BITS>
FixedPoint<INT_BITS, FRAC_BITS>::FixedPoint(double val) 
{
    if (INT_BITS + FRAC_BITS > 64) {
        throw std::invalid_argument("Total bit width exceeds 64 bits");
    }
    value = static_cast<int64_t>(val * (1LL << FRAC_BITS));
}

// Operations
template <int INT_BITS, int FRAC_BITS>
FixedPoint<INT_BITS, FRAC_BITS> FixedPoint<INT_BITS, FRAC_BITS>::operator+(const FixedPoint& other) const 
{
    FixedPoint result;
    result.value = this->value + other.value;
    return result;
}

template <int INT_BITS, int FRAC_BITS>
FixedPoint<INT_BITS, FRAC_BITS> FixedPoint<INT_BITS, FRAC_BITS>::operator-(const FixedPoint& other) const 
{
    FixedPoint result;
    result.value = this->value - other.value;
    return result;
}

template <int INT_BITS, int FRAC_BITS>
FixedPoint<INT_BITS, FRAC_BITS> FixedPoint<INT_BITS, FRAC_BITS>::operator*(const FixedPoint& other) const 
{
    FixedPoint result;
    __int128_t temp = static_cast<__int128_t>(this->value) * static_cast<__int128_t>(other.value);
    result.value = static_cast<int64_t>(temp >> FRAC_BITS);
    return result;
}

// Newton Raphson division
// The corresponding RTL code is in rtl/components/reciprocal.sv

// First, compile time LUT for initial approximation
// The corresponding RTL is
/*
  fixed_t lut [0:LUT_SIZE-1];
  initial begin
    // Precompute the LUT values (procedural for-loop is synthesizer/testbench friendly)
    for (int i = 0; i < LUT_SIZE; i++) begin
      real denom;
      real recip; 
      denom = 1.0 + (real'(i) / real'(LUT_SIZE));
      recip = 1.0 / denom;
      lut[i] = from_real(recip);
    end
  end
*/

// I hate C++
constexpr unsigned floorlog2(unsigned x)
{
    return x == 1 ? 0 : 1+floorlog2(x >> 1);
}

constexpr unsigned ceillog2(unsigned x)
{
    return x == 1 ? 0 : floorlog2(x - 1) + 1;
}

constexpr int LUT_SIZE = 128;
constexpr int LUT_ADDR_WIDTH = ceillog2(LUT_SIZE);

template <int INT_BITS, int FRAC_BITS>
FixedPoint<INT_BITS, FRAC_BITS> initial_reciprocal_approximation(int index) 
{
    double denom = 1.0 + (static_cast<double>(index) / static_cast<double>(LUT_SIZE));
    double recip = 1.0 / denom;
    return FixedPoint<INT_BITS, FRAC_BITS>(recip);
}

template <size_t N, int INT_BITS, int FRAC_BITS>
std::array<FixedPoint<INT_BITS, FRAC_BITS>, N> generate_lut()
{
    std::array<FixedPoint<INT_BITS, FRAC_BITS>, N> lut = {};
    for (size_t i = 0; i < N; ++i) 
    {
        lut[i] = initial_reciprocal_approximation<INT_BITS, FRAC_BITS>(i);
    }
    return lut;
}

template <int INT_BITS, int FRAC_BITS>
static auto RECIP_LUT = generate_lut<LUT_SIZE, INT_BITS, FRAC_BITS>();

template <int INT_BITS, int FRAC_BITS>
FixedPoint<INT_BITS, FRAC_BITS> FixedPoint<INT_BITS, FRAC_BITS>::operator/(const FixedPoint& other) const 
{
    // First get our LUT index, normalising the denominator to the range [1,2)
    FixedPoint<INT_BITS, FRAC_BITS> norm;
    uint64_t absValue;
    bool sign;
    
    // First we want the sign of the result
    // Sign bit is at bit position INT_BITS + FRAC_BITS - 1
    sign = other.value & (1LL << (INT_BITS + FRAC_BITS - 1));
    if (sign)
        absValue = -other.value;
    else
        absValue = other.value;

    // Next we find the MSB position
    int msb = -1;
    for (int i = INT_BITS + FRAC_BITS - 1; i >= 0; i--) {
        if (other.value & (1LL << i)) {
            msb = i;
            break;
        }
    }

    FixedPoint<INT_BITS, FRAC_BITS> reciprocal;
    int S;
    if (msb == -1) 
    {
        S = 0;
        norm.value = 0;
        reciprocal = RECIP_LUT<INT_BITS, FRAC_BITS>[0];
    }
    else
    {
        // Now we can normalise
        uint64_t normBits;
    
        S = FRAC_BITS - msb;
        norm.value = absValue;
        absValue &= ((1LL << (INT_BITS + FRAC_BITS)) - 1); // Mask to bitwidth
    
        if (S >= 0) {
            normBits = absValue << S;
        } else {
            normBits = absValue >> -S;
        }
        norm.value = normBits;
            
        // Get LUT index from top bits of normalised denominator
        // lut_idx = $unsigned(normalised_struct.norm.value[FIXED_FRAC-1 -: LUT_ADDR_WIDTH]);
        int lutIndex = (norm.value >> (FRAC_BITS - 1 - LUT_ADDR_WIDTH)) & ((1 << LUT_ADDR_WIDTH) - 1);
        reciprocal = RECIP_LUT<INT_BITS, FRAC_BITS>[lutIndex];
    }

    // Now, two Newton-Raphson iterations
    // x_{n+1} = x_n * (2 - D * x_n)
    for (int i = 0; i < 2; i++) 
    {
        FixedPoint<INT_BITS, FRAC_BITS> D_xn = norm * reciprocal;
        FixedPoint<INT_BITS, FRAC_BITS> twoMinusD_xn = FixedPoint<INT_BITS, FRAC_BITS>(2.0) - D_xn;
        reciprocal = reciprocal * twoMinusD_xn;
    }

    // Apply exponent correction: reciprocal(original) = reciprocal(normalized) * 2^{S}    
    if (S >= 0) {
        reciprocal.value = reciprocal.value << S;
    } else {
        reciprocal.value = reciprocal.value >> -S;
    }
    
    // Reapply sign of denominator
    if (sign)
        reciprocal.value = -reciprocal.value;

    // Finally, multiply by numerator
    return (*this) * reciprocal;
}

template <int INT_BITS, int FRAC_BITS>
double FixedPoint<INT_BITS, FRAC_BITS>::toDouble() const 
{
    return static_cast<double>(value) / static_cast<double>(1LL << FRAC_BITS);
}

// Compile for used types, I hate C++
template class FixedPoint<11, 9>;
template class FixedPoint<18, 18>;