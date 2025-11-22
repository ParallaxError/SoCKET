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

module mat_mult (
    input  logic    clk_i,
    input  logic    rst_i,

    // Input vector
    input  logic    in_vec_valid_i,
    output logic    in_vec_ready_o,
    input  vertex_t in_vec_i,

    // Input matrix
    input  mat4x4_t in_mat_i,

    // Output vector
    output logic    out_vec_valid_o,
    output vertex_t out_vec_o,
    output fixed_t  w_o,
    input  logic    out_vec_ready_i
);
  // Imports
  import fixed_point_pkg::*;
  import mat4x4_pkg::*;
  import vertex_pkg::*;

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
      result = fixed_point_add(result, a[3]);  // b.w_o is always 1
      return result;
    end
  endfunction

  // State machine states
  // Idle: can accept input
  // Compute: computing rows
  // Done: waiting for output to be accepted
  typedef enum logic [1:0] {
    Idle,
    Compute,
    Done
  } state_e;

  state_e state;
  state_e next_state;

  logic [1:0] row_counter;  // Current row being processed

  // Next state sequential logic
  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      state <= Idle;
      row_counter <= 2'b00;
    end else begin
      state <= next_state;
      if (state == Compute && row_counter < 2'b11) begin
        row_counter <= row_counter + 1;
      end else if (state == Idle || state == Done) begin
        row_counter <= 2'b00;
      end
    end
  end

  // Combinatorial logic for state transitions + output logic
  // Each cycle we populate a row of the output vector with the dot product of the component with the input matrix
  // For component i, this is simply the summation from j=0-3 of Mat[i][j] * Vector[j]
  always_comb begin
    // Next state logic
    if (state == Idle) begin
      if (in_vec_valid_i) begin
        next_state = Compute;
      end else begin
        next_state = Idle;
      end
    end else if (state == Compute) begin
      if (row_counter == 2'b11) begin
        next_state = Done;
      end else begin
        next_state = Compute;
      end
    end else if (state == Done) begin
      if (out_vec_ready_i) begin
        next_state = Idle;
      end else begin
        next_state = Done;
      end
    end else begin
      next_state = Idle;  // Default case
    end

    // Current state logic:
    // Because the vector is a packed struct I unfortunately have to write this as a case statement
    // The w_o component of the input vector is always 1, and is passed through to the output as the signal 'w_o'
    if (state == Compute) begin
      out_vec_o.r = in_vec_i.r;
      out_vec_o.g = in_vec_i.g;
      out_vec_o.b = in_vec_i.b;
      case (row_counter)
        2'b00:   out_vec_o.x = fixed_point_dot_product(in_mat_i.m[0], in_vec_i);
        2'b01:   out_vec_o.y = fixed_point_dot_product(in_mat_i.m[1], in_vec_i);
        2'b10:   out_vec_o.z = fixed_point_dot_product(in_mat_i.m[2], in_vec_i);
        2'b11:   w_o = fixed_point_dot_product(in_mat_i.m[3], in_vec_i);
        default: ;
      endcase
    end

    // Control signals
    in_vec_ready_o  = (next_state == Idle);
    out_vec_valid_o = (next_state == Done);
  end

endmodule
