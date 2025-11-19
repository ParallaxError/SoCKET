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

`include "types/fragment.sv"
`include "types/pixels.sv"
import fragment_pkg::*;
import pixels_pkg::*;

module FragmentShader
(
    input  logic            clk,
    input  logic            rst,

    // input streaming iface
    output logic            in_frag_ready,
    input  fragment_t       in_frag_data,
    input  logic            in_frag_valid,

    // output streaming iface
    input  logic            out_ready,
    output pixel_buffer_t   out_data,
    output logic            out_valid
);

    // Simple pass-through for now
    assign in_frag_ready = out_ready;
    
    always_comb begin
        // Default outputs
        out_data.pixels[in_frag_data.x % PIXELS_PER_WORD].r = in_frag_data.r[7:0];
        out_data.pixels[in_frag_data.x % PIXELS_PER_WORD].g = in_frag_data.g[7:0];
        out_data.pixels[in_frag_data.x % PIXELS_PER_WORD].b = in_frag_data.b[7:0];
    end

    assign out_valid      = in_frag_valid;
    assign out_data.x     = in_frag_data.x / PIXELS_PER_WORD;
    assign out_data.y     = in_frag_data.y;
    assign out_data.valid_pixels = 1 << (in_frag_data.x % PIXELS_PER_WORD);

endmodule