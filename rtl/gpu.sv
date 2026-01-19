/*
 * @file /rtl/gpu.sv
 * @brief
 * Top-level module for the GPU design.
 * Instantiaites and connects the various pipeline stages and components.
 * Also inserts FIFO buffers between stages to decouple timing.
 * Exposes signals to show if the GPU is busy processing data or has data to output.
 *
 * -----
 * Last Modified: Sunday, 18th January 2026 10:16 pm
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
    output logic                      out_valid_o,
    output logic                      out_done_o // One cycle pulse when all data has been processed
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
  logic    vs_busy;

  vertex_shader vertex_shader_inst (
      .clk_i      (clk_i),
      .rst_i      (rst_i),

      .in_ready_o (in_ready_o),
      .in_data_i  (in_data_i),
      .in_valid_i (in_valid_i),

      .in_matrix_i(in_matrix_i),

      .out_ready_i(!vs_binner_full),
      .out_data_o (vs_out_data),
      .out_valid_o(vs_out_valid),
      .out_busy_o (vs_busy)
  );

  // VS out -> Binner in FIFO
  logic    vs_binner_full;
  vertex_t vs_binner_out_data;
  logic    vs_binner_out_data_valid;
  logic    vs_binner_empty;

  sync_fifo #(
      .T(vertex_t),
      .DEPTH(128)  // TODO magic
  ) vs_to_binner_fifo (
      .clk_i          (clk_i),
      .rst_i          (rst_i),

      .rd_en_i        (vs_out_ready),
      .empty_o        (vs_binner_empty),
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
  logic      binner_busy;

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
      .out_valid_o    (binner_out_valid),
      .out_busy_o     (binner_busy)
  );

  // Binner -> raster FIFOs
  triangle_t                          binner_raster_out_data      [NUM_BINS_X * NUM_BINS_Y];
  logic                               binner_raster_out_data_valid[NUM_BINS_X * NUM_BINS_Y];
  logic [NUM_BINS_X * NUM_BINS_Y-1:0] binner_raster_empty;
  logic                               binner_raster_out_ready     [NUM_BINS_X * NUM_BINS_Y];

  //`define BINNER_RASTER_FIFOS
  `ifdef BINNER_RASTER_FIFOS
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
            .DEPTH(128)  // TODO magic
        ) binner_to_raster_fifo (
            .clk_i          (clk_i),
            .rst_i          (rst_i),

            .rd_en_i        (binner_raster_out_ready[binner_raster_x*NUM_BINS_Y+binner_raster_y]),
            .empty_o        (binner_raster_empty[binner_raster_x*NUM_BINS_Y+binner_raster_y]),
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
  `else
  // If FIFOs are disabled, connect directly
  genvar direct_binner_raster_x, direct_binner_raster_y;
  generate
    for (
        direct_binner_raster_x = 0; direct_binner_raster_x < NUM_BINS_X; direct_binner_raster_x++
    ) begin : gen_direct_binner_raster_fifos_x
      for (
          direct_binner_raster_y = 0; direct_binner_raster_y < NUM_BINS_Y; direct_binner_raster_y++
      ) begin : gen_direct_binner_raster_fifos_y
        assign binner_raster_out_data[direct_binner_raster_x*NUM_BINS_Y+direct_binner_raster_y] =
          binner_out_data;
        assign binner_raster_out_data_valid[direct_binner_raster_x*NUM_BINS_Y+direct_binner_raster_y] =
          binner_out_valid[direct_binner_raster_x][direct_binner_raster_y];
        assign binner_out_ready[direct_binner_raster_x][direct_binner_raster_y] =
          binner_raster_out_ready[direct_binner_raster_x*NUM_BINS_Y+direct_binner_raster_y];
        assign binner_raster_empty[direct_binner_raster_x*NUM_BINS_Y+direct_binner_raster_y] =
          !binner_out_valid[direct_binner_raster_x][direct_binner_raster_y];
      end
    end
  endgenerate
  `endif // BINNER_RASTER_FIFOS

  // Initial attribute calculator to be shared among raster units
  // TODO: If DSPs permit, could have multiple of these
  logic                    initial_attributes_in_valid[NUM_BINS_X][NUM_BINS_Y];
  logic                    initial_attributes_in_ready[NUM_BINS_X][NUM_BINS_Y];
  integer                  bin_x_i[NUM_BINS_X][NUM_BINS_Y];
  integer                  bin_y_i[NUM_BINS_X][NUM_BINS_Y];
  triangle_pkg::triangle_t triangles_i[NUM_BINS_X][NUM_BINS_Y];

  triangle_attribute_pkg::triangle_attributes_t triangle_attrs;
  logic                                         initial_attributes_out_valid[NUM_BINS_X][NUM_BINS_Y];
  logic                                         initial_attributes_out_ready[NUM_BINS_X][NUM_BINS_Y];

  initial_attributes #(
      .NUM_BINS_X(NUM_BINS_X),
      .NUM_BINS_Y(NUM_BINS_Y)
  ) initial_attributes_inst (
      .clk_i           (clk_i),
      .rst_i           (rst_i),

      .in_valid_i      (initial_attributes_in_valid),
      .in_ready_o      (initial_attributes_in_ready),
      .bin_x_i         (bin_x_i),
      .bin_y_i         (bin_y_i),
      .triangles_i     (triangles_i),

      .out_ready_i     (initial_attributes_out_ready),
      .triangle_attrs_o(triangle_attrs),
      .out_valid_o     (initial_attributes_out_valid)
  );

  // Raster units
  logic                               raster_frag_out_ready[NUM_BINS_X * NUM_BINS_Y];
  logic                               raster_frag_out_valid[NUM_BINS_X * NUM_BINS_Y];
  fragment_t                          raster_frag_out_data [NUM_BINS_X * NUM_BINS_Y];
  logic [NUM_BINS_X * NUM_BINS_Y-1:0] raster_busy;

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
            .in_ready_o (binner_raster_out_ready[bx * NUM_BINS_Y + by]),
            .in_data_i  (binner_raster_out_data[bx * NUM_BINS_Y + by]),
            .in_valid_i (binner_raster_out_data_valid[bx * NUM_BINS_Y + by]),

            // Initial attributes iface
            .in_attrs_ready_o      (initial_attributes_out_ready[bx][by]),
            .attrs_triangle_valid_o(initial_attributes_in_valid[bx][by]),
            .attrs_triangle_o      (triangles_i[bx][by]),
            .attrs_bin_x_o         (bin_x_i[bx][by]),
            .attrs_bin_y_o         (bin_y_i[bx][by]),
            .in_attrs_valid_i      (initial_attributes_out_valid[bx][by]),
            .in_attrs_i            (triangle_attrs),

            // Output iface (to aggregator)
            .out_ready_i(raster_frag_out_ready[bx*NUM_BINS_Y+by]),
            .out_data_o (raster_frag_out_data[bx*NUM_BINS_Y+by]),
            .out_valid_o(raster_frag_out_valid[bx*NUM_BINS_Y+by]),
            .out_busy_o (raster_busy[bx*NUM_BINS_Y+by])
        );

      end
    end
  endgenerate

  // Raster -> Fragment shader
  logic                               frag_out_ready[NUM_BINS_X * NUM_BINS_Y];
  logic                               frag_out_valid[NUM_BINS_X * NUM_BINS_Y];
  pixel_buffer_t                      frag_out_data [NUM_BINS_X * NUM_BINS_Y];
  logic [NUM_BINS_X * NUM_BINS_Y-1:0] frag_busy;

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
            .out_valid_o(frag_out_valid[fx*NUM_BINS_Y+fy]),
            .out_busy_o (frag_busy[fx*NUM_BINS_Y+fy])
        );
      end
    end
  endgenerate

    // Fragment -> aggregator FIFOs
  pixel_buffer_t                      fragment_aggregator_out_data      [NUM_BINS_X * NUM_BINS_Y];
  logic                               fragment_aggregator_out_data_valid[NUM_BINS_X * NUM_BINS_Y];
  logic [NUM_BINS_X * NUM_BINS_Y-1:0] fragment_aggregator_empty;
  logic                               fragment_aggregator_out_ready     [NUM_BINS_X * NUM_BINS_Y];

  genvar fragment_aggregator_x, fragment_aggregator_y;
  generate
    for (
        fragment_aggregator_x = 0; fragment_aggregator_x < NUM_BINS_X; fragment_aggregator_x++
    ) begin : gen_fragment_aggregator_fifos_x
      for (
          fragment_aggregator_y = 0; fragment_aggregator_y < NUM_BINS_Y; fragment_aggregator_y++
      ) begin : gen_fragment_aggregator_fifos_y
        // FIFO between binner and raster unit
        logic fragment_aggregator_full;

        sync_fifo #(
            .T(pixel_buffer_t),
            .DEPTH(2048)  // TODO magic
        ) fragment_to_aggregator_fifo (
            .clk_i          (clk_i),
            .rst_i          (rst_i),

            .rd_en_i        (fragment_aggregator_out_ready[fragment_aggregator_x*NUM_BINS_Y+fragment_aggregator_y]),
            .empty_o        (fragment_aggregator_empty[fragment_aggregator_x*NUM_BINS_Y+fragment_aggregator_y]),
            .rd_data_o      (fragment_aggregator_out_data[fragment_aggregator_x*NUM_BINS_Y+fragment_aggregator_y]),
            .rd_data_valid_o(),

            .wr_en_i        (frag_out_valid[fragment_aggregator_x * NUM_BINS_Y + fragment_aggregator_y]),
            .wr_data_i      (frag_out_data[fragment_aggregator_x * NUM_BINS_Y + fragment_aggregator_y]),
            .full_o         (fragment_aggregator_full)
        );

        // Connect binner outputs to FIFO inputs
        assign frag_out_ready[fragment_aggregator_x * NUM_BINS_Y + fragment_aggregator_y] = !fragment_aggregator_full;
        assign fragment_aggregator_out_data_valid[fragment_aggregator_x * NUM_BINS_Y + fragment_aggregator_y] = 
          !fragment_aggregator_empty[fragment_aggregator_x * NUM_BINS_Y + fragment_aggregator_y];
      end
    end
  endgenerate

  // Pixel aggregator
  sync_fifo_aggregator #(
      .T(pixel_buffer_t),
      .NUM_INPUTS(NUM_BINS_X * NUM_BINS_Y)
  ) pixel_aggregator_inst (
      .clk_i     (clk_i),
      .rst_i     (rst_i),

      // Input ifaces from raster units
      .in_ready_o(fragment_aggregator_out_ready),
      .in_data_i (fragment_aggregator_out_data),
      .in_valid_i(fragment_aggregator_out_data_valid),

      // Output iface
      .out_ready_i(out_ready_i),
      .out_data_o (out_data_o),
      .out_valid_o(out_valid_o)
  );

  // Done signal generation
  // Initially, done is low. When a command is received, we wait for all stages to be not busy, then pulse done high for one cycle.
  typedef enum logic [1:0] {
    IDLE,
    BUSY,
    DONE
  } gpu_done_state_t;

  gpu_done_state_t done_state, done_state_next;
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      done_state <= IDLE;
    end else begin
      done_state <= done_state_next;
    end
  end

  always_comb begin
    // Default next state
    done_state_next = done_state;
    out_done_o      = 1'b0;

    case (done_state)
      IDLE: begin
        // Wait for input valid to start processing
        if (in_valid_i) begin
          done_state_next = BUSY;
        end
      end

      BUSY: begin
        // Wait for all stages to be not busy
        if (
            !vs_busy &&
            !binner_busy &&
            (|raster_busy == 1'b0) && // All raster units not busy
            (|frag_busy == 1'b0) &&   // All fragment shaders not busy
            vs_binner_empty &&        // VS to binner FIFO empty
            (&binner_raster_empty == 1'b1) &&       // Binner to raster FIFOs empty
            (&fragment_aggregator_empty == 1'b1)    // Fragment to aggregator FIFOs empty
        ) begin
          done_state_next = DONE;
        end
      end

      DONE: begin
        // Pulse done signal for one cycle
        out_done_o      = 1'b1;
        done_state_next = IDLE;
      end

      default: begin
        done_state_next = IDLE;
      end
    endcase
  end

endmodule
