/*
 * @file /rtl/types/mat4x4.sv
 * @brief
 * SystemVerilog package for a 4x4 transformation matrix used in 3D graphics processing.
 * The size each cell is parameterized to allow for different fixed-point representations, but should match
 * the vertex coordinate representation for correct matrix-vector multiplication.
 * 
 * -----
 * Last Modified: Sunday, 2nd November 2025 8:20 pm
 * -----
 */

`ifndef MAT4X4_PKG_SV
`define MAT4X4_PKG_SV

`include "types/fixed_point.sv"
package mat4x4_pkg;
    import fixed_point_pkg::*;

    typedef struct {
        fixed_t m[4][4];
    } mat4x4_t;

endpackage
`endif // MAT4X4_PKG_SV