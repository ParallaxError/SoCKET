/*
 * @file /rtl/stages/fragment_shader.sv
 * @brief
 * Fragment shader stage to convert fragments into pixel buffers.
 * Currently, just acts as a pass-through.
 *
 * -----
 * Last Modified: Saturday, 22nd November 2025 10:56 pm
 * -----
 */

`include "types/fragment_pkg.svh"
`include "types/pixels_pkg.svh"

module fragment_shader (
    input  logic                      clk_i,
    input  logic                      rst_i,

    // input streaming iface
    output logic                      in_ready_o,
    input  fragment_pkg::fragment_t   in_data_i,
    input  logic                      in_valid_i,

    // output streaming iface
    input  logic                      out_ready_i,
    output pixels_pkg::pixel_buffer_t out_data_o,
    output logic                      out_valid_o
);
  // Imports
  import fragment_pkg::*;
  import pixels_pkg::*;

  // Simple pass-through for now
  assign in_ready_o = out_ready_i;

  pixel_buffer_t out_data_comb;

  always_comb begin
    // Default outputs
    out_data_comb.pixels[in_data_i.x%PIXELS_PER_WORD].r = in_data_i.r[7:0];
    out_data_comb.pixels[in_data_i.x%PIXELS_PER_WORD].g = in_data_i.g[7:0];
    out_data_comb.pixels[in_data_i.x%PIXELS_PER_WORD].b = in_data_i.b[7:0];
  end

  assign out_valid_o             = in_valid_i;
  assign out_data_o.pixels       = out_data_comb.pixels;
  assign out_data_o.x            = in_data_i.x / PIXELS_PER_WORD;
  assign out_data_o.y            = in_data_i.y;
  assign out_data_o.valid_pixels = 1 << (in_data_i.x % PIXELS_PER_WORD);

endmodule
