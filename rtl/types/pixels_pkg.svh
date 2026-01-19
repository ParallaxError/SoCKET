/*
 * @file /rtl/types/pixels_pkg.svh
 * @brief
 * Structure definitions for pixel output from the GPU pipeline.
 * Since the framestore can accept 4 8 bit/2 16 bit pixels per clock,
 * we define a packed structure to hold multiple pixels.
 *
 * -----
 * Last Modified: Sunday, 18th January 2026 10:16 pm
 * -----
 */

`ifndef PIXELS_PKG_SV
`define PIXELS_PKG_SV

`include "types/rendering_pkg.svh"
package pixels_pkg;
  import rendering_pkg::*;

  // Single pixel structure
  parameter int RED_DEPTH = 5;
  parameter int GREEN_DEPTH = 6;
  parameter int BLUE_DEPTH = 5;

  typedef struct packed {
    logic [RED_DEPTH-1:0] r;
    logic [GREEN_DEPTH-1:0] g;
    logic [BLUE_DEPTH-1:0] b;
  } pixel_t;

  // 32 bit buffer holding as many pixels as possible, with a signal
  // for how many pixels are valid (may output less than max if at end of line)
  localparam int PIXEL_WIDTH = $bits(pixel_t);
  localparam int PIXELS_PER_WORD = 32 / PIXEL_WIDTH;
  typedef struct packed {
    logic [$clog2(SCREEN_WIDTH / PIXELS_PER_WORD)-1:0] x;
    // y indexes full pixel rows, so width should be based on SCREEN_HEIGHT (not divided
    // by PIXELS_PER_WORD). Using SCREEN_HEIGHT/PIXELS_PER_WORD here truncated values
    // (e.g. 135 -> 7). Use full height so rows up to SCREEN_HEIGHT-1 fit.
    logic [$clog2(SCREEN_HEIGHT)-1:0] y;
    pixel_t [0:PIXELS_PER_WORD-1] pixels;
    logic [PIXELS_PER_WORD - 1:0] valid_pixels;
  } pixel_buffer_t;

endpackage

`endif  // PIXELS_PKG_SV
