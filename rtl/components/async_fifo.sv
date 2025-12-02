/*
 * @file /rtl/components/async_fifo.sv
 * @brief
 * Asynchronous FIFO for crossing clock domains.
 * Drawing engine and input IFC operate on a 40MHz clock, ideally we can run the GPU core at a higher
 * frequency (e.g. 100MHz) to improve throughput.
 * 
 * -----
 * Last Modified: Sunday, 30th November 2025 2:58 pm
 * -----
 */

module async_fifo #(
    parameter type T = logic [31:0],
    parameter int  DEPTH = 8
) (
    input  logic wr_clk_i,
    input  logic wr_rst_i,
    input  logic rd_clk_i,
    input  logic rd_rst_i,

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

  // Binary and Gray pointers
  logic [$clog2(DEPTH):0] wr_ptr_bin, wr_ptr_bin_next;
  logic [$clog2(DEPTH):0] rd_ptr_bin, rd_ptr_bin_next;

  logic [$clog2(DEPTH):0] wr_ptr_gray, wr_ptr_gray_next;
  logic [$clog2(DEPTH):0] rd_ptr_gray, rd_ptr_gray_next;

  // Binary to gray helper function
  function automatic logic [$clog2(DEPTH):0] bin2gray(input logic [$clog2(DEPTH):0] b);
    return (b >> 1) ^ b;
  endfunction

  // Write domain sequential logic
  always_ff @ (posedge wr_clk_i) begin
    if (wr_rst_i) begin
      wr_ptr_bin <= '0;
      wr_ptr_gray <= '0;
    end else begin
      wr_ptr_bin <= wr_ptr_bin_next;
      wr_ptr_gray <= wr_ptr_gray_next;

      if (wr_en_i && !full_o) begin
        fifo_mem[wr_ptr_bin[$clog2(DEPTH)-1:0]] <= T'(wr_data_i);
      end
    end
  end

  // Next state combinatorial logic (writes)
  always_comb begin
    wr_ptr_bin_next = wr_ptr_bin;
    if (wr_en_i && !full_o) begin
      wr_ptr_bin_next = wr_ptr_bin + 1;
    end
    wr_ptr_gray_next = bin2gray(wr_ptr_bin_next);
  end

  // Read domain sequential logic
  always_ff @ (posedge rd_clk_i) begin
    if (rd_rst_i) begin
      rd_ptr_bin <= '0;
      rd_ptr_gray <= '0;
    end else begin
      rd_ptr_bin <= rd_ptr_bin_next;
      rd_ptr_gray <= rd_ptr_gray_next;

      if (rd_en_i && !empty_o && !rd_data_valid_o) begin
        rd_data_o <= T'(fifo_mem[rd_ptr_bin[$clog2(DEPTH)-1:0]]);
        rd_data_valid_o <= 1;
      end else begin
        rd_data_valid_o <= 0;
      end
    end
  end

  // Next state combinatorial logic (reads)
  always_comb begin
    rd_ptr_bin_next = rd_ptr_bin;
    if (rd_en_i && !empty_o) begin
      rd_ptr_bin_next = rd_ptr_bin + 1;
    end
    rd_ptr_gray_next = bin2gray(rd_ptr_bin_next);
  end

  // Cross domain pointer synchronisation
  logic [$clog2(DEPTH):0] wr_ptr_gray_rd_sync_0, wr_ptr_gray_rd_sync_1;
  logic [$clog2(DEPTH):0] rd_ptr_gray_wr_sync_0, rd_ptr_gray_wr_sync_1;

  always_ff @ (posedge wr_clk_i) begin
    if (wr_rst_i) begin
      rd_ptr_gray_wr_sync_0 <= '0;
      rd_ptr_gray_wr_sync_1 <= '0;
    end else begin
      rd_ptr_gray_wr_sync_0 <= rd_ptr_gray;
      rd_ptr_gray_wr_sync_1 <= rd_ptr_gray_wr_sync_0;
    end
  end

  always_ff @ (posedge rd_clk_i) begin
    if (rd_rst_i) begin
      wr_ptr_gray_rd_sync_0 <= '0;
      wr_ptr_gray_rd_sync_1 <= '0;
    end else begin
      wr_ptr_gray_rd_sync_0 <= wr_ptr_gray;
      wr_ptr_gray_rd_sync_1 <= wr_ptr_gray_rd_sync_0;
    end
  end

  // Full/empty signals
  assign empty_o = (rd_ptr_gray == wr_ptr_gray_rd_sync_1);

  // Not sure if this works
  assign full_o = ( (wr_ptr_gray[$clog2(DEPTH):$clog2(DEPTH)-1] ==
                     ~rd_ptr_gray_wr_sync_1[$clog2(DEPTH):$clog2(DEPTH)-1]) &&
                   (wr_ptr_gray[$clog2(DEPTH)-2:0] ==
                     rd_ptr_gray_wr_sync_1[$clog2(DEPTH)-2:0]) );

endmodule
