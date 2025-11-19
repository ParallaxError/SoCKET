`include "types/vertex.sv"
`include "types/fixed_point.sv"
`include "types/mat4x4.sv"
`include "types/pixels.sv"
import vertex_pkg::*;
import fixed_point_pkg::*;
import mat4x4_pkg::*;
import pixels_pkg::*;

import "DPI-C" function void writescreen (input int R, input int G, input int B, input int x, input int y);

module top_tb();
    logic        clk;
    logic        rst;

    // Input FIFO
    logic        in_rd_en;
    logic        in_empty;
    vertex_t     in_data;
    logic        in_data_valid;

    logic        in_wr_en;
    vertex_t     in_wr_data;
    logic        in_full;

    SyncFifo#(
        .T(vertex_t),
        .DEPTH(16)
    ) input_fifo (
        .clk            (clk),
        .rst            (rst),

        .rd_en          (in_rd_en),
        .empty          (in_empty),
        .rd_data        (in_data),
        .rd_data_valid  (in_data_valid),

        .wr_en          (in_wr_en),
        .wr_data        (in_wr_data),
        .full           (in_full)
    );

    // Output FIFO
    logic               out_rd_en;
    logic               out_empty;
    pixel_buffer_t      out_rd_data;
    logic               out_rd_data_valid;
    logic               out_full;

    SyncFifo#(
        .T(pixel_buffer_t),
        .DEPTH(64)
    ) output_fifo (
        .clk            (clk),
        .rst            (rst),
        
        .rd_en          (out_rd_en),
        .empty          (out_empty),
        .rd_data        (out_rd_data),
        .rd_data_valid  (out_rd_data_valid),

        .wr_en          (gpu_valid && !out_full),
        .wr_data        (gpu_data),
        .full           (out_full)
    );

    // GPU
    logic               gpu_ready;
    pixel_buffer_t      gpu_data;
    logic               gpu_valid;

    // Input matrix
    mat4x4_t mvp;

    GPU gpu_inst (
        .clk        (clk),
        .rst        (rst),
        
        .in_ready   (gpu_ready),
        .in_data    (in_data),
        .in_valid   (in_data_valid),

        .in_matrix  (mvp),

        .out_ready  (!out_full),
        .out_data   (gpu_data),
        .out_valid  (gpu_valid)
    );

    // GPU should ask for data when input FIFO is not empty
    assign in_rd_en = gpu_ready && !in_empty;

    // Clock generation
    initial begin
        clk = 0;
        forever #1 clk = ~clk; // 2 time units clock period
    end

    int out_count = 0;

    initial begin
        $dumpfile("wave/top_tb.fst"); // output VCD
        $dumpvars(0, top_tb);         // 0 = dump everything in hierarchy
    end

    // Test sequence
    initial begin
        int num_vertices = 0;
        vertex_t test_vertex;

        // Open the vertices file
        int fd = $fopen("test_data/input.verts", "r");
        // Very first line is the number of vertices
        $fscanf(fd, "%d\n", num_vertices);
        $display("Number of vertices to load: %0d", num_vertices);


        // First 4 lines are the first 4 rows of the matrix
        // Read 4 floats 4 times and set it
        for (int i = 0; i < 4; i++) begin
            real f0, f1, f2, f3;
            $fscanf(fd, "%f %f %f %f\n", f0, f1, f2, f3);
            mvp.m[i][0] = from_real(f0);
            mvp.m[i][1] = from_real(f1);
            mvp.m[i][2] = from_real(f2);
            mvp.m[i][3] = from_real(f3);
        end

        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++)
                $display("MVP[%0d][%0d] = %f", i, j, to_real(mvp.m[i][j]));

        clk = 0;
        rst = 1;
        in_wr_en = 0;

        // Wait 5 cycles for reset
        repeat (5) @ (posedge clk);
        rst = 0;

        // Enqueue all input vertices
        for (int i = 0; i < num_vertices; i++) begin
             // First, read a vertex from the file
            real x, y, z;
            int r, g, b;

            $fscanf(fd, "%f %f %f %d %d %d\n", x, y, z, r, g, b);
            test_vertex.x = from_real(x);
            test_vertex.y = from_real(y);
            test_vertex.z = from_real(z);
            test_vertex.r = r;
            test_vertex.g = g;
            test_vertex.b = b;

            // Wait until FIFO has space
            wait (!in_full);
            @(posedge clk); 

            in_wr_data <= test_vertex; 
            in_wr_en = 1; 
            @(posedge clk); 
            in_wr_en = 0;

            // $display("[%0t] Enqueued vertex %0d: x=%f y=%f z=%f r=%0h g=%0h b=%0h",
            //         $time, i,
            //         to_real(test_vertices[i].x), to_real(test_vertices[i].y),
            //         to_real(test_vertices[i].z), test_vertices[i].r,
            //         test_vertices[i].g, test_vertices[i].b);
        end

        $display("\nTest completed successfully.");
        // $finish;
    end

    // GPU output handling
    initial begin
                // Wait for GPU output
        $display("\n--- GPU Output ---");
        while (1) begin
            @ (posedge clk);
            if (!out_empty) begin
                out_count++;
                out_rd_en = 1;
                wait (out_rd_data_valid);
                // $display("[%0t] Output pixel %0d: x=%0d y=%0d",
                //         $time, out_count,
                //         out_rd_data.x, out_rd_data.y);

                for (int p = 0; p < $bits(out_rd_data.valid_pixels); p++) begin
                    if (!out_rd_data.valid_pixels[p]) continue;

                    // $display("Pixel %0d: r=%0h g=%0h b=%0h", p,
                    //          out_rd_data.pixels[p].r,
                    //          out_rd_data.pixels[p].g,
                    //          out_rd_data.pixels[p].b);

                    writescreen(
                        out_rd_data.pixels[p].r,
                        out_rd_data.pixels[p].g,
                        out_rd_data.pixels[p].b,
                        out_rd_data.x * PIXELS_PER_WORD + p,
                        out_rd_data.y
                    );
                end
                out_rd_en = 0;
            end
            // $finish;
        end
    end

    // Timeout to prevent infinite simulation
    initial begin
        #600000;
        $display("Test timed out!");
        $finish;
    end

endmodule