/*
 * @file /rtl/types/rendering_pkg.svh
 * @brief
 * Rendering-specific definitions and constants for the graphics pipeline.
 *
 * -----
 * Last Modified: Saturday, 29th November 2025 8:14 pm
 * -----
 */

`ifndef RENDERING_PKG_SV
`define RENDERING_PKG_SV

package rendering_pkg;

    // Constants for the rendering pipeline
    localparam int SCREEN_WIDTH  = 640;
    localparam int SCREEN_HEIGHT = 480;

    // Bin size
    localparam int BIN_WIDTH     = 160;
    localparam int BIN_HEIGHT    = 240;
endpackage : rendering_pkg

`endif // RENDERING_PKG_SV
