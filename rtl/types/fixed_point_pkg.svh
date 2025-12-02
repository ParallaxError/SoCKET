/*
 * @file /rtl/types/fixed_point_pkg.svh
 * @brief
 * SystemVerilog package for a fixed-point number representation.
 * Allows a parameterized number of integer and fractional bits. Also has helper functions to convert to/from
 * the SystemVerilog real type.
 * https://www.chipverify.com/systemverilog/systemverilog-package
 *
 * -----
 * Last Modified: Tuesday, 2nd December 2025 10:46 pm
 * -----
 */

`ifndef FIXED_POINT_PKG_SV
`define FIXED_POINT_PKG_SV
package fixed_point_pkg;

  // Configurable parameters
  parameter int FIXED_WIDTH = 32;
  parameter int FIXED_FRAC = 16;

  typedef struct packed {logic signed [FIXED_WIDTH-1:0] value;} fixed_t;

  // Convert from real to fixed
  function automatic fixed_t from_real(real r);
    fixed_t f;
    f.value = $rtoi(r * (1 << FIXED_FRAC));
    return f;
  endfunction

  // From int
  function automatic fixed_t from_int(int i);
    fixed_t f;
    f.value = i <<< FIXED_FRAC;
    return f;
  endfunction

  // Convert back to real (for testbench printing)
  function automatic real to_real(fixed_t f);
    return real'(f.value) / real'(1 << FIXED_FRAC);
  endfunction

  // From int
  function automatic fixed_t int_to_fixed_point(int i);
    fixed_t f;
    f.value = i <<< FIXED_FRAC;
    return f;
  endfunction

  // Get rid of the fractional part (floor) and return an integer
  function automatic int fixed_point_to_int(fixed_t f);
    return $signed(f.value >>> FIXED_FRAC);
  endfunction

  // Add two fixed point numbers
  function automatic fixed_t fixed_point_add(fixed_t a, fixed_t b);
    fixed_t result;
    result.value = a.value + b.value;
    return result;
  endfunction

  // Subtract two fixed point numbers
  function automatic fixed_t fixed_point_sub(fixed_t a, fixed_t b);
    fixed_t result;
    result.value = a.value - b.value;
    return result;
  endfunction

  // Multiply two fixed point numbers
  function automatic fixed_t fixed_point_mult(fixed_t a, fixed_t b);
    fixed_t result;
    logic signed [FIXED_WIDTH * 2 - 1:0] product;

    // Multiply the raw values, then shift right by the number of fractional bits
    product = a.value * b.value;
    result.value = product[FIXED_WIDTH+FIXED_FRAC-1-:FIXED_WIDTH];
    return result;
  endfunction

endpackage
`endif  // FIXED_POINT_PKG_SV
