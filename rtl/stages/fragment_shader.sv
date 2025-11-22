/*
 * @file /rtl/stages/fragment_shader.sv
 * @brief
 * Fragment shader stage to convert fragments into pixel buffers.
 * Currently, just acts as a pass-through.
 *
 * -----
 * Last Modified: Tuesday, 11th November 2025 2:05 pm
 * -----
 */

`include "types/fragment_pkg.svh"
`include "types/pixels_pkg.svh"
import fragment_pkg::*;
import pixels_pkg::*;

module fragment_shader (
    input logic clk,
    input logic rst,

    // input streaming iface
    output logic      in_ready,
    input  fragment_t in_data,
    input  logic      in_valid,

    // output streaming iface
    input  logic          out_ready,
    output pixel_buffer_t out_data,
    output logic          out_valid
);

  // Simple pass-through for now
  assign in_ready = out_ready;

  always_comb begin
    // Default outputs
    out_data.pixels[in_data.x%PIXELS_PER_WORD].r = in_data.r[7:0];
    out_data.pixels[in_data.x%PIXELS_PER_WORD].g = in_data.g[7:0];
    out_data.pixels[in_data.x%PIXELS_PER_WORD].b = in_data.b[7:0];
  end

  assign out_valid             = in_valid;
  assign out_data.x            = in_data.x / PIXELS_PER_WORD;
  assign out_data.y            = in_data.y;
  assign out_data.valid_pixels = 1 << (in_data.x % PIXELS_PER_WORD);

endmodule
