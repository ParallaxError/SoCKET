/*
 * @file /rtl/types/rendering_pkg.svh
 * @brief
 * Rendering-specific definitions and constants for the graphics pipeline.
 *
 * -----
 * Last Modified: Sunday, 18th January 2026 9:41 pm
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
    localparam int BIN_HEIGHT    = 160;
endpackage : rendering_pkg

`endif // RENDERING_PKG_SV
