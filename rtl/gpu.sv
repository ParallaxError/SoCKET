/*
 * @file /rtl/gpu.sv
 * @brief
 * Top-level module for the GPU design.
 * Instantiaites and connects the various pipeline stages and components.
 * Also inserts FIFO buffers between stages to decouple timing.
 * Exposes signals to show if the GPU is busy processing data or has data to output.
 *
 * -----
 * Last Modified: Monday, 10th November 2025 7:38 pm
 * -----
 */

`include "types/vertex_pkg.svh"
`include "types/mat4x4_pkg.svh"
`include "types/pixels_pkg.svh"
`include "types/rendering_pkg.svh"
import vertex_pkg::*;
import mat4x4_pkg::*;
import pixels_pkg::*;
import rendering_pkg::*;

module gpu (
    input logic clk,
    input logic rst,

    // input streaming iface
    output logic    in_ready,
    input  vertex_t in_data,
    input  logic    in_valid,

    // Input matrix
    input mat4x4_t in_matrix,

    // output streaming iface
    input  logic          out_ready,
    output pixel_buffer_t out_data,
    output logic          out_valid
);

  // Vertex Shader Stage
  logic    vs_out_ready;
  logic    vs_out_valid;
  vertex_t vs_out_data;

  vertex_shader vertex_shader_inst (
      .clk      (clk),
      .rst      (rst),

      .in_ready (in_ready),
      .in_data  (in_data),
      .in_valid (in_valid),

      .in_matrix(in_matrix),

      .out_ready(!vs_binner_full),
      .out_data (vs_out_data),
      .out_valid(vs_out_valid)
  );

  // VS out -> Binner in FIFO
  logic    vs_binner_empty;
  logic    vs_binner_full;
  vertex_t vs_binner_out_data;
  logic    vs_binner_out_data_valid;

  sync_fifo #(
      .T(vertex_t),
      .DEPTH(16)  // TODO magic
  ) vs_to_binner_fifo (
      .clk          (clk),
      .rst          (rst),

      .rd_en        (vs_out_ready),
      .empty        (vs_binner_empty),
      .rd_data      (vs_binner_out_data),
      .rd_data_valid(vs_binner_out_data_valid),

      .wr_en        (vs_out_valid),
      .wr_data      (vs_out_data),
      .full         (vs_binner_full)
  );

  // Binner stage
  // First, calculate number of bins
  localparam int NUM_BINS_X = SCREEN_WIDTH / BIN_WIDTH;
  localparam int NUM_BINS_Y = SCREEN_HEIGHT / BIN_HEIGHT;

  // Binner signals
  logic      binner_out_valid[NUM_BINS_X][NUM_BINS_Y];
  logic      binner_out_ready[NUM_BINS_X][NUM_BINS_Y];
  triangle_t binner_out_data;

  binner #(
      .BIN_WIDTH (BIN_WIDTH),
      .BIN_HEIGHT(BIN_HEIGHT)
  ) binner_inst (
      .clk          (clk),
      .rst          (rst),

      .in_vert_ready(vs_out_ready),
      .in_vert_data (vs_binner_out_data),
      .in_vert_valid(vs_binner_out_data_valid),

      .out_ready    (binner_out_ready),
      .out_data     (binner_out_data),
      .out_valid    (binner_out_valid)
  );

  // Binner -> raster FIFOs
  logic      binner_raster_empty[NUM_BINS_X][NUM_BINS_Y];
  logic      binner_raster_full [NUM_BINS_X][NUM_BINS_Y];

  triangle_t binner_raster_out_data      [NUM_BINS_X * NUM_BINS_Y];
  logic      binner_raster_out_data_valid[NUM_BINS_X * NUM_BINS_Y];

  genvar binner_raster_x, binner_raster_y;
  generate
    for (
        binner_raster_x = 0; binner_raster_x < NUM_BINS_X; binner_raster_x++
    ) begin : gen_binner_raster_fifos_x
      for (
          binner_raster_y = 0; binner_raster_y < NUM_BINS_Y; binner_raster_y++
      ) begin : gen_binner_raster_fifos_y
        // FIFO between binner and raster unit
        logic binner_raster_empty;
        logic binner_raster_full;

        sync_fifo #(
            .T(triangle_t),
            .DEPTH(16)  // TODO magic
        ) binner_to_raster_fifo (
            .clk          (clk),
            .rst          (rst),

            .rd_en        (binner_raster_out_ready[binner_raster_x*NUM_BINS_Y+binner_raster_y]),
            .empty        (binner_raster_empty),
            .rd_data      (binner_raster_out_data[binner_raster_x*NUM_BINS_Y+binner_raster_y]),
            .rd_data_valid(
                binner_raster_out_data_valid[binner_raster_x * NUM_BINS_Y + binner_raster_y]
            ),

            .wr_en        (binner_out_valid[binner_raster_x][binner_raster_y]),
            .wr_data      (binner_out_data),
            .full         (binner_raster_full)
        );

        // Connect binner outputs to FIFO inputs
        assign binner_out_ready[binner_raster_x][binner_raster_y] = !binner_raster_full;
      end
    end
  endgenerate

  // Raster units
  logic      binner_raster_out_ready[NUM_BINS_X * NUM_BINS_Y];
  logic      raster_frag_out_ready  [NUM_BINS_X * NUM_BINS_Y];
  logic      raster_frag_out_valid  [NUM_BINS_X * NUM_BINS_Y];
  fragment_t raster_frag_out_data   [NUM_BINS_X * NUM_BINS_Y];
  genvar bx, by;
  generate
    for (bx = 0; bx < NUM_BINS_X; bx++) begin : gen_raster_units_x
      for (by = 0; by < NUM_BINS_Y; by++) begin : gen_raster_units_y

        raster_shader #(
            .TOP_LEFT_X(bx * BIN_WIDTH),
            .TOP_LEFT_Y(by * BIN_HEIGHT)
        ) raster_shader_inst (
            .clk      (clk),
            .rst      (rst),

            // Input iface (from binner FIFOs)
            .in_ready (binner_raster_out_ready[bx*NUM_BINS_Y+by]),
            .in_data  (binner_raster_out_data[bx*NUM_BINS_Y+by]),
            .in_valid (binner_raster_out_data_valid[bx*NUM_BINS_Y+by]),

            // Output iface (to aggregator)
            .out_ready(raster_frag_out_ready[bx*NUM_BINS_Y+by]),
            .out_data (raster_frag_out_data[bx*NUM_BINS_Y+by]),
            .out_valid(raster_frag_out_valid[bx*NUM_BINS_Y+by])
        );

      end
    end
  endgenerate

  // Raster -> Fragment shader
  logic          frag_out_ready[NUM_BINS_X * NUM_BINS_Y];
  logic          frag_out_valid[NUM_BINS_X * NUM_BINS_Y];
  pixel_buffer_t frag_out_data [NUM_BINS_X * NUM_BINS_Y];

  genvar fx, fy;
  generate
    for (fx = 0; fx < NUM_BINS_X; fx++) begin : gen_frag_shaders_x
      for (fy = 0; fy < NUM_BINS_Y; fy++) begin : gen_frag_shaders_y
        fragment_shader fragment_shader_inst (
            .clk      (clk),
            .rst      (rst),

            // input streaming iface
            .in_ready (raster_frag_out_ready[fx*NUM_BINS_Y+fy]),
            .in_data  (raster_frag_out_data[fx*NUM_BINS_Y+fy]),
            .in_valid (raster_frag_out_valid[fx*NUM_BINS_Y+fy]),

            // output streaming iface
            .out_ready(frag_out_ready[fx*NUM_BINS_Y+fy]),
            .out_data (frag_out_data[fx*NUM_BINS_Y+fy]),
            .out_valid(frag_out_valid[fx*NUM_BINS_Y+fy])
        );
      end
    end
  endgenerate

  // TODO: Output FIFOs to aggregator

  // Pixel aggregator
  sync_fifo_aggregator #(
      .T(pixel_buffer_t),
      .NUM_INPUTS(NUM_BINS_X * NUM_BINS_Y)
  ) pixel_aggregator_inst (
      .clk     (clk),
      .rst     (rst),

      // Input ifaces from raster units
      .in_ready(frag_out_ready),
      .in_data (frag_out_data),
      .in_valid(frag_out_valid),

      // Output iface
      .out_ready(out_ready),
      .out_data (out_data),
      .out_valid(out_valid)
  );


endmodule
