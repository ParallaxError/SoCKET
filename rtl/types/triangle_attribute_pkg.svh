/*
 * @file /rtl/types/triangle_attribute_pkg.svh
 * @brief
 * Contains a structure to store the initial triangle attributes for a bin.
 * This allows bins to share DSPs with another module that calculates initial triangle attributes.
 * 
 * -----
 * Last Modified: Friday, 28th November 2025 3:08 am
 * -----
 */

`ifndef TRIANGLE_ATTRIBUTE_PKG_SV
`define TRIANGLE_ATTRIBUTE_PKG_SV

`include "types/fixed_point_pkg.svh"
`include "types/fixed_point_wide_pkg.svh"
`include "types/triangle_pkg.svh"

package triangle_attribute_pkg;
  import fixed_point_pkg::*;
  import fixed_point_wide_pkg::*;
  import triangle_pkg::*;

  typedef struct {
    fixed_wide_t e0;
    fixed_wide_t e1;
    fixed_wide_t e2;

    fixed_wide_t R_start;
    fixed_wide_t G_start;
    fixed_wide_t B_start;
  } triangle_attributes_t;

  // Function to calculate initial triangle attributes for a given coordinate and triangle
  function automatic triangle_attributes_t calculate_initial_attributes(
      triangle_pkg::triangle_t triangle,
      integer bin_x,
      integer bin_y
  );
    triangle_attributes_t attrs;

    // Calculate the pixel position at the top-left of the bin
    fixed_wide_t px = wide_from_int(bin_x);
    fixed_wide_t py = wide_from_int(bin_y);
    fixed_t fixed_px = from_int(bin_x);
    fixed_t fixed_py = from_int(bin_y);

    // Calculate edge functions at this position
    attrs.e0 = edge_function(
      fixed_px, fixed_py,
      triangle.v0.x, triangle.v0.y,
      triangle.v1.x, triangle.v1.y
    );
    attrs.e1 = edge_function(
      fixed_px, fixed_py,
      triangle.v1.x, triangle.v1.y,
      triangle.v2.x, triangle.v2.y
    );
    attrs.e2 = edge_function(
      fixed_px, fixed_py,
      triangle.v2.x, triangle.v2.y,
      triangle.v0.x, triangle.v0.y
    );

    // Calculate starting colour attributes at this position
    // TODO Could use fixed_t instead of fixed_wide_t then promotes
    attrs.R_start = fixed_wide_add(
      fixed_wide_add(
        fixed_wide_mul(triangle.R_dx, fixed_wide_sub(px, from_fixed(triangle.v0.x))),
        fixed_wide_mul(triangle.R_dy, fixed_wide_sub(py, from_fixed(triangle.v0.y)))
      ),
      wide_from_int(triangle.v0.r)
    );

    attrs.G_start = fixed_wide_add(
      fixed_wide_add(
        fixed_wide_mul(triangle.G_dx, fixed_wide_sub(px, from_fixed(triangle.v0.x))),
        fixed_wide_mul(triangle.G_dy, fixed_wide_sub(py, from_fixed(triangle.v0.y)))
      ),
      wide_from_int(triangle.v0.g)
    );

    attrs.B_start = fixed_wide_add(
      fixed_wide_add(
        fixed_wide_mul(triangle.B_dx, fixed_wide_sub(px, from_fixed(triangle.v0.x))),
        fixed_wide_mul(triangle.B_dy, fixed_wide_sub(py, from_fixed(triangle.v0.y)))
      ),
      wide_from_int(triangle.v0.b)
    );

    return attrs;
  endfunction

endpackage;

`endif // TRIANGLE_ATTRIBUTE_PKG_SV
