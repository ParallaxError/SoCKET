/*
 * @file /rtl/components/sync_fifo.sv
 * @brief
 * Synchronous FIFO (First-In-First-Out) buffer implementation in SystemVerilog.
 * Used between synchronous clock domains to safely pass data, notably pipeline stages in the GPU.
 * Exposes simple interface with ready (empty_o/full_o) handshaking.
 *
 * -----
 * Last Modified: Sunday, 18th January 2026 10:00 pm
 * -----
 */

module sync_fifo #(
    parameter type T = logic [31:0],
    parameter int  DEPTH = 8
) (
    input  logic clk_i,
    input  logic rst_i,

    input  logic rd_en_i,
    output logic empty_o,
    output T     rd_data_o,
    output logic rd_data_valid_o,

    input  logic wr_en_i,
    input  T     wr_data_i,
    output logic full_o
); 
  // Use a flat logic memory so synthesis can infer a single BRAM reliably
  localparam int MEMW = $bits(T);
  (* ram_style = "block" *) logic [MEMW-1:0] fifo_mem [0:DEPTH-1];

  logic [$clog2(DEPTH)-1:0] wr_ptr;
  logic [$clog2(DEPTH)-1:0] rd_ptr;

  // Control signal logic
  assign empty_o = (wr_ptr == rd_ptr);
  assign full_o  = ((wr_ptr + 1) % DEPTH) == rd_ptr;

  // Reading logic
  // TODO: Synchronous reset to infer BRAM, is that ok?
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      rd_ptr <= '0;
    end else if (rd_en_i && !empty_o && !rd_data_valid_o) begin
      rd_data_o <= T'(fifo_mem[rd_ptr]);
      rd_data_valid_o <= 1;
      rd_ptr <= rd_ptr + 1;
    end else begin
      rd_data_valid_o <= 0;
    end
  end

  // Writing logic
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      wr_ptr <= '0;
    end else if (wr_en_i && !full_o) begin
      fifo_mem[wr_ptr] <= T'(wr_data_i);
      wr_ptr <= wr_ptr + 1;
    end
  end

endmodule
