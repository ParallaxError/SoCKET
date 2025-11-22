/*
 * @file /rtl/types/fragment_pkg.svh
 * @brief
 * Fragment type passed from the raster shader to the fragment shader.
 * Each fragment encodes information about a pixel of a triangle to be shaded, such as its normals or colour.
 * The fragment shader then outputs a pixel buffer to be written to the framebuffer with this information.
 *
 * -----
 * Last Modified: Tuesday, 11th November 2025 2:03 pm
 * -----
 */

`ifndef FRAGMENT_PKG_SV
`define FRAGMENT_PKG_SV

`include "types/rendering_pkg.svh"

package fragment_pkg;
  import rendering_pkg::*;

  // Fragment structure
  typedef struct packed {
    // Pixel position
    logic [$clog2(SCREEN_WIDTH)-1:0]  x;
    logic [$clog2(SCREEN_HEIGHT)-1:0] y;

    // Interpolated colour
    logic [7:0] r;
    logic [7:0] g;
    logic [7:0] b;
  } fragment_t;

endpackage

`endif  // FRAGMENT_PKG_SV
