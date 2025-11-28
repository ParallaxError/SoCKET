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
 * Last Modified: Thursday, 27th November 2025 10:22 pm
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

  // Signals to connect matrix mult to dividers
  logic x_div_ready, y_div_ready, z_div_ready;

  // We're ready to accept new data when the output of the mat_mult is ready if we have valid input and the matrix
  // is valid
  assign out_mat_ready = x_div_ready && y_div_ready && z_div_ready;

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

  // Perpsective divide stage
  // Takes in transformed vertex and performs perspective divide to get screen coordinates
  // Need three dividers for x, y, z
  fixed_t x_numerator, y_numerator, z_numerator;
  fixed_t w_reg;
  fixed_t x_output, y_output, z_output;
  logic   x_in_valid, y_in_valid, z_in_valid;
  logic   x_div_valid, y_div_valid, z_div_valid;

  // Reciprocal units
  reciprocal reciprocal_x_inst (
      .clk_i              (clk_i),
      .rst_i              (rst_i),

      .in_ready_o         (x_div_ready),
      .in_valid_i         (x_in_valid),
      .in_denominator_i   (w_reg),
      .in_numerator_i     (x_numerator),

      .out_ready_i        (out_ready_i),
      .out_data_o         (x_output),
      .out_valid_o        (x_div_valid)
  );

  reciprocal reciprocal_y_inst (
      .clk_i              (clk_i),
      .rst_i              (rst_i),

      .in_ready_o         (y_div_ready),
      .in_valid_i         (y_in_valid),
      .in_denominator_i   (w_reg),
      .in_numerator_i     (y_numerator),

      .out_ready_i        (out_ready_i),
      .out_data_o         (y_output),
      .out_valid_o        (y_div_valid)
  );

  reciprocal reciprocal_z_inst (
      .clk_i              (clk_i),
      .rst_i              (rst_i),

      .in_ready_o         (z_div_ready),
      .in_valid_i         (z_in_valid),
      .in_denominator_i   (w_reg),
      .in_numerator_i     (z_numerator),
      
      .out_ready_i        (out_ready_i),
      .out_data_o         (z_output),
      .out_valid_o        (z_div_valid)
  );

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      x_in_valid <= 1'b0;
      y_in_valid <= 1'b0;
      z_in_valid <= 1'b0;
      
      out_valid_o <= 1'b0;
      
      x_numerator <= fixed_t'('0);
      y_numerator <= fixed_t'('0);
      z_numerator <= fixed_t'('0);
    end else begin
      // Default: deassert input valids; we'll pulse them when we accept a mat result
      x_in_valid <= 1'b0;
      y_in_valid <= 1'b0;
      z_in_valid <= 1'b0;
      out_valid_o <= 1'b0;

      if (out_mat_valid && out_mat_ready) begin
        // Perspective divide: Convert to screen coordinates then divide by w
        // Division is done by the reciprocal units, we just set up numerators and pulse valids

        x_numerator <= out_mat_data.x;
        y_numerator <= out_mat_data.y;
        z_numerator <= out_mat_data.z;
        w_reg <= out_mat_w;

        // Passthrough colour
        out_data_o.r <= out_mat_data.r;
        out_data_o.g <= out_mat_data.g;
        out_data_o.b <= out_mat_data.b;

        // Pulse valids to start dividers
        x_in_valid <= 1'b1;
        y_in_valid <= 1'b1;
        z_in_valid <= 1'b1;
      end else begin
        x_in_valid <= 1'b0;
        y_in_valid <= 1'b0;
        z_in_valid <= 1'b0;
      end

      // When all dividers have valid outputs and the downstream consumer will accept, present the result
      if (x_div_valid && y_div_valid && z_div_valid) begin
        // Only mark the vertex output valid when consumer ready is asserted (or hold until accepted)
        if (out_ready_i) begin
          out_valid_o <= 1'b1;
          out_data_o.x <= fixed_point_mult(
              x_output, from_real(real'(rendering_pkg::SCREEN_WIDTH))
          );
          out_data_o.y <= fixed_point_sub(
              from_real(real'(rendering_pkg::SCREEN_HEIGHT)), 
              fixed_point_mult(y_output, from_real(real'(rendering_pkg::SCREEN_HEIGHT)))
          );
          out_data_o.z <= z_output;
        end
      end
    end
  end

endmodule
