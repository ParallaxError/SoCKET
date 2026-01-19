/*
 * @file /rtl/stages/raster_shader.sv
 * @brief
 * Main raster stage of the GPU pipeline.
 * The raster stage takes in triangles from the binning stage, and rasterizes them into pixel fragments.
 * Fragments are output in pixel buffer format to be fragment shaded, then written to the output FIFO aggregator.
 *
 * -----
 * Last Modified: Sunday, 18th January 2026 10:17 pm
 * -----
 */

`include "types/fixed_point_pkg.svh"
`include "types/fixed_point_wide_pkg.svh"
`include "types/rendering_pkg.svh"
`include "types/pixels_pkg.svh"
`include "types/triangle_pkg.svh"
`include "types/triangle_attribute_pkg.svh"
`include "types/fragment_pkg.svh"

module raster_shader #(
    parameter int TOP_LEFT_X     = 0,
    parameter int TOP_LEFT_Y     = 0,
    parameter int PIXELS_PER_CYCLE = 1
)
(
    input  logic                                         clk_i,
    input  logic                                         rst_i,

    // input streaming iface
    output logic                                         in_ready_o,
    input  triangle_pkg::triangle_t                      in_data_i,
    input  logic                                         in_valid_i,

    // Initial attributes from initial_attributes module
    // TODO: Should incorporate if attributes module is ready for input
    output logic                                         in_attrs_ready_o,
    output logic                                         attrs_triangle_valid_o,
    output  triangle_pkg::triangle_t                     attrs_triangle_o,
    output integer                                       attrs_bin_x_o,
    output integer                                       attrs_bin_y_o,
    input  logic                                         in_attrs_valid_i,
    input  triangle_attribute_pkg::triangle_attributes_t in_attrs_i,

    // output streaming iface
    input  logic                                         out_ready_i,
    output fragment_pkg::fragment_t                      out_data_o,
    output logic                                         out_valid_o,
    output logic                                         out_busy_o
);
  // Imports
  import rendering_pkg::*;
  import fixed_point_pkg::*;
  import fixed_point_wide_pkg::*;
  import pixels_pkg::*;
  import triangle_pkg::*;
  import fragment_pkg::*;

  // Helper function for fragment shading, will be deleted later
  function automatic fragment_t create_fragment(
      int pixel_x, int pixel_y, logic [7:0] r, logic [7:0] g, logic [7:0] b,
      fixed_wide_t e0, fixed_wide_t e1, fixed_wide_t e2
  );
    fragment_t frag;
    fixed_wide_t lambda0, lambda1, lambda2;
    fixed_wide_t r_wide, g_wide, b_wide;

    int pixel_index;
    // Initialize to zero
    frag = '{default: '{default: '0}};
    
    // Divide by pixels per word to get x,y in the pixel buffer
    pixel_index = pixel_x % PIXELS_PER_WORD;

    frag.x = pixel_x;
    frag.y = pixel_y;

    // Finally, truncate and shift to (5, 6, 5) bits
    frag.r = r;
    frag.g = g;
    frag.b = b;

    return frag;
  endfunction

  // Current triangle
  triangle_t cur_triangle;

  // Helper signals
  fixed_wide_t tri_x0, tri_y0, tri_x1, tri_y1, tri_x2, tri_y2;
  assign tri_x0 = from_fixed(cur_triangle.v0.x);
  assign tri_y0 = from_fixed(cur_triangle.v0.y);
  assign tri_x1 = from_fixed(cur_triangle.v1.x);
  assign tri_y1 = from_fixed(cur_triangle.v1.y);
  assign tri_x2 = from_fixed(cur_triangle.v2.x);
  assign tri_y2 = from_fixed(cur_triangle.v2.y);

  // For now, we output constant colour pixels for every pixel in the triangle
  // Horribly pipelined, but works for now
  typedef enum logic [1:0] {
      Idle,
      InitialisingAttributes,
      Processing
  } state_e;

  state_e state, next_state;

  logic [$clog2(SCREEN_WIDTH*SCREEN_HEIGHT):0] cur_index;

  // Each clock edge, we update cur_x and cur_y by this many pixels
  // The combinatorial logic will attempt to process as many pixels as possible per cycle, so this value will be that
  // value if no pixel is in the triangle (we skip them), or the index of the pixel found in the triangle relative
  // to (cur_x, cur_y)
  logic [$clog2(SCREEN_WIDTH*SCREEN_HEIGHT):0] next_index;

  // Incremental edge function!
  // So the edge function is defined as (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  // Since a and b are constant and c.x and c.y increase by 1 per step, we can precompute the deltas
  // Take the cases where c.x increments by 1, we get (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * ((c.x + 1) - a.x)
  // Lets subtract this from the original edge function
  //   (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  // - (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * ((c.x + 1) - a.x)
  // = (b.y - a.y)((c.x - a.x) - (c.x + 1 - a.x)) = -(b.y - a.y)
  // In the case where y instead increments we get +(b.x - a.x)
  // Therefore, we calculate these deltas once per triangle and use them to incrementally update edge function values per pixel
  fixed_wide_t delta_x_e0, delta_y_e0;
  fixed_wide_t delta_x_e1, delta_y_e1;
  fixed_wide_t delta_x_e2, delta_y_e2;

  // For edge v0→v1
  assign delta_x_e0 = fixed_wide_sub(tri_y1, tri_y0); // dE/dx = (y1 - y0)
  assign delta_y_e0 = fixed_wide_sub(tri_x0, tri_x1); // dE/dy = (x0 - x1)

  // For edge v1 → v2 (E1)
  assign delta_x_e1 = fixed_wide_sub(tri_y2, tri_y1);
  assign delta_y_e1 = fixed_wide_sub(tri_x1, tri_x2);

  // For edge v2 → v0 (E2)
  assign delta_x_e2 = fixed_wide_sub(tri_y0, tri_y2);
  assign delta_y_e2 = fixed_wide_sub(tri_x2, tri_x0);

  // This is a lot of signals...
  // Finally, we need to *latch* the incremental edge function values between cycles
  // Including the row start one... it's worth the combinatorial save even if quite verbose
  // Set sequentially (latched)
  fixed_wide_t cur_e0, cur_e1, cur_e2;
  fixed_wide_t cur_e0_row_start, cur_e1_row_start, cur_e2_row_start;

  // Set combinatorially (to be latched next cycle)
  fixed_wide_t next_e0, next_e1, next_e2;
  fixed_wide_t next_e0_row_start, next_e1_row_start, next_e2_row_start;

  // Initial attributes
  fixed_wide_t cur_R, cur_G, cur_B;
  fixed_wide_t cur_R_row_start, cur_G_row_start, cur_B_row_start;

  // Combinatorial next values
  fixed_wide_t next_R, next_G, next_B;
  fixed_wide_t next_R_row_start, next_G_row_start, next_B_row_start;

  // For wrap checking in tile_next
  logic [$clog2(SCREEN_WIDTH):0] wrap_x;

  // Finally, we need to see when we're done with the triangle so we latch the final index
  logic [$clog2(SCREEN_WIDTH * SCREEN_HEIGHT):0] max_index;

  // Next state sequential logic
  always_ff @(posedge clk_i)
  begin
      // Locals for max checking
      int top_left_x;
      int top_left_y;

      if (rst_i)
      begin
          state <= Idle;
          cur_index <= 0;
      end
      else
      begin
        state <= next_state;

        if (state == Idle && in_valid_i)
        begin
          // Needed for initial attribute calculation
          fixed_wide_t x_rel, y_rel;

          // Start at the maximum of the bin's top-left index and the triangle's bounding-box minimum
          // Compute as integers to avoid width/signedness surprises
          top_left_x = (in_data_i.min_x > TOP_LEFT_X) ? in_data_i.min_x : TOP_LEFT_X;
          top_left_y = (in_data_i.min_y > TOP_LEFT_Y) ? in_data_i.min_y : TOP_LEFT_Y;

          cur_index <= int'(top_left_x) + int'(top_left_y) * SCREEN_WIDTH;
          wrap_x <= top_left_x;

          // Set output of attributes module
          attrs_bin_x_o <= top_left_x;
          attrs_bin_y_o <= top_left_y;

          // Finally, compute and latch the minimum index for termination
          max_index <= in_data_i.max_x + (in_data_i.max_y) * SCREEN_WIDTH;
          if (((TOP_LEFT_X + BIN_WIDTH) + (TOP_LEFT_Y + BIN_HEIGHT) * SCREEN_WIDTH) <=
              (in_data_i.max_x + (in_data_i.max_y) * SCREEN_WIDTH))
              max_index <= TOP_LEFT_X + (TOP_LEFT_Y + BIN_HEIGHT) * SCREEN_WIDTH;

          cur_triangle <= in_data_i;
        end
        else if (state == InitialisingAttributes && next_state == Processing)
        begin
          // Latch attributes
          cur_e0 <= in_attrs_i.e0;
          cur_e1 <= in_attrs_i.e1;
          cur_e2 <= in_attrs_i.e2;

          cur_e0_row_start <= in_attrs_i.e0;
          cur_e1_row_start <= in_attrs_i.e1;
          cur_e2_row_start <= in_attrs_i.e2;

          cur_R <= in_attrs_i.R_start;
          cur_G <= in_attrs_i.G_start;
          cur_B <= in_attrs_i.B_start;

          cur_R_row_start <= in_attrs_i.R_start;
          cur_G_row_start <= in_attrs_i.G_start;
          cur_B_row_start <= in_attrs_i.B_start;
        end
        // We can increment the current index if we're processing and either haven't output a pixel yet,
        // or the output pixel has been accepted
        else if (state == Processing && (!out_valid_o || out_ready_i))
        begin
            cur_index <= next_index;

            // Latch the updated edge function values
            cur_e0 <= next_e0;
            cur_e1 <= next_e1;
            cur_e2 <= next_e2;
            cur_e0_row_start <= next_e0_row_start;
            cur_e1_row_start <= next_e1_row_start;
            cur_e2_row_start <= next_e2_row_start;

            cur_R <= next_R;
            cur_G <= next_G;
            cur_B <= next_B;
            cur_R_row_start <= next_R_row_start;
            cur_G_row_start <= next_G_row_start;
            cur_B_row_start <= next_B_row_start;
        end
      end
  end

  // Helper: advance an index by one pixel but wrap within the tile width
  function automatic int tile_next(input int idx_in, ref logic wrapped);
      int cand_x = idx_in % SCREEN_WIDTH;
      int cand_y = idx_in / SCREEN_WIDTH;
      int tile_right = TOP_LEFT_X + BIN_WIDTH; // exclusive right bound

      if (cand_x + 1 >= tile_right) begin
          // move to next row at the tile's left edge
          wrapped = 1;
          return (cand_y + 1) * SCREEN_WIDTH + wrap_x;
      end else begin
          wrapped = 0;
          return idx_in + 1;
      end
  endfunction

  // Helper: Incremental edge function update
  // Given the previous edge function value at (x, y), compute the edge function at (x + 1, y)
  function automatic fixed_wide_t attribute_update(
      input fixed_wide_t prev, input fixed_wide_t delta
  );
      return fixed_wide_add(prev, delta);
  endfunction

  // Output combinational logic
  // Per cycle, if we are iin idle we go to processing and latch the triangle
  // In outputting, we attempt to process as many pixels as desired per raster unit
  // Then, we increment the current coordinate by that many pixels
  // However, if we find a pixel that is inside the triangle, we output it immediately and wait for the next cycle
  always_comb
  begin
      // Defaults
      in_ready_o = 0;
      out_data_o = '{default: '{default: '0}};
      out_valid_o = 0;
      next_state = state;
      attrs_triangle_o = cur_triangle;
      in_attrs_ready_o = 0;
      attrs_triangle_valid_o = 0;

      case (state)
        Idle:
        begin
          in_ready_o = 1;
          if (in_valid_i)
              next_state = InitialisingAttributes;
        end
        InitialisingAttributes:
        begin
          // Wait for attributes to be valid
          in_attrs_ready_o = 1;
          attrs_triangle_valid_o = 1;

          if (in_attrs_valid_i)
              next_state = Processing;
        end
        Processing:
        begin
          // We process up to PIXELS_PER_CYCLE pixels this cycle, advancing within the tile
          int          candidate;
          logic        wrapped; // Flag to indicate if we've wrapped to next row
          fixed_wide_t e0, e1, e2, e0_row_start, e1_row_start, e2_row_start;

          // Attributes
          fixed_wide_t r_attr, g_attr, b_attr;
          fixed_wide_t r_attr_row_start, g_attr_row_start, b_attr_row_start;

          candidate = cur_index;
          wrapped   = 0;

          // Incremental edge function values
          e0 = cur_e0;
          e1 = cur_e1;
          e2 = cur_e2;

          r_attr = cur_R;
          g_attr = cur_G;
          b_attr = cur_B;

          // In the case of wrapping, we need to reset the edge function values to the start of the new row
          // Therefore we store the row-start values, and increment them upon wrapping
          e0_row_start = cur_e0_row_start;
          e1_row_start = cur_e1_row_start;
          e2_row_start = cur_e2_row_start;

          r_attr_row_start = cur_R_row_start;
          g_attr_row_start = cur_G_row_start;
          b_attr_row_start = cur_B_row_start;

          next_index = cur_index; // default to current if nothing processed
          out_valid_o = 0;
          for (int step = 0; step < PIXELS_PER_CYCLE && candidate <= max_index; step++)
          begin
              // Already found a pixel, stop processing
              if (out_valid_o)
                  break;

              // Check if current pixel is inside triangle
              if ((e0.value >= 0 && e1.value >= 0 && e2.value >= 0) ||
                  // (e0.value >= 0 && e1.value >= 0 && e2.value >= 0))
                  0)
              begin
                out_data_o = create_fragment(
                    candidate % SCREEN_WIDTH, candidate / SCREEN_WIDTH,
                    to_int8(r_attr), to_int8(g_attr), to_int8(b_attr), e0, e1, e2
                );
                out_valid_o = 1;
              end

              // Advance candidate within tile bounds
              candidate = tile_next(candidate, wrapped);

              // Now, we need to update the three edge functions
              // First we need to check if we have wrapped to the next row
              if (wrapped) begin
                  // Reset to row-start values and increment by delta_y
                  e0 = attribute_update(e0_row_start, delta_y_e0);
                  e1 = attribute_update(e1_row_start, delta_y_e1);
                  e2 = attribute_update(e2_row_start, delta_y_e2);

                  r_attr = attribute_update(r_attr_row_start, cur_triangle.R_dy);
                  g_attr = attribute_update(g_attr_row_start, cur_triangle.G_dy);
                  b_attr = attribute_update(b_attr_row_start, cur_triangle.B_dy);

                  // Update row-start values for next row
                  e0_row_start = e0;
                  e1_row_start = e1;
                  e2_row_start = e2;
                  r_attr_row_start = r_attr;
                  g_attr_row_start = g_attr;
                  b_attr_row_start = b_attr;
              end else begin
                  // Normal increment in x direction
                  e0 = attribute_update(e0, delta_x_e0);
                  e1 = attribute_update(e1, delta_x_e1);
                  e2 = attribute_update(e2, delta_x_e2);

                  r_attr = attribute_update(r_attr, cur_triangle.R_dx);
                  g_attr = attribute_update(g_attr, cur_triangle.G_dx);
                  b_attr = attribute_update(b_attr, cur_triangle.B_dx);
              end
          end

          // Are we done?
          // Now that we know where we terminate, check if we're done
          if ((candidate > max_index) && (out_ready_i || !out_valid_o))
              next_state = Idle;
          else if (candidate > max_index) begin
              next_index = max_index; // clamp to end
          end else
              next_index = candidate;

          // Finally, we need to preserve the edge function and attribute values to be latched
          next_e0 = e0;
          next_e1 = e1;
          next_e2 = e2;
          next_e0_row_start = e0_row_start;
          next_e1_row_start = e1_row_start;
          next_e2_row_start = e2_row_start;
          next_R = r_attr;
          next_G = g_attr;
          next_B = b_attr;
          next_R_row_start = r_attr_row_start;
          next_G_row_start = g_attr_row_start;
          next_B_row_start = b_attr_row_start;
        end
        default:
        begin
            next_state = Idle;
        end
      endcase
  end

  assign out_busy_o = state != Idle;

endmodule
