/*
 * @file /rtl/gpu.sv
 * @brief
 * Top-level module for the GPU design.
 * Instantiaites and connects the various pipeline stages and components.
 * Also inserts FIFO buffers between stages to decouple timing.
 * Exposes signals to show if the GPU is busy processing data or has data to output.
 *
 * -----
 * Last Modified: Saturday, 22nd November 2025 10:58 pm
 * -----
 */

`include "types/rendering_pkg.svh"
`include "types/pixels_pkg.svh"
`include "types/mat4x4_pkg.svh"
`include "types/vertex_pkg.svh"
`include "types/triangle_pkg.svh"
`include "types/fragment_pkg.svh"

module gpu (
    input  logic                      clk_i,
    input  logic                      rst_i,

    // Input streaming iface
    output logic                      in_ready_o,
    input  vertex_pkg::vertex_t       in_data_i,
    input  logic                      in_valid_i,

    // Input matrix
    input  mat4x4_pkg::mat4x4_t       in_matrix_i,
    // Output streaming iface
    input  logic                      out_ready_i,
    output pixels_pkg::pixel_buffer_t out_data_o,
    output logic                      out_valid_o
);
  // Imports
  import rendering_pkg::*;
  import pixels_pkg::*;
  import mat4x4_pkg::*;
  import vertex_pkg::*;
  import triangle_pkg::*;
  import fragment_pkg::*;

  // Vertex Shader Stage
  logic    vs_out_ready;
  logic    vs_out_valid;
  vertex_t vs_out_data;

  vertex_shader vertex_shader_inst (
      .clk_i      (clk_i),
      .rst_i      (rst_i),

      .in_ready_o (in_ready_o),
      .in_data_i  (in_data_i),
      .in_valid_i (in_valid_i),

      .in_matrix_i(in_matrix_i),

      .out_ready_i(!vs_binner_full),
      .out_data_o (vs_out_data),
      .out_valid_o(vs_out_valid)
  );

  // VS out -> Binner in FIFO
  logic    vs_binner_full;
  vertex_t vs_binner_out_data;
  logic    vs_binner_out_data_valid;

  sync_fifo #(
      .T(vertex_t),
      .DEPTH(16)  // TODO magic
  ) vs_to_binner_fifo (
      .clk_i          (clk_i),
      .rst_i          (rst_i),

      .rd_en_i        (vs_out_ready),
      .empty_o        (),
      .rd_data_o      (vs_binner_out_data),
      .rd_data_valid_o(vs_binner_out_data_valid),

      .wr_en_i        (vs_out_valid),
      .wr_data_i      (vs_out_data),
      .full_o         (vs_binner_full)
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
      .clk_i          (clk_i),
      .rst_i          (rst_i),

      .in_vert_ready_o(vs_out_ready),
      .in_vert_data_i (vs_binner_out_data),
      .in_vert_valid_i(vs_binner_out_data_valid),

      .out_ready_i    (binner_out_ready),
      .out_data_o     (binner_out_data),
      .out_valid_o    (binner_out_valid)
  );

  // Binner -> raster FIFOs
  triangle_t binner_raster_out_data      [NUM_BINS_X * NUM_BINS_Y];
  logic      binner_raster_out_data_valid[NUM_BINS_X * NUM_BINS_Y];

  logic      binner_raster_out_ready     [NUM_BINS_X * NUM_BINS_Y];

  genvar binner_raster_x, binner_raster_y;
  generate
    for (
        binner_raster_x = 0; binner_raster_x < NUM_BINS_X; binner_raster_x++
    ) begin : gen_binner_raster_fifos_x
      for (
          binner_raster_y = 0; binner_raster_y < NUM_BINS_Y; binner_raster_y++
      ) begin : gen_binner_raster_fifos_y
        // FIFO between binner and raster unit
        logic binner_raster_full;

        sync_fifo #(
            .T(triangle_t),
            .DEPTH(16)  // TODO magic
        ) binner_to_raster_fifo (
            .clk_i          (clk_i),
            .rst_i          (rst_i),

            .rd_en_i        (binner_raster_out_ready[binner_raster_x*NUM_BINS_Y+binner_raster_y]),
            .empty_o        (),
            .rd_data_o      (binner_raster_out_data[binner_raster_x*NUM_BINS_Y+binner_raster_y]),
            .rd_data_valid_o(
                binner_raster_out_data_valid[binner_raster_x * NUM_BINS_Y + binner_raster_y]
            ),

            .wr_en_i        (binner_out_valid[binner_raster_x][binner_raster_y]),
            .wr_data_i      (binner_out_data),
            .full_o         (binner_raster_full)
        );

        // Connect binner outputs to FIFO inputs
        assign binner_out_ready[binner_raster_x][binner_raster_y] = !binner_raster_full;
      end
    end
  endgenerate

  // Raster units
  logic      raster_frag_out_ready[NUM_BINS_X * NUM_BINS_Y];
  logic      raster_frag_out_valid[NUM_BINS_X * NUM_BINS_Y];
  fragment_t raster_frag_out_data [NUM_BINS_X * NUM_BINS_Y];

  genvar bx, by;
  generate
    for (bx = 0; bx < NUM_BINS_X; bx++) begin : gen_raster_units_x
      for (by = 0; by < NUM_BINS_Y; by++) begin : gen_raster_units_y

        raster_shader #(
            .TOP_LEFT_X(bx * BIN_WIDTH),
            .TOP_LEFT_Y(by * BIN_HEIGHT)
        ) raster_shader_inst (
            .clk_i      (clk_i),
            .rst_i      (rst_i),

            // Input iface (from binner FIFOs)
            .in_ready_o (binner_raster_out_ready[bx*NUM_BINS_Y+by]),
            .in_data_i  (binner_raster_out_data[bx*NUM_BINS_Y+by]),
            .in_valid_i (binner_raster_out_data_valid[bx*NUM_BINS_Y+by]),

            // Output iface (to aggregator)
            .out_ready_i(raster_frag_out_ready[bx*NUM_BINS_Y+by]),
            .out_data_o (raster_frag_out_data[bx*NUM_BINS_Y+by]),
            .out_valid_o(raster_frag_out_valid[bx*NUM_BINS_Y+by])
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
            .clk_i      (clk_i),
            .rst_i      (rst_i),

            // input streaming iface
            .in_ready_o (raster_frag_out_ready[fx*NUM_BINS_Y+fy]),
            .in_data_i  (raster_frag_out_data[fx*NUM_BINS_Y+fy]),
            .in_valid_i (raster_frag_out_valid[fx*NUM_BINS_Y+fy]),

            // output streaming iface
            .out_ready_i(frag_out_ready[fx*NUM_BINS_Y+fy]),
            .out_data_o (frag_out_data[fx*NUM_BINS_Y+fy]),
            .out_valid_o(frag_out_valid[fx*NUM_BINS_Y+fy])
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
      .clk_i     (clk_i),
      .rst_i     (rst_i),

      // Input ifaces from raster units
      .in_ready_o(frag_out_ready),
      .in_data_i (frag_out_data),
      .in_valid_i(frag_out_valid),

      // Output iface
      .out_ready_i(out_ready_i),
      .out_data_o (out_data_o),
      .out_valid_o(out_valid_o)
  );


endmodule
