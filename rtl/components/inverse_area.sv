/*
 * @file /rtl/components/reciprocal.sv
 * @brief
 * Newton-Raphson based reciprocal calculation for the wide fixed point type to obtain the inverse
 * of the triangles area.
 * Pipelined to take multiple cycles, exposing valid/ready streaming interface.
 *
 * Currently uses a 128 lookup table for initial approximation, followed by 2 Newton-Raphson iterations. 
 * 
 * -----
 * Last Modified: Thursday, 27th November 2025 10:21 pm
 * -----
 */

`include "types/fixed_point_pkg.svh"
`include "types/fixed_point_wide_pkg.svh"

module inverse_area # (
    parameter int LUT_SIZE =   128,         
    parameter int ITERATIONS = 2
) (
    input  logic                              clk_i,
    input  logic                              rst_i,

    // Input streaming iface
    output logic                              in_ready_o,
    input  fixed_point_wide_pkg::fixed_wide_t in_denominator_i,
    input  logic                              in_valid_i,

    // Output streaming iface
    input  logic                              out_ready_i,
    output fixed_point_wide_pkg::fixed_wide_t out_data_o,
    output logic                              out_valid_o
);

  import fixed_point_pkg::*;
  import fixed_point_wide_pkg::*;

  typedef enum logic [1:0] {
    Idle,
    Iterate
  } state_e;

  state_e state, next_state;

  // Initial approximation LUT
  fixed_wide_t lut [0:LUT_SIZE-1];
  initial begin
    // Precompute the LUT values (procedural for-loop is synthesizer/testbench friendly)
    for (int i = 0; i < LUT_SIZE; i++) begin
      real denom;
      real recip; 
      denom = 1.0 + (real'(i) / real'(LUT_SIZE));
      recip = 1.0 / denom;
      lut[i] = from_fixed(from_real(recip));
    end
  end

  // Internal signals
  fixed_wide_t cur_reciprocal;
  fixed_wide_t next_reciprocal;

  logic [$clog2(ITERATIONS + 1)-1:0] iteration;

  // For LUT approximation, we need to normalize the denominator to the range [1,2)
  // This means for example, 10.5 -> 1.25 (shift -1), 0.75 -> 1.5 (shift +1)
  // Since our reciprocal approximations are stored linearly but reciprocals are exponential, this normalisation
  // allows us to get a good 7 bit approx to start
  // Therefore since each index doubles our accuracy, we can do 2 iterations for >20 bit precision

  // Normalization helpers and storage
  localparam int LUT_ADDR_WIDTH = $clog2(LUT_SIZE);
  localparam int SHIFT_WIDTH = $clog2(FIXED_WIDE_WIDTH) + 1;

  typedef struct {
    fixed_wide_t norm;
    logic signed [SHIFT_WIDTH-1:0] shift;
    logic sign;
    logic is_zero;
  } normalised_t;

  // Function: normalize denominator into range [1,2) and return shift/sign/zero flag
  function automatic normalised_t normalize_den(input fixed_wide_t d);
    normalised_t r;
    logic [FIXED_WIDE_WIDTH-1:0] abs_val;
    int msb;

    // First step is to find the absolute value and sign
    r.sign = d.value[FIXED_WIDE_WIDTH-1];
    if (r.sign)
      abs_val = -d.value;
    else
      abs_val = d.value;

    // Next, to find the MSB position we scan from MSB downwards for a one.
    msb = -1;
    for (int i = FIXED_WIDE_WIDTH-1; i >= 0; i--) begin
      if (abs_val[i] && msb == -1) msb = i;
      // TODO: Can I break here?
    end

    // If we scan the whole thing and find no ones, we're dividing by zero
    if (msb == -1) 
    begin
      r.is_zero = 1'b1;
      r.shift = '0;
      r.norm.value = '0;
    end
    else
    begin
      int S;
      logic [FIXED_WIDE_WIDTH-1:0] norm_bits;

      r.is_zero = 1'b0;

      // Ok, we need to shift to get MSB to FIXED_WIDE_FRAC position
      S = FIXED_WIDE_FRAC - msb;
      r.shift = S;
      // Shift the value: probably another DSP
      if (S >= 0)
        norm_bits = abs_val << S;
      else
        norm_bits = abs_val >> (-S);

      r.norm.value = norm_bits;
    end
    return r;
  endfunction

  // Registers to hold normalization results between cycles
  logic signed [SHIFT_WIDTH-1:0] shift_amount;
  logic denominator_signed;
  fixed_wide_t normalised_denominator;

  // Sequential logic
  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      state <= Idle;
      iteration <= 0;
    end else begin
      state <= next_state;

      if (state == Idle && next_state == Iterate) 
      begin
        // If starting a new calculation, normalize the denominator using the helper function
        normalised_t normalised_struct; 
        normalised_struct = normalize_den(in_denominator_i);

        denominator_signed <= normalised_struct.sign;
        shift_amount <= normalised_struct.shift;
        normalised_denominator <= normalised_struct.norm;

        if (normalised_struct.is_zero) begin
          // Fallback initial approx for zero denominator
          cur_reciprocal <= lut[0];
        end else begin
          logic [LUT_ADDR_WIDTH-1:0] lut_idx;
          lut_idx = $unsigned(normalised_struct.norm.value[FIXED_WIDE_FRAC-1 -: LUT_ADDR_WIDTH]);
          cur_reciprocal <= lut[lut_idx];
        end

        iteration <= 0;
      end

      if (state == Iterate && iteration < (ITERATIONS + 1))
      begin
        cur_reciprocal <= next_reciprocal;
        iteration <= iteration + 1;
      end
    end
  end

  // Output and next state combinational logic
  always_comb 
  begin
    fixed_wide_t D_xn, two_minus_D_xn, corrected_reciprocal;
    
    // Defaults
    D_xn = fixed_wide_t'('0);
    two_minus_D_xn = fixed_wide_t'('0);
    corrected_reciprocal = fixed_wide_t'('0);

    next_reciprocal = cur_reciprocal;
    next_state = state;
    out_valid_o = 1'b0;
    out_data_o = fixed_wide_t'('0);

    case (state)
      Idle: 
      begin
        if (in_valid_i) 
        begin
          next_state = Iterate;
        end
      end
      Iterate: 
      begin
        // Newton-Raphson iteration: x_{n+1} = x_n * (2 - D * x_n)
        // Use normalized denominator in the iteration
        
        D_xn = fixed_wide_mul(normalised_denominator, cur_reciprocal);
        two_minus_D_xn = fixed_wide_sub(from_fixed(from_real(2.0)), D_xn);

        next_reciprocal = fixed_wide_mul(cur_reciprocal, two_minus_D_xn);

        if (iteration + 1 > ITERATIONS && out_ready_i) 
          next_state = Idle;

        if (iteration + 1 > ITERATIONS) 
        begin
          out_valid_o = 1'b1;
          // Apply exponent correction: reciprocal(original) = reciprocal(normalized) * 2^{S}        
          if (shift_amount >= 0) begin
            corrected_reciprocal.value = cur_reciprocal.value <<< shift_amount;
          end else begin
            corrected_reciprocal.value = cur_reciprocal.value >>> (-shift_amount);
          end
          
          // Reapply sign of denominator: reciprocal of negative denom is negative
          if (denominator_signed) corrected_reciprocal.value = -corrected_reciprocal.value;
          out_data_o = corrected_reciprocal;
        end
      end
      default:
      begin
        next_state = Idle;
      end
    endcase
  end

  // Ready signal
  assign in_ready_o = (next_state == Idle);

endmodule
