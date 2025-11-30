/*
 * @file /gpu_top.sv
 * @brief
 * Interface adapter from the drawing unit interface to the GPU core.
 * Handles the commands which the user can send to the GPU core.
 *
 * Currently, the only command supported is to pass in a singular vertex through the registers. 
 * -----
 * Last Modified: Sunday, 30th November 2025 6:41 pm
 * -----
 */

`include "types/fixed_point_pkg.svh"
`include "types/rendering_pkg.svh"
`include "types/pixels_pkg.svh"
`include "types/mat4x4_pkg.svh"
`include "types/vertex_pkg.svh"

module gpu_top ( input  logic        clk,             
                 input  logic        reset,
                 input  logic        req,             /* Interface to command */
                 output logic        ack,

                 input  logic [31:0] r0,              /*  General arguments   */
                 input  logic [31:0] r1,
                 input  logic [31:0] r2,
                 input  logic [31:0] r3,
                 input  logic [31:0] r4,
                 input  logic [31:0] r5,
                 input  logic [31:0] r6,
                 input  logic [31:0] r7,
                 output logic        busy,            /*    Status outputs    */
                 output logic        done,

                 output logic        de_req,          /* Framestore interface */
                 input  logic        de_ack,
                 output logic [17:0] de_addr,
                 output logic  [3:0] de_nbyte,
                 output logic        de_rnw,
                 output logic [31:0] de_w_data,
                 input  logic [31:0] de_r_data,

                 input  logic [17:0] display_base,    /* Display status info. */
                 input  logic  [1:0] display_mode,    /*  *May* be used for   */
                 input  logic  [9:0] display_height,  /*  added flexibility.  */
                 input  logic  [9:0] display_width );

  // Imports
  import fixed_point_pkg::*;
  import rendering_pkg::*;
  import pixels_pkg::*;
  import mat4x4_pkg::*;
  import vertex_pkg::*;

  // GPU signals
  logic    in_ready_o;
  vertex_t in_data_i;
  logic    in_valid_i;

  mat4x4_t input_matrix;

  logic          out_ready_i;
  pixel_buffer_t out_data_o;
  logic          out_valid_o;

  // Input matrix set to identity for now
  initial begin
    for (int x = 0; x < 4; x++) begin
      for (int y = 0; y < 4; y++) begin
        if (x == y) begin
            input_matrix.m[x][y] = from_real(1.0); // 1.0 in fixed-point
        end else begin
            input_matrix.m[x][y] = from_real(0.0); // 0.0 in fixed-point
        end
      end
    end
  end

  // GPU instantiation
  gpu gpu_inst (
    .clk_i      (clk),
    .rst_i      (reset),

    .in_ready_o (in_ready_o),
    .in_data_i  (in_data_i),
    .in_valid_i (in_valid_i),

    .in_matrix_i(input_matrix),

    .out_ready_i(out_ready_i),
    .out_data_o (out_data_o),
    .out_valid_o(out_valid_o)
  );

  // Input data handling
  always_ff @ (posedge clk or posedge reset)
  begin
    if (reset)
    begin
      ack         <= 1'b0;
      in_valid_i    <= 1'b0;
    end
    else
    begin
      if (req && !ack && in_ready_o)
      begin
        // Latch parameters into in data
        in_data_i.x <= r0;
        in_data_i.y <= r1;
        in_data_i.z <= r2;
        in_data_i.r <= r3[7:0];
        in_data_i.g <= r4[7:0];
        in_data_i.b <= r5[7:0];

        in_valid_i  <= 1'b1;
        ack       <= 1'b1;
      end
      else
      begin
        ack       <= 1'b0;
        in_valid_i  <= 1'b0;
      end
    end
  end
  
  parameter int B = PIXEL_WIDTH / 8;

  // Output data handling
  always_ff @ (posedge clk or posedge reset)
  begin
    if (reset)
    begin
      out_ready_i   <= 1'b1;
      de_req      <= 1'b0;
    end
    else
    begin
      if (out_valid_o && !de_req)
      begin
        // Latch output data
        de_addr   <= (out_data_o.y * (SCREEN_WIDTH / PIXELS_PER_WORD)) + out_data_o.x;
        for (int i = 0; i < PIXELS_PER_WORD; i++)
        begin
          if (out_data_o.valid_pixels[i])
          begin
            de_w_data[((i + 1)*PIXEL_WIDTH) - 1 -: PIXEL_WIDTH] <= out_data_o.pixels[i];
          end
        end

        for (int i = 0; i < PIXELS_PER_WORD; i++) begin
          de_nbyte[(i+1)*B-1 -: B] = {B{~out_data_o.valid_pixels[i]}};
        end

        out_ready_i <= 1'b0;
        de_req    <= 1'b1;
      end
      else if (de_ack)
      begin
        de_req    <= 1'b0;
        out_ready_i <= 1'b1;
        de_w_data <= 32'h0;
      end
    end
  end

  assign busy      =  !in_ready_o;
  assign done      =  out_valid_o;

  assign de_rnw    =  1'b0;

endmodule
