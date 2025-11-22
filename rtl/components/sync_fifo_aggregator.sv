/*
 * @file /rtl/components/sync_fifo_aggregator.sv
 * @brief
 * Synchronous round-robin FIFO stream aggregator.
 * Used to combine the raster units FIFOs into a single output stream.
 *
 * -----
 * Last Modified: Thursday, 6th November 2025 12:27 am
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
  int   idx;  // round-robin start pointer
  int   selected;  // currently selected input index
  logic selected_valid;  // whether a selection is active

  // Registered outputs
  T     out_data_reg;
  logic out_valid_reg;

  // Sequential logic: select next input and forward when downstream accepts
  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      idx <= 0;
      selected <= 0;
      selected_valid <= 0;
      out_data_reg <= zero_T();
      out_valid_reg <= 0;
    end else begin
      if (!selected_valid) begin
        // find next available valid stream in round-robin order
        logic found;
        found = 0;

        for (int i = 0; i < NUM_INPUTS; i++) begin
          int j;
          j = (idx + i) % NUM_INPUTS;

          if (in_valid_i[j]) begin
            selected <= j;
            selected_valid <= 1;
            out_data_reg <= in_data_i[j];
            out_valid_reg <= 1;
            found = 1;
            break;
          end
        end
        if (!found) begin
          out_valid_reg <= 0;
        end
      end else begin
        // We have a selected input being presented to the consumer
        if (out_ready_i) begin
          // handshake complete: advance pointer and clear selection
          idx <= (selected + 1) % NUM_INPUTS;
          selected_valid <= 0;
          out_valid_reg <= 0;
        end
      end
    end
  end

  // Drive outputs
  assign out_data_o  = out_data_reg;
  assign out_valid_o = out_valid_reg;

  // Per-input ready: only the selected input sees ready and only when downstream ready
  genvar gi;
  generate
    for (gi = 0; gi < NUM_INPUTS; gi++) begin : gen_in_ready
      assign in_ready_o[gi] = (selected_valid && (selected == gi)) ? out_ready_i : 1'b0;
    end
  endgenerate

endmodule
