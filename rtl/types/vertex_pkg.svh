/*
 * @file /rtl/types/vertex_pkg.svh
 * @brief
 * SystemVerilog package for the vertex data type used in 3D graphics processing.
 * Each vertex has a position comprising of three fixed-point coordinates (x, y, z).
 * Currently, each vertex also has a colour: RGB with 8 bits per channel.
 * Later, may add texture coordinates, normals, etc.
 *
 * -----
 * Last Modified: Monday, 10th November 2025 3:25 pm
 * -----
 */

`ifndef VERTEX_PKG_SV
`define VERTEX_PKG_SV

`include "types/fixed_point_pkg.svh"

package vertex_pkg;
  import fixed_point_pkg::*;

  parameter int COLOUR_DEPTH = 8;

  typedef struct packed {
    fixed_t x;
    fixed_t y;
    fixed_t z;
    logic [COLOUR_DEPTH-1:0]    r;
    logic [COLOUR_DEPTH-1:0]    g;
    logic [COLOUR_DEPTH-1:0]    b;
  } vertex_t;

endpackage
`endif  // VERTEX_PKG_SV
