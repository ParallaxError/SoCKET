/*
 * @file /rtl/stages/binner.sv
 * @brief
 * Binning stage of the GPU pipeline.
 * Aggregates input vertices into triangles and assigns them to screen-space bins for rasterization.
 *
 * -----
 * Last Modified: Thursday, 27th November 2025 9:41 pm
 * -----
 */

`include "types/fixed_point_pkg.svh"
`include "types/fixed_point_wide_pkg.svh"
`include "types/vertex_pkg.svh"
`include "types/triangle_pkg.svh"
`include "types/rendering_pkg.svh"

module binner #(
    parameter int BIN_WIDTH  = 64,
    parameter int BIN_HEIGHT = 64,
    parameter int NUM_BINS_X = rendering_pkg::SCREEN_WIDTH / BIN_WIDTH,
    parameter int NUM_BINS_Y = rendering_pkg::SCREEN_HEIGHT / BIN_HEIGHT
) (
    input  logic                    clk_i,
    input  logic                    rst_i,

    // input streaming iface
    output logic                    in_vert_ready_o,
    input  vertex_pkg::vertex_t     in_vert_data_i,
    input  logic                    in_vert_valid_i,

    // output streaming iface
    input  logic                    out_ready_i[NUM_BINS_X][NUM_BINS_Y],
    output triangle_pkg::triangle_t out_data_o,
    output logic                    out_valid_o[NUM_BINS_X][NUM_BINS_Y]
);
  // Imports
  import fixed_point_pkg::*;
  import fixed_point_wide_pkg::*;
  import vertex_pkg::*;
  import triangle_pkg::*;
  import rendering_pkg::*;

  // Currently split into 3 phases
  // TODO: Check critical path to divide accordingly
  // TODO: Check for backfacing triangles (signed area negative)
  typedef enum logic [1:0] {
    Aggregating,
    CalculatingBounds,
    WaitingForDivider,
    Done
  } state_e;

  state_e    state, next_state;

  int        vertex_count;
  triangle_t aggregated_triangle;

  // Registered output that persists between CalculatingBounds and Done
  triangle_t out_data_reg;

  // Combinational next value for out_data_reg (computed during CalculatingBounds)
  triangle_t next_out_data;

  // 1/area calculation
  // Reciprocal signals
  fixed_wide_t area_reg;
  fixed_wide_t div_output;
  logic   div_in_valid;
  logic   div_out_valid;
  logic   div_ready;

  // Area inverser
  inverse_area inverse_area_inst (
      .clk_i              (clk_i),
      .rst_i              (rst_i),

      .in_ready_o         (div_ready),
      .in_valid_i         (div_in_valid),
      .in_denominator_i   (area_reg),

      .out_ready_i        (state == WaitingForDivider ? 1'b1 : 1'b0),
      .out_data_o         (div_output),
      .out_valid_o        (div_out_valid)
  );

  // Next state sequential logic
  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      state <= Aggregating;
      vertex_count <= 0;
      out_data_reg <= '{default: '0};
    end else begin
      if (state == Aggregating && in_vert_valid_i) begin
        case (vertex_count)
          0: aggregated_triangle.v0 <= in_vert_data_i;
          1: aggregated_triangle.v1 <= in_vert_data_i;
          2: aggregated_triangle.v2 <= in_vert_data_i;
        endcase

        vertex_count <= vertex_count + 1;

        // Latch and calculate edge area when moving to CalculatingBounds
        if (next_state == CalculatingBounds) begin
          // Can't use aggregated_triangle here since it'll be latched *this* cycle
          area_reg <= edge_function(
            aggregated_triangle.v0.x, aggregated_triangle.v0.y,
            aggregated_triangle.v1.x, aggregated_triangle.v1.y,
            in_vert_data_i.x, in_vert_data_i.y
          );
        end
      end

      // Reset vert count if going into Aggregating
      if (state != Aggregating && next_state == Aggregating) vertex_count <= 0;
      
      // Latch computed triangle when we transition to Done from CalculatingBounds
      out_data_reg <= next_out_data;

      state <= next_state;
    end
  end


  // Combinatorial logic to determine next state + output logic
  always_comb begin
    logic all_bins_ready;  // Needed for Done state, can't declare inside case
    all_bins_ready = 1'b1;

    // Default
    next_state = state;
    in_vert_ready_o = 0;
    // default next_out_data to the current registered output so we only change it
    next_out_data = out_data_reg;
    for (int bx = 0; bx < NUM_BINS_X; bx++)
      for (int by = 0; by < NUM_BINS_Y; by++)
        out_valid_o[bx][by] = 0;

    div_in_valid = 1'b0;

    // Output + next state logic
    case (state)
      Aggregating: begin
        in_vert_ready_o = 1;

        // Move to bounds calculation after 3 verts
        if (in_vert_valid_i && vertex_count == 2 && div_ready) next_state = CalculatingBounds;
      end
      CalculatingBounds: begin
        // First set the minimum to vert 0s coords, then we compare against other verts
        fixed_t min_x_fp, max_x_fp, min_y_fp, max_y_fp;
        int min_x, max_x, min_y, max_y;

        // Calculate bounding box of triangle in fixed-point temporaries
        min_x_fp = aggregated_triangle.v0.x;
        max_x_fp = aggregated_triangle.v0.x;
        min_y_fp = aggregated_triangle.v0.y;
        max_y_fp = aggregated_triangle.v0.y;

        in_vert_ready_o = 0;

        // Assign triangle data into the combinational next value
        next_out_data = aggregated_triangle;

        if ($signed(aggregated_triangle.v1.x.value) < $signed(min_x_fp.value))
          min_x_fp = aggregated_triangle.v1.x;
        if ($signed(aggregated_triangle.v1.x.value) > $signed(max_x_fp.value))
          max_x_fp = aggregated_triangle.v1.x;
        if ($signed(aggregated_triangle.v1.y.value) < $signed(min_y_fp.value))
          min_y_fp = aggregated_triangle.v1.y;
        if ($signed(aggregated_triangle.v1.y.value) > $signed(max_y_fp.value))
          max_y_fp = aggregated_triangle.v1.y;
        if ($signed(aggregated_triangle.v2.x.value) < $signed(min_x_fp.value))
          min_x_fp = aggregated_triangle.v2.x;
        if ($signed(aggregated_triangle.v2.x.value) > $signed(max_x_fp.value))
          max_x_fp = aggregated_triangle.v2.x;
        if ($signed(aggregated_triangle.v2.y.value) < $signed(min_y_fp.value))
          min_y_fp = aggregated_triangle.v2.y;
        if ($signed(aggregated_triangle.v2.y.value) > $signed(max_y_fp.value))
          max_y_fp = aggregated_triangle.v2.y;

        // Convert to int (user-provided helper expected) AFTER the display
        min_x = fixed_point_to_int(min_x_fp);
        max_x = fixed_point_to_int(max_x_fp);
        min_y = fixed_point_to_int(min_y_fp);
        max_y = fixed_point_to_int(max_y_fp);

        // If the triangle is completely off-screen, discard it
        if ($signed(max_x) < 0 || min_x >= SCREEN_WIDTH || $signed(max_y) < 0 || min_y >= SCREEN_HEIGHT)
        begin
          next_state = Aggregating;
        end else begin
          next_state = WaitingForDivider; // Otherwise we wait for the divider
        end

        // Otherwise, we clip to screen bounds
        if (min_x < 0) min_x = 0;
        if (max_x >= SCREEN_WIDTH) max_x = SCREEN_WIDTH - 1;
        if (min_y < 0) min_y = 0;
        if (max_y >= SCREEN_HEIGHT) max_y = SCREEN_HEIGHT - 1;

        // Truncate by populating structure members
        next_out_data.min_x = min_x;
        next_out_data.max_x = max_x;
        next_out_data.min_y = min_y;
        next_out_data.max_y = max_y;

        // While we do this, populate reciprocal unit to calculate 1/a
        div_in_valid = 1'b1;
      end
      WaitingForDivider: begin
        in_vert_ready_o = 0;

        // When reciprocal output valid, latch it and move to Done
        if (div_out_valid) begin
          // Latch inverse area
          next_out_data.inverse_area = div_output;
          if ($signed(div_output.value) < 0)
            next_state = Aggregating; // Backfacing triangle, discard
          else
            next_state = Done;
        end
      end
      Done: begin
        in_vert_ready_o = 0;
        // Done stage needs to figure out which bins to send the triangle to
        // But first, we can only proceed if all target bins are ready
        for (int bx = 0; bx < NUM_BINS_X; bx++) begin
          for (int by = 0; by < NUM_BINS_Y; by++) begin
            // Locals
            int bin_min_x, bin_max_x, bin_min_y, bin_max_y;
            logic overlaps;

            // Calculate bin bounds
            bin_min_x = bx * BIN_WIDTH;
            bin_max_x = bin_min_x + BIN_WIDTH - 1;
            bin_min_y = by * BIN_HEIGHT;
            bin_max_y = bin_min_y + BIN_HEIGHT - 1;

            overlaps = !(out_data_reg.max_x < bin_min_x || out_data_reg.min_x > bin_max_x ||
              out_data_reg.max_y < bin_min_y || out_data_reg.min_y > bin_max_y);

            if (overlaps && !out_ready_i[bx][by]) all_bins_ready = 0;
          end
        end

        // If all our bins are ready, we can output to them
        if (all_bins_ready) begin
          for (int bx = 0; bx < NUM_BINS_X; bx++) begin
            for (int by = 0; by < NUM_BINS_Y; by++) begin
              int bin_min_x, bin_max_x, bin_min_y, bin_max_y;
              logic overlaps;

              // Calculate bin bounds
              bin_min_x = bx * BIN_WIDTH;
              bin_max_x = bin_min_x + BIN_WIDTH - 1;
              bin_min_y = by * BIN_HEIGHT;
              bin_max_y = bin_min_y + BIN_HEIGHT - 1;

              overlaps = !(out_data_reg.max_x < bin_min_x || out_data_reg.min_x > bin_max_x ||
                  out_data_reg.max_y < bin_min_y || out_data_reg.min_y > bin_max_y);

              if (overlaps) out_valid_o[bx][by] = 1;
            end
          end
          // Can move to next triangle after outputting, output will be accepted
          next_state = Aggregating;
        end else
          // Output won't be accepted yet, so gotta stay in Done
          next_state = Done;
      end
      default: 
      begin
        next_state = Aggregating;
      end
    endcase
  end

  // Drive module output from registered triangle so it persists across cycles
  assign out_data_o = out_data_reg;

endmodule
