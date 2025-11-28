/*
 * @file /rtl/types/triangle_pkg.svh
 * @brief
 * Structure definition for the aggregated triangles passed from the binning stage.
 * Each triangle consists of 3 vertices, but also the bounding boxes of the triangle for efficient rasterization.
 *
 * -----
 * Last Modified: Thursday, 27th November 2025 10:21 pm
 * -----
 */

`ifndef TRIANGLE_PKG_SV
`define TRIANGLE_PKG_SV

`include "types/fixed_point_pkg.svh"
`include "types/fixed_point_wide_pkg.svh"
`include "types/vertex_pkg.svh"
`include "types/rendering_pkg.svh"
`include "types/pixels_pkg.svh"

package triangle_pkg;
  import fixed_point_pkg::*;
  import fixed_point_wide_pkg::*;
  import vertex_pkg::*;
  import rendering_pkg::*;
  import pixels_pkg::*;

  typedef struct packed {
    vertex_t v0;
    vertex_t v1;
    vertex_t v2;

    // Inverse of area for colour interpolation
    fixed_wide_t inverse_area;

    // Bounding box for the triangle
    logic [$clog2(SCREEN_WIDTH) - 1:0]  min_x;
    logic [$clog2(SCREEN_WIDTH) - 1:0]  max_x;
    logic [$clog2(SCREEN_HEIGHT) - 1:0] min_y;
    logic [$clog2(SCREEN_HEIGHT) - 1:0] max_y;
  } triangle_t;

  // Edge function helper (returns signed area)
  function automatic fixed_wide_t edge_function(
      fixed_t px, fixed_t py,
      fixed_t x0, fixed_t y0,
      fixed_t x1, fixed_t y1
  );
      // Use wider intermediates
      fixed_wide_t dxp, dyp, dx, dy, term1, term2;

      // Compute differences (sign-extend to wide type)
      dxp = fixed_wide_sub(from_fixed(px), from_fixed(x0));
      dyp = fixed_wide_sub(from_fixed(py), from_fixed(y0));
      dx  = fixed_wide_sub(from_fixed(x1), from_fixed(x0));
      dy  = fixed_wide_sub(from_fixed(y1), from_fixed(y0));

      // Edge function = (px - x0)*(y1 - y0) - (py - y0)*(x1 - x0)
      term1 = fixed_wide_mul(dxp, dy);
      term2 = fixed_wide_mul(dyp, dx);

      return fixed_wide_sub(term1, term2);
  endfunction
endpackage

`endif  // TRIANGLE_PKG_SV
