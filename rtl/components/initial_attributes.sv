/*
 * @file /rtl/components/initial_attributes.sv
 * @brief
 * Module to calculate the initial triangle attributes for singular bin.
 * Combinatorially calculates edge functions and colour starts for a given triangle and position.
 * This means one bin's initial attributes may be obtained per cycle.
 *
 * The S750 is heavily limited by DSP availability, so this module allows multiple bins to share 
 * DSPs with another module that calculates initial triangle attributes.
 * 
 * -----
 * Last Modified: Saturday, 29th November 2025 8:21 pm
 * -----
 */

`include "types/triangle_attribute_pkg.svh"
`include "types/rendering_pkg.svh"

module initial_attributes # (
  parameter NUM_BINS_X = 1,
  parameter NUM_BINS_Y = 1
) (
  input  logic                                         clk_i,
  input  logic                                         rst_i,

  input  logic                                         in_valid_i[NUM_BINS_X][NUM_BINS_Y],
  input  triangle_pkg::triangle_t                      triangles_i[NUM_BINS_X][NUM_BINS_Y],
  input  integer                                       bin_x_i[NUM_BINS_X][NUM_BINS_Y],
  input  integer                                       bin_y_i[NUM_BINS_X][NUM_BINS_Y],
  output logic                                         in_ready_o[NUM_BINS_X][NUM_BINS_Y], // May not be required

  output logic                                         out_valid_o[NUM_BINS_X][NUM_BINS_Y],
  output triangle_attribute_pkg::triangle_attributes_t triangle_attrs_o,
  input logic                                          out_ready_i[NUM_BINS_X][NUM_BINS_Y]
);

// Indexes and state
int   idx;  // round-robin start pointer
int   next_idx;

triangle_attribute_pkg::triangle_attributes_t triangle_attrs_o_comb;
logic                                         out_valid_o_comb[NUM_BINS_X][NUM_BINS_Y];

// Sequential logic: Updating the next selected bin
always_ff @(posedge clk_i or posedge rst_i) begin
  if (rst_i) begin
    idx <= 0;
  end else begin
    idx <= next_idx;
    triangle_attrs_o <= triangle_attrs_o_comb;
    for (int i = 0; i < NUM_BINS_X*NUM_BINS_Y; i++) begin
      out_valid_o[i/NUM_BINS_Y][i%NUM_BINS_Y] <= out_valid_o_comb[i/NUM_BINS_Y][i%NUM_BINS_Y];
    end
  end
end

// Combinatorial logic
// Scan from the last selected index for the next valid input
// Once that is valid, assert output valid and calculate attributes
// Then, update the next selected index to start from the next idx on the next cycle
always_comb begin
  logic found;
  int   found_idx;
  found = 0;
  found_idx = 0;
  
  // Default outputs
  for (int i = 0; i < NUM_BINS_X*NUM_BINS_Y; i++) begin
    in_ready_o[i/NUM_BINS_Y][i%NUM_BINS_Y] = 1'b1; // Always ready to accept input
    out_valid_o_comb[i/NUM_BINS_Y][i%NUM_BINS_Y] = 1'b0;
  end

  next_idx = idx;
  triangle_attrs_o_comb = '{default: '0};
  // Scan for next valid input
  for (int i = 0; i < NUM_BINS_X*NUM_BINS_Y; i++) begin
    int j;
    j = (idx + i) % (NUM_BINS_X*NUM_BINS_Y);

    if (in_valid_i[j/NUM_BINS_Y][j%NUM_BINS_Y]) begin
      // Found a valid input
      found = 1;
      found_idx = j;
      break;
    end
  end

  // Now, we drive the output for the selected input if found
  if (found && out_ready_i[found_idx/NUM_BINS_Y][found_idx%NUM_BINS_Y]) begin
    // Calculate initial triangle attributes
    triangle_attrs_o_comb = triangle_attribute_pkg::calculate_initial_attributes(
      triangles_i[found_idx/NUM_BINS_Y][found_idx%NUM_BINS_Y],
      bin_x_i[found_idx/NUM_BINS_Y][found_idx%NUM_BINS_Y],
      bin_y_i[found_idx/NUM_BINS_Y][found_idx%NUM_BINS_Y]
    );

    // First, assert output valid
    out_valid_o_comb[found_idx/NUM_BINS_Y][found_idx%NUM_BINS_Y] = 1'b1;

    // Update next index to start from the next bin on the next cycle
    next_idx = (found_idx + 1) % (NUM_BINS_X*NUM_BINS_Y);
  end

end

endmodule
