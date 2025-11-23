/*
 * @file /rtl/stages/vertex_shader.sv
 * @brief
 * First stage of the graphics pipeline: the vertex shader.
 * The vertex shader applies transformations to the vertices in world space to obtain screen space coordinates.
 *
 * With the simple GPU implemented here, the vertex shader applies a single 4x4 transformation matrix to each vertex.
 * Details on the Matrix Multiplication Units used are in rtl/components/mat_mult.sv.
 *
 * -----
 * Last Modified: Saturday, 22nd November 2025 10:58 pm
 * -----
 */

`include "types/fixed_point_pkg.svh"
`include "types/vertex_pkg.svh"
`include "types/mat4x4_pkg.svh"
`include "types/rendering_pkg.svh"

module vertex_shader (
    input  logic                clk_i,
    input  logic                rst_i,

    // input streaming iface
    output logic                in_ready_o,
    input  vertex_pkg::vertex_t in_data_i,
    input  logic                in_valid_i,

    // Input matrix
    input  mat4x4_pkg::mat4x4_t in_matrix_i,

    // output streaming iface
    input  logic                out_ready_i,
    output vertex_pkg::vertex_t out_data_o,
    output logic                out_valid_o
);
  // Imports
  import fixed_point_pkg::*;
  import vertex_pkg::*;
  import mat4x4_pkg::*;
  import rendering_pkg::*;

  // Internal connections
  logic out_mat_valid;
  vertex_t out_mat_data;
  fixed_t out_mat_w;
  logic out_mat_ready;

  logic div_ready;
  logic div_valid;

  // We're ready to accept new data when the output of the mat_mult is ready if we have valid input and the matrix
  // is valid
  assign out_mat_ready = div_ready;

  // Matrix multiplication unit
  mat_mult mat_mult_inst (
      .clk_i          (clk_i),
      .rst_i          (rst_i),

      // Input vector
      .in_vec_valid_i (in_valid_i),
      .in_vec_ready_o (in_ready_o),
      .in_vec_i       (in_data_i),

      // Input matrix
      .in_mat_i       (in_matrix_i),

      // Output vector
      .out_vec_valid_o(out_mat_valid),
      .out_vec_o      (out_mat_data),
      .w_o            (out_mat_w),
      .out_vec_ready_i(out_mat_ready)
  );

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      div_valid <= 1'b0;
      div_ready <= 1'b1;
    end else if (out_mat_valid && out_mat_ready) begin
      // perform perspective divide
      // x' = x / w, y' = y / w, z' = z / w
      // Here we assume w is non-zero; in a full implementation, should handle w=0 case
      // Also multiply with screen size to get screen coordinates
      out_data_o.x.value <= fixed_point_mult(
          fixed_point_div(out_mat_data.x.value, out_mat_w), from_real(rendering_pkg::SCREEN_WIDTH)
      );
      // TODO Shorten
      out_data_o.y.value <= fixed_point_sub(
          from_real(real'(SCREEN_HEIGHT)),
          fixed_point_mult(
              fixed_point_div(out_mat_data.y.value, out_mat_w),
              from_real(rendering_pkg::SCREEN_HEIGHT)
          )
      );
      out_data_o.z.value <= fixed_point_div(out_mat_data.z.value, out_mat_w);
      out_data_o.r <= out_mat_data.r;
      out_data_o.g <= out_mat_data.g;
      out_data_o.b <= out_mat_data.b;
      div_valid <= 1'b1;
      div_ready <= out_ready_i;  // Div can accept new input if consumer will accept next cycle
    end else if (div_valid && out_ready_i) begin
      div_valid <= 1'b0;
      div_ready <= 1'b1;
    end
  end

  // output signals
  assign out_valid_o = div_valid;

endmodule
