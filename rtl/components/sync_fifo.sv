/*
 * @file /rtl/components/sync_fifo.sv
 * @brief
 * Synchronous FIFO (First-In-First-Out) buffer implementation in SystemVerilog.
 * Used between synchronous clock domains to safely pass data, notably pipeline stages in the GPU.
 * Exposes simple interface with ready (empty/full) handshaking.
 *
 * -----
 * Last Modified: Monday, 10th November 2025 10:11 pm
 * -----
 */

module sync_fifo #(
    parameter type T = logic [31:0],
    parameter int DEPTH = 8
) (
    input logic clk,
    input logic rst,

    input  logic rd_en,
    output logic empty,
    output T     rd_data,
    output logic rd_data_valid,

    input  logic wr_en,
    input  T     wr_data,
    output logic full
);
  localparam int WIDTH = $bits(T);
  T fifo[DEPTH];

  logic [$clog2(DEPTH)-1:0] wr_ptr;
  logic [$clog2(DEPTH)-1:0] rd_ptr;

  // Control signal logic
  assign empty = (wr_ptr == rd_ptr);
  assign full  = ((wr_ptr + 1) % DEPTH) == rd_ptr;

  // Reading logic
  always @(posedge clk) begin
    if (rst) begin
      rd_ptr <= '0;
    end else if (rd_en && !empty && !rd_data_valid) begin
      rd_data <= fifo[rd_ptr];
      rd_data_valid <= 1;
      rd_ptr <= rd_ptr + 1;
    end else begin
      rd_data_valid <= 0;
    end
  end

  // Writing logic
  always @(posedge clk) begin
    if (rst) begin
      wr_ptr <= '0;
    end else if (wr_en && !full) begin
      fifo[wr_ptr] <= wr_data;
      wr_ptr <= wr_ptr + 1;
    end
  end

endmodule
