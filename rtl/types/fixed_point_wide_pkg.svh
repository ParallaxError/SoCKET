/*
 * @file /rtl/types/fixed_point_wide_pkg.svh
 * @brief
 * Fixed point type with double the width of the standard fixed point type.
 * Used for calculations like the edge functions in rasterization to avoid overflow.
 *
 * -----
 * Last Modified: Thursday, 27th November 2025 10:21 pm
 * -----
 */

`ifndef FIXED_POINT_WIDE_PKG_SV
`define FIXED_POINT_WIDE_PKG_SV

`include "types/fixed_point_pkg.svh"
;
package fixed_point_wide_pkg;
  import fixed_point_pkg::*;

  parameter int FIXED_WIDE_WIDTH = 36;
  parameter int FIXED_WIDE_FRAC  = 18;

  typedef struct packed {logic signed [FIXED_WIDE_WIDTH-1:0] value;} fixed_wide_t;

  function automatic fixed_wide_t from_fixed(fixed_t f);
    fixed_wide_t w;
    localparam int SHIFT = FIXED_WIDE_FRAC - FIXED_FRAC;

    // Sign-extend the input fixed point value since the point is in a new position
    logic signed [FIXED_WIDE_WIDTH-1:0] ext;
    ext = {{(FIXED_WIDE_WIDTH-FIXED_WIDTH){f.value[FIXED_WIDTH-1]}}, f.value};

    w.value = ext <<< SHIFT;
    return w;
  endfunction

  function automatic fixed_wide_t wide_from_int(int i);
    fixed_wide_t w;
    w.value = i <<< FIXED_WIDE_FRAC;
    return w;
  endfunction

  function automatic fixed_wide_t wide_from_real(real r);
    fixed_wide_t w;
    w.value = $rtoi(r * (1 << FIXED_WIDE_FRAC));
    return w;
  endfunction

  function automatic logic [7:0] to_int8(fixed_wide_t f);
    logic signed [FIXED_WIDE_WIDTH-1:0] shifted;
    shifted = f.value >>> FIXED_WIDE_FRAC;
    return shifted[7:0];
  endfunction

  function automatic real wide_to_real(fixed_wide_t f);
    return real'(f.value) / real'(1 << FIXED_WIDE_FRAC);
  endfunction

  // Arithmetic needed: sub and mult
  function automatic fixed_wide_t fixed_wide_sub(fixed_wide_t a, fixed_wide_t b);
    fixed_wide_t result;
    result.value = a.value - b.value;
    return result;
  endfunction

  function automatic fixed_wide_t fixed_wide_add(fixed_wide_t a, fixed_wide_t b);
    fixed_wide_t result;
    result.value = a.value + b.value;
    return result;
  endfunction

  function automatic fixed_wide_t fixed_wide_neg(fixed_wide_t a);
    fixed_wide_t result;
    result.value = -a.value;
    return result;
  endfunction

  function automatic fixed_wide_t fixed_wide_mul(fixed_wide_t a, fixed_wide_t b);
    fixed_wide_t result;
    // Extra size needed to hold full product
    logic signed [(2*FIXED_WIDE_WIDTH)-1:0] full;
    // Multiply and adjust for fixed point fractional bits
    full = a.value * b.value;
    result.value = full >>> (FIXED_WIDE_FRAC);

    return result;
  endfunction

endpackage
`endif  // FIXED_POINT_WIDE_PKG_SV
