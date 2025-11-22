/*
 * @file /rtl/types/fixed_point_wide_pkg.svh
 * @brief
 * Fixed point type with double the width of the standard fixed point type.
 * Used for calculations like the edge functions in rasterization to avoid overflow.
 *
 * -----
 * Last Modified: Sunday, 9th November 2025 10:18 pm
 * -----
 */

`ifndef FIXED_POINT_WIDE_PKG_SV
`define FIXED_POINT_WIDE_PKG_SV

`include "types/fixed_point_pkg.svh"
;
package fixed_point_wide_pkg;
  import fixed_point_pkg::*;

  typedef struct packed {logic signed [FIXED_WIDTH*2-1:0] value;} fixed_wide_t;

  function automatic fixed_wide_t from_fixed(fixed_t f);
    fixed_wide_t w;
    w.value = {{FIXED_WIDTH{f.value[FIXED_WIDTH-1]}}, f.value};
    return w;
  endfunction

  function automatic fixed_wide_t from_int(int signed f);
    fixed_wide_t w;
    // TODO: Surely a better way... ugly
    w.value = $signed({{FIXED_WIDTH{$signed(f)[FIXED_WIDTH-1]}}, f}) <<< FIXED_FRAC;
    return w;
  endfunction

  // TODO: delete
  function automatic logic [7:0] to_int8(fixed_wide_t f);
    logic signed [FIXED_WIDTH*2-1:0] shifted;
    shifted = f.value >>> FIXED_FRAC;
    return shifted[7:0];
  endfunction

  function automatic real wide_to_real(fixed_wide_t f);
    return real'(f.value) / real'(1 << FIXED_FRAC);
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
    // Multiply and adjust for fixed point fractional bits
    result.value = (a.value * b.value) >>> (FIXED_FRAC);
    return result;
  endfunction

  function automatic fixed_wide_t fixed_wide_div(fixed_wide_t a, fixed_wide_t b);
    fixed_wide_t result;
    result.value = (a.value <<< FIXED_FRAC) / b.value;
    return result;
  endfunction

endpackage
`endif  // FIXED_POINT_WIDE_PKG_SV
