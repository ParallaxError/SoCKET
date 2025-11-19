/*
 * @file /gpu_top.sv
 * @brief
 * Interface adapter from the drawing unit interface to the GPU core.
 * Handles the commands which the user can send to the GPU core.
 *
 * Currently, the only command supported is to pass in a singular vertex through the registers. 
 * -----
 * Last Modified: Monday, 10th November 2025 7:38 pm
 * -----
 */

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

// GPU signals
logic in_ready;
vertex_t in_data;
logic in_valid;

mat4x4_t input_matrix;

logic out_ready;
pixel_buffer_t out_data;
logic out_valid;

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
GPU gpu_inst (
    .clk            (clk),
    .rst            (reset),

    .in_ready       (in_ready),
    .in_data        (in_data),
    .in_valid       (in_valid),

    .in_matrix      (input_matrix),

    .out_ready      (out_ready),
    .out_data       (out_data),
    .out_valid      (out_valid)
);

// Input data handling
always_ff @ (posedge clk or posedge reset)
begin
    if (reset)
    begin
        ack         <= 1'b0;
        in_valid    <= 1'b0;
    end
    else
    begin
        if (req && !ack && in_ready)
        begin
            // Latch parameters into in data
            in_data.x <= r0;
            in_data.y <= r1;
            in_data.z <= r2;
            in_data.r <= r3[7:0];
            in_data.g <= r4[7:0];
            in_data.b <= r5[7:0];

            in_valid  <= 1'b1;
            ack       <= 1'b1;
        end
        else
        begin
            ack       <= 1'b0;
            in_valid  <= 1'b0;
        end
    end
end

// Output data handling
always_ff @ (posedge clk or posedge reset)
begin
    if (reset)
    begin
        out_ready   <= 1'b1;
        de_req      <= 1'b0;
    end
    else
    begin
        if (out_valid && !de_req)
        begin
            // Latch output data
            de_addr   <= (out_data.y * SCREEN_WIDTH) + out_data.x;
            for (int i = 0; i < PIXELS_PER_WORD; i++)
            begin
                de_w_data[((i + 1)*8) -: 8] <= out_data.pixels[i];
            end

            de_nbyte <= ~out_data.valid_pixels;

            out_ready <= 1'b0;
            de_req    <= 1'b1;
        end
        else if (de_ack)
        begin
            de_req    <= 1'b0;
            out_ready <= 1'b1;
        end
    end
end

assign busy      =  !in_ready;           
assign done      =  out_valid;                 /* Dummy unit is 'done' immediately; */
                                         /*      (Not the general case!)      */
assign de_rnw    =  1'b0;                /* Read 'safer' than write           */

endmodule
