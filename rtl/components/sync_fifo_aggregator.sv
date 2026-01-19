/*
 * @file /rtl/components/sync_fifo_aggregator.sv
 * @brief
 * Synchronous round-robin FIFO stream aggregator.
 * Used to combine the raster units FIFOs into a single output stream.
 *
 * -----
 * Last Modified: Sunday, 18th January 2026 10:17 pm
 * -----
 */

module sync_fifo_aggregator #(
    parameter type T = logic [31:0],
    parameter int  NUM_INPUTS = 4
) (
    input  logic clk_i,
    input  logic rst_i,

    // Input interfaces
    input  T     in_data_i [NUM_INPUTS],
    input  logic in_valid_i[NUM_INPUTS],

    // Per-input ready signals so each producer can be gated independently
    output logic in_ready_o[NUM_INPUTS],

    // Output interface
    input  logic out_ready_i,
    output T     out_data_o,
    output logic out_valid_o
);

  // Helper to produce a zero-initialised value of the generic type T
  // Stops Verilator from having a fit if I just use '0 directly
  function automatic T zero_T();
    zero_T = '{default: '0};
  endfunction

  // Indexes and state
  logic [$clog2(NUM_INPUTS)-1:0] idx;  // round-robin start pointer
  logic [$clog2(NUM_INPUTS)-1:0] next_idx;

  // Sequential logic: Updating the next selected input
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      idx <= 0;
    end else begin
      idx <= next_idx;
    end
  end

  // Combinatorial logic
  // Scan from the last selected index for the next valid input
  // Once that is valid, assert output valid and forward data
  // Then, update the next selected index to start from the next idx on the next cycle
  always_comb begin
    logic                          found;
    logic [$clog2(NUM_INPUTS)-1:0] found_idx;
    found = 0;
    found_idx = 0;
    out_valid_o = 1'b0;

    // Default outputs
    out_data_o = zero_T();
    for (int i = 0; i < NUM_INPUTS; i++) begin
      in_ready_o[i] = 1'b0;
    end

    next_idx = idx;
    // Scan for next valid input
    for (int i = 0; i < NUM_INPUTS; i++) begin
      logic [$clog2(NUM_INPUTS)-1:0] j;
      j = (idx + i) % NUM_INPUTS;

      if (in_valid_i[j]) begin
        // Found a valid input
        found = 1;
        found_idx = j;
        break;
      end
    end

  // Drive the output for the selected input if found
    if (found && out_ready_i) begin
      // Forward ready signal to producer
      in_ready_o[found_idx] = 1'b1;

      out_data_o = in_data_i[found_idx];
      out_valid_o = 1'b1;
      next_idx = (found_idx + 1) % NUM_INPUTS;
    end
  end

endmodule
