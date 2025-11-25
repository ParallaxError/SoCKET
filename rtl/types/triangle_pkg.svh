/*
 * @file /rtl/types/triangle_pkg.svh
 * @brief
 * Structure definition for the aggregated triangles passed from the binning stage.
 * Each triangle consists of 3 vertices, but also the bounding boxes of the triangle for efficient rasterization.
 *
 * -----
 * Last Modified: Tuesday, 25th November 2025 12:05 pm
 * -----
 */

`ifndef TRIANGLE_PKG_SV
`define TRIANGLE_PKG_SV

`include "types/vertex_pkg.svh"
`include "types/rendering_pkg.svh"
`include "types/pixels_pkg.svh"

package triangle_pkg;
  import vertex_pkg::*;
  import rendering_pkg::*;
  import pixels_pkg::*;

  typedef struct packed {
    vertex_t v0;
    vertex_t v1;
    vertex_t v2;

    // Inverse of area for co

    // Bounding box for the triangle
    logic [$clog2(SCREEN_WIDTH) - 1:0]  min_x;
    logic [$clog2(SCREEN_WIDTH) - 1:0]  max_x;
    logic [$clog2(SCREEN_HEIGHT) - 1:0] min_y;
    logic [$clog2(SCREEN_HEIGHT) - 1:0] max_y;
  } triangle_t;
endpackage

`endif  // TRIANGLE_PKG_SV
