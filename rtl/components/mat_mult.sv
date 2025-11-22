/*
 * @file /rtl/components/mat_mult.sv
 * @brief
 * Sequential vector * matrix multiplication unit for 4x4 transformation matrices.
 * Currently pipelined in 4 cycles, one for each row of the matrix.
 *
 * -----
 * Last Modified: Tuesday, 11th November 2025 7:10 pm
 * -----
 */

`include "types/fixed_point_pkg.svh"
`include "types/mat4x4_pkg.svh"
`include "types/vertex_pkg.svh"

import fixed_point_pkg::*;
import mat4x4_pkg::*;
import vertex_pkg::*;

module mat_mult (
    input logic clk,
    input logic rst,

    // Input vector
    input  logic    in_vec_valid,
    output logic    in_vec_ready,
    input  vertex_t in_vec,

    // Input matrix
    input mat4x4_t in_mat,

    // Output vector
    output logic    out_vec_valid,
    output vertex_t out_vec,
    output fixed_t  w,
    input  logic    out_vec_ready
);
  // Dot product function for fixed point vectors
  // This becomes a DSP block in synthesis, so should be efficient
  // However, the Spartan 7 has 120 DSPs so during placement have to see how many matmults we can have
  function automatic fixed_t fixed_point_dot_product(input fixed_t a[4], input vertex_t b);
    fixed_t result;
    begin
      result = fixed_t'(0);
      result = fixed_point_add(result, fixed_point_mult(a[0], b.x));
      result = fixed_point_add(result, fixed_point_mult(a[1], b.y));
      result = fixed_point_add(result, fixed_point_mult(a[2], b.z));
      result = fixed_point_add(result, a[3]);  // b.w is always 1
      return result;
    end
  endfunction

  // State machine states
  // IDLE: can accept input
  // COMPUTE: computing rows
  // DONE: waiting for output to be accepted
  typedef enum logic [1:0] {
    IDLE,
    COMPUTE,
    DONE
  } state_t;

  state_t state;
  state_t next_state;
  logic [1:0] row_counter;  // Current row being processed

  // Next state sequential logic
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= IDLE;
      row_counter <= 2'b00;
    end else begin
      state <= next_state;
      if (state == COMPUTE && row_counter < 2'b11) begin
        row_counter <= row_counter + 1;
      end else if (state == IDLE || state == DONE) begin
        row_counter <= 2'b00;
      end
    end
  end

  // Combinatorial logic for state transitions + output logic
  // Each cycle we populate a row of the output vector with the dot product of the component with the input matrix
  // For component i, this is simply the summation from j=0-3 of Mat[i][j] * Vector[j]
  always_comb begin
    // Next state logic
    if (state == IDLE) begin
      if (in_vec_valid) begin
        next_state = COMPUTE;
      end else begin
        next_state = IDLE;
      end
    end else if (state == COMPUTE) begin
      if (row_counter == 2'b11) begin
        next_state = DONE;
      end else begin
        next_state = COMPUTE;
      end
    end else if (state == DONE) begin
      if (out_vec_ready) begin
        next_state = IDLE;
      end else begin
        next_state = DONE;
      end
    end else begin
      next_state = IDLE;  // Default case
    end

    // Current state logic:
    // Because the vector is a packed struct I unfortunately have to write this as a case statement
    // The w component of the input vector is always 1, and is passed through to the output as the signal 'w'
    if (state == COMPUTE) begin
      out_vec.r = in_vec.r;
      out_vec.g = in_vec.g;
      out_vec.b = in_vec.b;
      case (row_counter)
        2'b00:   out_vec.x = fixed_point_dot_product(in_mat.m[0], in_vec);
        2'b01:   out_vec.y = fixed_point_dot_product(in_mat.m[1], in_vec);
        2'b10:   out_vec.z = fixed_point_dot_product(in_mat.m[2], in_vec);
        2'b11:   w = fixed_point_dot_product(in_mat.m[3], in_vec);
        default: ;
      endcase
    end

    // Control signals
    in_vec_ready  = (next_state == IDLE);
    out_vec_valid = (next_state == DONE);
  end

endmodule
