/*
 * @file /rtl/stages/raster_shader.sv
 * @brief
 * Main raster stage of the GPU pipeline.
 * The raster stage takes in triangles from the binning stage, and rasterizes them into pixel fragments.
 * Fragments are output in pixel buffer format to be fragment shaded, then written to the output FIFO aggregator.
 *
 * -----
 * Last Modified: Tuesday, 11th November 2025 8:49 pm
 * -----
 */

`include "types/triangle_pkg.svh"
`include "types/pixels_pkg.svh"
`include "types/fragment_pkg.svh"
`include "types/fixed_point_pkg.svh"
`include "types/fixed_point_wide_pkg.svh"
import triangle_pkg::*;
import pixels_pkg::*;
import fragment_pkg::*;
import fixed_point_pkg::*;
import fixed_point_wide_pkg::*;

module raster_shader #(
    parameter int TOP_LEFT_X     = 0,
    parameter int TOP_LEFT_Y     = 0,
    parameter int PIXELS_PER_CYCLE = 32
)
(
    input  logic            clk,
    input  logic            rst,

    // input streaming iface
    output logic            in_ready,
    input  triangle_t       in_data,
    input  logic            in_valid,

    // output streaming iface
    input  logic            out_ready,
    output fragment_t       out_data,
    output logic            out_valid
);

    // Helper function for fragment shading, will be deleted later
    function automatic fragment_t create_fragment(
        int pixel_x, int pixel_y, logic [7:0] r, logic [7:0] g, logic [7:0] b,
        fixed_wide_t e0, fixed_wide_t e1, fixed_wide_t e2, fixed_wide_t area
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

      // Now, let's try Barycentric coordinates to interpolate colour
      // First, calculate lambdas as e/area
      lambda0 = fixed_wide_div(e1, area);
      lambda1 = fixed_wide_div(e2, area);
      lambda2 = fixed_wide_div(e0, area);

      // Next, we (stupidly but fix later) promote the colours to wide fixed point for interpolation and sum them
      r_wide = fixed_wide_add(fixed_wide_add(fixed_wide_mul(from_int(cur_triangle.v0.r), lambda0),
                                              fixed_wide_mul(from_int(cur_triangle.v1.r), lambda1)),
                                              fixed_wide_mul(from_int(cur_triangle.v2.r), lambda2));

      g_wide = fixed_wide_add(fixed_wide_add(fixed_wide_mul(from_int(cur_triangle.v0.g), lambda0),
                                              fixed_wide_mul(from_int(cur_triangle.v1.g), lambda1)),
                                              fixed_wide_mul(from_int(cur_triangle.v2.g), lambda2));

      b_wide = fixed_wide_add(fixed_wide_add(fixed_wide_mul(from_int(cur_triangle.v0.b), lambda0),
                                              fixed_wide_mul(from_int(cur_triangle.v1.b), lambda1)),
                                              fixed_wide_mul(from_int(cur_triangle.v2.b), lambda2));

      // Finally, truncate and shift to (5, 6, 5) bits
      frag.r = to_int8(r_wide);
      frag.g = to_int8(g_wide);
      frag.b = to_int8(b_wide);

      return frag;
    endfunction

    // Current triangle
    triangle_t cur_triangle;

    // Helper signals
    fixed_wide_t x0, y0, x1, y1, x2, y2;
    assign x0 = from_fixed(cur_triangle.v0.x);
    assign y0 = from_fixed(cur_triangle.v0.y);
    assign x1 = from_fixed(cur_triangle.v1.x);
    assign y1 = from_fixed(cur_triangle.v1.y);
    assign x2 = from_fixed(cur_triangle.v2.x);
    assign y2 = from_fixed(cur_triangle.v2.y);

    // Edge function helper (returns signed area)
    function automatic fixed_wide_t edge_function(
        fixed_wide_t px, fixed_wide_t py,
        fixed_wide_t x0, fixed_wide_t y0,
        fixed_wide_t x1, fixed_wide_t y1
    );
        // Use wider intermediates
        fixed_wide_t dxp, dyp, dx, dy, term1, term2;

        // Compute differences (sign-extend to wide type)
        dxp = fixed_wide_sub(px, x0);
        dyp = fixed_wide_sub(py, y0);
        dx  = fixed_wide_sub(x1, x0);
        dy  = fixed_wide_sub(y1, y0);

        // Edge function = (px - x0)*(y1 - y0) - (py - y0)*(x1 - x0)
        term1 = fixed_wide_mul(dxp, dy);
        term2 = fixed_wide_mul(dyp, dx);

        return fixed_wide_sub(term1, term2);
    endfunction

    // For now, we output constant colour pixels for every pixel in the triangle
    // Horribly pipelined, but works for now
    typedef enum logic [1:0] {
        IDLE,
        PROCESSING
    } state_t;

    state_t state, next_state;
    logic [$clog2(SCREEN_WIDTH * SCREEN_HEIGHT):0] cur_index;
    // Each clock edge, we update cur_x and cur_y by this many pixels
    // The combinatorial logic will attempt to process as many pixels as possible per cycle, so this value will be that
    // value if no pixel is in the triangle (we skip them), or the index of the pixel found in the triangle relative
    // to (cur_x, cur_y)
    int next_index;
    int last_index;

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
    assign delta_x_e0 = fixed_wide_sub(y1, y0); // dE/dx = (y0 - y1)
    assign delta_y_e0 = fixed_wide_sub(x0, x1); // dE/dy = (x1 - x0)

    // For edge v1 → v2 (E1)
    assign delta_x_e1 = fixed_wide_sub(y2, y1);
    assign delta_y_e1 = fixed_wide_sub(x1, x2);

    // For edge v2 → v0 (E2)
    assign delta_x_e2 = fixed_wide_sub(y0, y2);
    assign delta_y_e2 = fixed_wide_sub(x2, x0);

    fixed_wide_t top_left_e0, top_left_e1, top_left_e2;

    // This is a lot of signals...
    // Finally, we need to *latch* the incremental edge function values between cycles
    // Including the row start one... it's worth the combinatorial save even if quite verbose
    // Set sequentially (latched)
    fixed_wide_t cur_e0, cur_e1, cur_e2;
    fixed_wide_t cur_e0_row_start, cur_e1_row_start, cur_e2_row_start;

    // Set combinatorially (to be latched next cycle)
    fixed_wide_t next_e0, next_e1, next_e2;
    fixed_wide_t next_e0_row_start, next_e1_row_start, next_e2_row_start;

    // Next, for barycentric coords we need to know the total (signed) area of the tri to optimise
    // TODO: Could pass this in from binner, since binner should calc it anyway for backface culling
    fixed_wide_t tri_area;
    assign tri_area = edge_function(x0, y0, x1, y1, x2, y2);

    // For wrap checking in tile_next
    logic [$clog2(SCREEN_WIDTH):0] wrap_x;

    // Finally, we need to see when we're done with the triangle so we latch the final index
    logic [$clog2(SCREEN_WIDTH * SCREEN_HEIGHT):0] max_index;

    // Next state sequential logic
    always_ff @(posedge clk or posedge rst)
    begin
        // Locals for max checking
        int top_left_x;
        int top_left_y;

        // Annoying but needed for slight combinatorial optimisation
        fixed_wide_t e0;
        fixed_wide_t e1;
        fixed_wide_t e2;

        if (rst)
        begin
            state <= IDLE;
            cur_index <= 0;
        end
        else
            begin
                state <= next_state;

            if (state == IDLE && in_valid)
            begin
                // Start at the maximum of the bin's top-left index and the triangle's bounding-box minimum
                // Compute as integers to avoid width/signedness surprises
                top_left_x = (in_data.min_x > TOP_LEFT_X) ? in_data.min_x : TOP_LEFT_X;
                top_left_y = (in_data.min_y > TOP_LEFT_Y) ? in_data.min_y : TOP_LEFT_Y;

                cur_index <= int'(top_left_x) + int'(top_left_y) * SCREEN_WIDTH;
                wrap_x <= top_left_x;

                // Now, precompute edge function values at the top-left corner
                // TODO: Optimise
                cur_e0 <= edge_function(
                    from_int(top_left_x), from_int(top_left_y), in_data.v0.x,
                    in_data.v0.y, in_data.v1.x, in_data.v1.y
                );

                cur_e1 <= edge_function(
                    from_int(top_left_x), from_int(top_left_y), in_data.v1.x,
                    in_data.v1.y, in_data.v2.x, in_data.v2.y
                );
                cur_e2 <= edge_function(
                    from_int(top_left_x), from_int(top_left_y), in_data.v2.x,
                    in_data.v2.y, in_data.v0.x, in_data.v0.y
                );

                cur_e0_row_start <= edge_function(
                    from_int(top_left_x), from_int(top_left_y), in_data.v0.x,
                    in_data.v0.y, in_data.v1.x, in_data.v1.y
                );
                cur_e1_row_start <= edge_function(
                    from_int(top_left_x), from_int(top_left_y), in_data.v1.x,
                    in_data.v1.y, in_data.v2.x, in_data.v2.y
                );
                cur_e2_row_start <= edge_function(
                    from_int(top_left_x), from_int(top_left_y), in_data.v2.x,
                    in_data.v2.y, in_data.v0.x, in_data.v0.y
                );

                // Finally, compute and latch the minimum index for termination
                max_index <= in_data.max_x + (in_data.max_y) * SCREEN_WIDTH;
                if (((TOP_LEFT_X + BIN_WIDTH) + (TOP_LEFT_Y + BIN_HEIGHT) * SCREEN_WIDTH) <=
                     (in_data.max_x + (in_data.max_y) * SCREEN_WIDTH))
                    max_index <= TOP_LEFT_X + (TOP_LEFT_Y + BIN_HEIGHT) * SCREEN_WIDTH;

                cur_triangle <= in_data;
            end

            // We can increment the current index if we're processing and either haven't output a pixel yet,
            // or the output pixel has been accepted
            else if (state == PROCESSING && (!out_valid || out_ready))
            begin
                cur_index <= next_index;

                // Latch the updated edge function values
                cur_e0 <= next_e0;
                cur_e1 <= next_e1;
                cur_e2 <= next_e2;
                cur_e0_row_start <= next_e0_row_start;
                cur_e1_row_start <= next_e1_row_start;
                cur_e2_row_start <= next_e2_row_start;
            end
        end
    end

    // Helper: advance an index by one pixel but wrap within the tile width
    function automatic int tile_next(input int idx_in, ref bit wrapped);
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
    function automatic fixed_wide_t edge_function_update(
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
        in_ready = 0;
        out_data = '{default: '{default: '0}};
        out_valid = 0;
        next_state = state;

        case (state)
            IDLE:
            begin
                in_ready = 1;
                if (in_valid)
                    next_state = PROCESSING;
            end

            PROCESSING:
            begin
                // We process up to PIXELS_PER_CYCLE pixels this cycle, advancing within the tile
                int candidate = cur_index;

                int last_candidate = last_index;
                bit wrapped; // Flag to indicate if we've wrapped to next row

                // Incremental edge function values
                fixed_wide_t e0 = cur_e0;
                fixed_wide_t e1 = cur_e1;
                fixed_wide_t e2 = cur_e2;

                // In the case of wrapping, we need to reset the edge function values to the start of the new row
                // Therefore we store the row-start values, and increment them upon wrapping
                fixed_wide_t e0_row_start = cur_e0_row_start;
                fixed_wide_t e1_row_start = cur_e1_row_start;
                fixed_wide_t e2_row_start = cur_e2_row_start;

                next_index = cur_index; // default to current if nothing processed
                out_valid = 0;
                // TODO: Bins may be overextending
                for (int step = 0; step < PIXELS_PER_CYCLE && candidate <= max_index; step++)
                begin
                    // Already found a pixel, stop processing
                    if (out_valid)
                        break;

                    // Check if current pixel is inside triangle
                    if ((e0.value >= 0 && e1.value >= 0 && e2.value >= 0) ||
                        // (e0.value >= 0 && e1.value >= 0 && e2.value >= 0))
                        0)
                    begin
                        out_data = create_fragment(
                            candidate % SCREEN_WIDTH, candidate / SCREEN_WIDTH,
                            8'hFF, 8'hFF, 8'hFF, e0, e1, e2, tri_area
                        );
                        out_valid = 1;
                    end

                    // Advance candidate within tile bounds
                    last_candidate = candidate;
                    candidate = tile_next(candidate, wrapped);

                    // Now, we need to update the three edge functions
                    // First we need to check if we have wrapped to the next row
                    if (wrapped) begin
                        // Reset to row-start values and increment by delta_y
                        e0 = edge_function_update(e0_row_start, delta_y_e0);
                        e1 = edge_function_update(e1_row_start, delta_y_e1);
                        e2 = edge_function_update(e2_row_start, delta_y_e2);

                        // Update row-start values for next row
                        e0_row_start = e0;
                        e1_row_start = e1;
                        e2_row_start = e2;
                    end else begin
                        // Normal increment in x direction
                        e0 = edge_function_update(e0, delta_x_e0);
                        e1 = edge_function_update(e1, delta_x_e1);
                        e2 = edge_function_update(e2, delta_x_e2);
                    end
                end

                // Are we done?
                // Now that we know where we terminate, check if we're done
                if ((candidate > max_index) && (out_ready || !out_valid))
                    next_state = IDLE;
                else if (candidate > max_index) begin
                    next_index = max_index; // clamp to end
                end else
                    next_index = candidate;

                // Finally, we need to latch the updated edge function values
                next_e0 = e0;
                next_e1 = e1;
                next_e2 = e2;
                next_e0_row_start = e0_row_start;
                next_e1_row_start = e1_row_start;
                next_e2_row_start = e2_row_start;
            end
        endcase
    end

endmodule
