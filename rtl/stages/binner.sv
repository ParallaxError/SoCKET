/*
 * @file /rtl/stages/binner.sv
 * @brief
 * Binning stage of the GPU pipeline.
 * Aggregates input vertices into triangles and assigns them to screen-space bins for rasterization.
 *
 * -----
 * Last Modified: Sunday, 18th January 2026 10:17 pm
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
    output logic                    out_valid_o[NUM_BINS_X][NUM_BINS_Y],
    output logic                    out_busy_o
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
  typedef enum logic [2:0] {
    Aggregating,
    CalculatingBounds,
    SetupDivider,
    WaitingForDivider,
    CalculatingDeltas,
    Done
  } state_e;

  typedef enum logic [2:0] {
    CalculatingRed,
    CalculatingBlue,
    CalculatingGreen
  } current_delta_e;

  state_e         state, next_state;
  current_delta_e current_delta;
  logic [1:0]     vertex_count;

  // Combinatorially driven triangle output
  triangle_t out_data_comb;
  // Next-cycle registered output valid signals (break comb loops)
  logic      next_out_valid[NUM_BINS_X][NUM_BINS_Y];

  // 1/area calculation
  // Reciprocal signals
  fixed_wide_t area_reg;
  fixed_wide_t area_reg_pipe; // Violates timing otherwise, extra cycle for setup
  logic[0:0]   setup_counter;
  fixed_wide_t div_output;
  fixed_wide_t inverse_area_reg;
  logic        div_in_valid;
  logic        div_out_valid;
  logic        div_ready;

  // Delta calculation
  // Can calculate one delta attribute per cycle
  logic [7:0] current_attribute_v0, current_attribute_v1, current_attribute_v2;
  fixed_wide_t current_dx, current_dy;

  // Area inverser
  inverse_area inverse_area_inst (
      .clk_i              (clk_i),
      .rst_i              (rst_i),

      .in_ready_o         (div_ready),
      .in_valid_i         (div_in_valid),
      .in_denominator_i   (area_reg_pipe),

      .out_ready_i        ((state == SetupDivider || state == WaitingForDivider) ? 1'b1 : 1'b0),
      .out_data_o         (div_output),
      .out_valid_o        (div_out_valid)
  );

  // Next state sequential logic
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state <= Aggregating;
      current_delta <= CalculatingRed;
      vertex_count <= 0;
      out_data_o <= '{default: '0};
      area_reg <= '0;
      setup_counter <= '0;
      inverse_area_reg <= '0;

      current_attribute_v0 <= '0;
      current_attribute_v1 <= '0;
      current_attribute_v2 <= '0;

      // Clear registered output valids
      for (int bx = 0; bx < NUM_BINS_X; bx++)
        for (int by = 0; by < NUM_BINS_Y; by++)
          out_valid_o[bx][by] <= 1'b0;
    end else begin
      if (state == Aggregating && in_vert_valid_i) begin
        case (vertex_count)
          0: out_data_o.v0 <= in_vert_data_i;
          1: out_data_o.v1 <= in_vert_data_i;
          2: out_data_o.v2 <= in_vert_data_i;
        endcase

        vertex_count <= vertex_count + 1;

        // Latch and calculate edge area when moving to CalculatingBounds
        if (next_state == CalculatingBounds) begin
          // Can't use out_data_o here since it'll be latched *this* cycle
          area_reg <= edge_function(
            out_data_o.v0.x, out_data_o.v0.y,
            out_data_o.v1.x, out_data_o.v1.y,
            in_vert_data_i.x, in_vert_data_i.y
          );
        end
        // area_reg_pipe is captured when moving from CalculatingBounds -> SetupDivider
      end
      else if (state == CalculatingBounds && next_state == SetupDivider) begin
        // Latch bounds from comb reg
        out_data_o.min_x <= out_data_comb.min_x;
        out_data_o.max_x <= out_data_comb.max_x;
        out_data_o.min_y <= out_data_comb.min_y;
        out_data_o.max_y <= out_data_comb.max_y; 
        // Capture the pipelined area for the reciprocal unit
        area_reg_pipe <= area_reg;
      end
      else if (state == WaitingForDivider && next_state == CalculatingDeltas) begin
        // Latch inverse area
        inverse_area_reg <= div_output;
        // Start by calculating red deltas
        current_delta <= CalculatingRed;
        current_attribute_v0 <= out_data_o.v0.r;
        current_attribute_v1 <= out_data_o.v1.r;
        current_attribute_v2 <= out_data_o.v2.r;
      end
      else if (state == CalculatingDeltas) begin
        // Latch deltas depending on state and move to next attribute
        case (current_delta)
          CalculatingRed: begin
            out_data_o.R_dx <= current_dx;
            out_data_o.R_dy <= current_dy;
            // Move to blue
            current_delta <= CalculatingBlue;
            current_attribute_v0 <= out_data_o.v0.b;
            current_attribute_v1 <= out_data_o.v1.b;
            current_attribute_v2 <= out_data_o.v2.b;
          end
          CalculatingBlue: begin
            out_data_o.B_dx <= current_dx;
            out_data_o.B_dy <= current_dy;
            // Move to green
            current_delta <= CalculatingGreen;
            current_attribute_v0 <= out_data_o.v0.g;
            current_attribute_v1 <= out_data_o.v1.g;
            current_attribute_v2 <= out_data_o.v2.g;
          end
          CalculatingGreen: begin
            out_data_o.G_dx <= current_dx;
            out_data_o.G_dy <= current_dy;
            // All done with deltas
          end
          default: ;
        endcase
      end

      if (state == SetupDivider)
      begin
        if (setup_counter == 0)
          setup_counter <= 1;
        else
          setup_counter <= 0; // Shouldn't hit here but just in case
      end
      else
        setup_counter <= 0;

      // Reset vert count if going into Aggregating
      if (state != Aggregating && next_state == Aggregating) vertex_count <= 0;

      // Register the next-cycle out_valid signals
      for (int bx = 0; bx < NUM_BINS_X; bx++)
        for (int by = 0; by < NUM_BINS_Y; by++)
          out_valid_o[bx][by] <= next_out_valid[bx][by];

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
    out_data_comb = out_data_o;

    for (int bx = 0; bx < NUM_BINS_X; bx++)
      for (int by = 0; by < NUM_BINS_Y; by++)
        next_out_valid[bx][by] = 1'b0;

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
        min_x_fp = out_data_o.v0.x;
        max_x_fp = out_data_o.v0.x;
        min_y_fp = out_data_o.v0.y;
        max_y_fp = out_data_o.v0.y;

        in_vert_ready_o = 0;

        if ($signed(out_data_o.v1.x.value) < $signed(min_x_fp.value))
          min_x_fp = out_data_o.v1.x;
        if ($signed(out_data_o.v1.x.value) > $signed(max_x_fp.value))
          max_x_fp = out_data_o.v1.x;
        if ($signed(out_data_o.v1.y.value) < $signed(min_y_fp.value))
          min_y_fp = out_data_o.v1.y;
        if ($signed(out_data_o.v1.y.value) > $signed(max_y_fp.value))
          max_y_fp = out_data_o.v1.y;
        if ($signed(out_data_o.v2.x.value) < $signed(min_x_fp.value))
          min_x_fp = out_data_o.v2.x;
        if ($signed(out_data_o.v2.x.value) > $signed(max_x_fp.value))
          max_x_fp = out_data_o.v2.x;
        if ($signed(out_data_o.v2.y.value) < $signed(min_y_fp.value))
          min_y_fp = out_data_o.v2.y;
        if ($signed(out_data_o.v2.y.value) > $signed(max_y_fp.value))
          max_y_fp = out_data_o.v2.y;

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
          next_state = SetupDivider; // Otherwise we pass to divider for 1/a
        end

        // Otherwise, we clip to screen bounds
        if (min_x < 0) min_x = 0;
        if (max_x >= SCREEN_WIDTH) max_x = SCREEN_WIDTH - 1;
        if (min_y < 0) min_y = 0;
        if (max_y >= SCREEN_HEIGHT) max_y = SCREEN_HEIGHT - 1;

        // Truncate by populating structure members
        out_data_comb.min_x = min_x;
        out_data_comb.max_x = max_x;
        out_data_comb.min_y = min_y;
        out_data_comb.max_y = max_y;
      end
      SetupDivider: begin
        // Wait state for timing: 7s50 needed two extra cycles when implemented
        if (setup_counter == 1)
          next_state = WaitingForDivider;
      end
      WaitingForDivider: begin
        in_vert_ready_o = 0;
        div_in_valid = 1'b1;

        // When reciprocal output valid, latch it and move to Done
        if (div_out_valid) begin
          if ($signed(div_output.value) < 0)
            next_state = Aggregating; // Backfacing triangle, discard
          else
            next_state = CalculatingDeltas;
        end
      end
      CalculatingDeltas: begin
        // Calculate deltas for current attribute
        current_dx = fixed_wide_mul(
                fixed_wide_sub(
                    fixed_wide_mul(
                        wide_from_int(
                            $signed({1'b0, current_attribute_v1}) -
                            $signed({1'b0, current_attribute_v0})
                        ),
                        from_fixed(fixed_point_sub(out_data_o.v0.y, out_data_o.v2.y))
                    ),
                    fixed_wide_mul(
                        wide_from_int(
                            $signed({1'b0, current_attribute_v2}) -
                            $signed({1'b0, current_attribute_v0})
                        ),
                        from_fixed(fixed_point_sub(out_data_o.v0.y, out_data_o.v1.y))
                    )
                ),
                inverse_area_reg
            );

        current_dy = fixed_wide_mul(
                fixed_wide_sub(
                    fixed_wide_mul(
                        wide_from_int(
                            $signed({1'b0, current_attribute_v2}) -
                            $signed({1'b0, current_attribute_v0})
                        ),
                        from_fixed(fixed_point_sub(out_data_o.v0.x, out_data_o.v1.x))
                    ),
                    fixed_wide_mul(
                        wide_from_int(
                            $signed({1'b0, current_attribute_v1}) -
                            $signed({1'b0, current_attribute_v0})
                        ),
                        from_fixed(fixed_point_sub(out_data_o.v0.x, out_data_o.v2.x))
                    )
                ),
                inverse_area_reg
            );

        if (current_delta == CalculatingGreen) begin
          // Last attribute calculated, move to Done
          next_state = Done;
        end else begin
          next_state = CalculatingDeltas;
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

            overlaps = !(out_data_o.max_x < bin_min_x || out_data_o.min_x > bin_max_x ||
              out_data_o.max_y < bin_min_y || out_data_o.min_y > bin_max_y);

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

              overlaps = !(out_data_o.max_x < bin_min_x || out_data_o.min_x > bin_max_x ||
                  out_data_o.max_y < bin_min_y || out_data_o.min_y > bin_max_y);

              if (overlaps) next_out_valid[bx][by] = 1;
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

  assign out_busy_o = (state != Aggregating) || vertex_count != 0;

endmodule
