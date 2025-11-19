/*
 * @file /rtl/stages/binner.sv
 * @brief
 * Binning stage of the GPU pipeline.
 * Aggregates input vertices into triangles and assigns them to screen-space bins for rasterization.
 * 
 * -----
 * Last Modified: Tuesday, 11th November 2025 8:49 pm
 * -----
 */

`include "types/fixed_point.sv"
`include "types/vertex.sv"
`include "types/triangle.sv"
`include "types/rendering_pkg.sv"

import fixed_point_pkg::*;
import vertex_pkg::*;
import triangle_pkg::*;
import rendering_pkg::*;

module Binner #(
    parameter int BIN_WIDTH  = 64,
    parameter int BIN_HEIGHT = 64,
    parameter int NUM_BINS_X = SCREEN_WIDTH / BIN_WIDTH,
    parameter int NUM_BINS_Y = SCREEN_HEIGHT / BIN_HEIGHT
)
(
    input  logic            clk,
    input  logic            rst,

    // input streaming iface
    output logic            in_vert_ready,
    input  vertex_t         in_vert_data,
    input  logic            in_vert_valid,

    // output streaming iface
    input  logic            out_ready[NUM_BINS_X][NUM_BINS_Y],
    output triangle_t       out_data,
    output logic            out_valid[NUM_BINS_X][NUM_BINS_Y]
);
    // Currently split into 3 phases
    // TODO: Check critical path to divide accordingly
    // TODO: Check for backfacing triangles (signed area negative)
    typedef enum logic [1:0] {
        AGGREGATING,
        CALCULATING_BOUNDS,
        DONE
    } state_t;

    state_t state, next_state;
    int vertex_count;
    triangle_t aggregated_triangle;
    // Registered output that persists between CALCULATING_BOUNDS and DONE
    triangle_t out_data_reg;
    // Combinational next value for out_data_reg (computed during CALCULATING_BOUNDS)
    triangle_t next_out_data;

    // Next state sequential logic
    always_ff @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            state <= AGGREGATING;
            vertex_count <= 0;
            out_data_reg <= '{default: '0};
        end
        else
        begin
            if (state == AGGREGATING && in_vert_valid)
            begin
                case (vertex_count)
                    0: aggregated_triangle.v0 <= in_vert_data;
                    1: aggregated_triangle.v1 <= in_vert_data;
                    2: aggregated_triangle.v2 <= in_vert_data;
                endcase

                vertex_count <= vertex_count + 1;
            end

            // Reset vert count before next triangle
            if (state == DONE && next_state == AGGREGATING)
                vertex_count <= 0;
                
            // Latch computed triangle when we transition to DONE from CALCULATING_BOUNDS
            if (state == CALCULATING_BOUNDS && next_state == DONE) begin
                out_data_reg <= next_out_data;
            end

            state <= next_state;
        end
    end


    // Combinatorial logic to determine next state + output logic
    always_comb
    begin
        logic all_bins_ready = 1; // Needed for DONE state, can't declare inside case
        
        // Default
        next_state = state;
        in_vert_ready = 0;
        // default next_out_data to the current registered output so we only change it
        next_out_data = out_data_reg;
        for (int bx = 0; bx < NUM_BINS_X; bx++) 
            for (int by = 0; by < NUM_BINS_Y; by++) 
                out_valid[bx][by] = 0;

        // Output + next state logic
        case (state)
            AGGREGATING: 
            begin
                in_vert_ready = 1;

                // Move to bounds calculation after 3 verts
                if (in_vert_valid && vertex_count == 2)
                    next_state = CALCULATING_BOUNDS;
            end
            CALCULATING_BOUNDS:
            begin
                // Calculate bounding box of triangle in fixed-point temporaries
                fixed_t min_x_fp = aggregated_triangle.v0.x;
                fixed_t max_x_fp = aggregated_triangle.v0.x;
                fixed_t min_y_fp = aggregated_triangle.v0.y;
                fixed_t max_y_fp = aggregated_triangle.v0.y;
                int min_x, max_x, min_y, max_y;
                
                in_vert_ready = 0;

                // Assign triangle data into the combinational next value
                next_out_data = aggregated_triangle;

                if ($signed(aggregated_triangle.v1.x.value) < $signed(min_x_fp.value)) min_x_fp = aggregated_triangle.v1.x;
                if ($signed(aggregated_triangle.v1.x.value) > $signed(max_x_fp.value)) max_x_fp = aggregated_triangle.v1.x;
                if ($signed(aggregated_triangle.v1.y.value) < $signed(min_y_fp.value)) min_y_fp = aggregated_triangle.v1.y;
                if ($signed(aggregated_triangle.v1.y.value) > $signed(max_y_fp.value)) max_y_fp = aggregated_triangle.v1.y;
                if ($signed(aggregated_triangle.v2.x.value) < $signed(min_x_fp.value)) min_x_fp = aggregated_triangle.v2.x;
                if ($signed(aggregated_triangle.v2.x.value) > $signed(max_x_fp.value)) max_x_fp = aggregated_triangle.v2.x;
                if ($signed(aggregated_triangle.v2.y.value) < $signed(min_y_fp.value)) min_y_fp = aggregated_triangle.v2.y;
                if ($signed(aggregated_triangle.v2.y.value) > $signed(max_y_fp.value)) max_y_fp = aggregated_triangle.v2.y;

                // Convert to int (user-provided helper expected) AFTER the display
                min_x = fixed_point_to_int(min_x_fp);
                max_x = fixed_point_to_int(max_x_fp);
                min_y = fixed_point_to_int(min_y_fp);
                max_y = fixed_point_to_int(max_y_fp);                

                // If the triangle is completely off-screen, discard it
                if (next_out_data.max_x < 0 || next_out_data.min_x >= SCREEN_WIDTH ||
                    next_out_data.max_y < 0 || next_out_data.min_y >= SCREEN_HEIGHT)
                begin
                    next_state = AGGREGATING;
                end
                else 
                begin
                    next_state = DONE;
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
            end 
            DONE:
            begin
                in_vert_ready = 0;
                // Done stage needs to figure out which bins to send the triangle to
                // But first, we can only proceed if all target bins are ready
                for (int bx = 0; bx < NUM_BINS_X; bx++) 
                begin
                    for (int by = 0; by < NUM_BINS_Y; by++) 
                    begin
                        int bin_min_x = bx * BIN_WIDTH;
                        int bin_max_x = bin_min_x + BIN_WIDTH - 1;
                        int bin_min_y = by * BIN_HEIGHT;
                        int bin_max_y = bin_min_y + BIN_HEIGHT - 1;

                        // Bit type? never used this before
                        bit overlaps = !(out_data_reg.max_x < bin_min_x || out_data_reg.min_x > bin_max_x ||
                                         out_data_reg.max_y < bin_min_y || out_data_reg.min_y > bin_max_y);

                        if (overlaps && !out_ready[bx][by])
                            all_bins_ready = 0;
                    end
                end

                // If all our bins are ready, we can output to them
                if (all_bins_ready)
                begin
                    for (int bx = 0; bx < NUM_BINS_X; bx++)
                    begin
                        for (int by = 0; by < NUM_BINS_Y; by++) 
                        begin
                            int bin_min_x = bx * BIN_WIDTH;
                            int bin_max_x = bin_min_x + BIN_WIDTH - 1;
                            int bin_min_y = by * BIN_HEIGHT;
                            int bin_max_y = bin_min_y + BIN_HEIGHT - 1;


                            bit overlaps = !(out_data_reg.max_x < bin_min_x || out_data_reg.min_x > bin_max_x ||
                                             out_data_reg.max_y < bin_min_y || out_data_reg.min_y > bin_max_y);

                            if (overlaps)
                                out_valid[bx][by] = 1;
                        end
                    end
                    // Can move to next triangle after outputting, output will be accepted
                    next_state = AGGREGATING; 
                end 
                else
                    // Output won't be accepted yet, so gotta stay in DONE
                    next_state = DONE;
            end
        endcase
    end

    // Drive module output from registered triangle so it persists across cycles
    assign out_data = out_data_reg;

endmodule