// Includes
`include "types/rendering_pkg.svh"
`include "types/vertex_pkg.svh"
`include "types/fixed_point_pkg.svh"
`include "types/mat4x4_pkg.svh"
`include "types/pixels_pkg.svh"

import "DPI-C" function void writescreen (
    input int R, input int G, input int B, input int x, input int y
);

module top_tb();
  import rendering_pkg::*;
  import vertex_pkg::*;
  import fixed_point_pkg::*;
  import mat4x4_pkg::*;
  import pixels_pkg::*;

  logic        clk;
  logic        rst;
  
  // Testbench signals
  int          vertices_left;

  // Input FIFO
  logic        in_rd_en;
  logic        in_empty;
  vertex_t     in_data_i;
  logic        in_data_valid;

  logic        in_wr_en;
  vertex_t     in_wr_data;
  logic        in_full;

  sync_fifo#(
      .T(vertex_t),
      .DEPTH(16)
  ) input_fifo (
      .clk_i            (clk),
      .rst_i            (rst),

      .rd_en_i          (in_rd_en),
      .empty_o          (in_empty),
      .rd_data_o        (in_data_i),
      .rd_data_valid_o  (in_data_valid),

      .wr_en_i          (in_wr_en),
      .wr_data_i        (in_wr_data),
      .full_o           (in_full)
  );

  // Output FIFO
  logic               out_rd_en;
  logic               out_empty;
  pixel_buffer_t      out_rd_data;
  logic               out_rd_data_valid;
  logic               out_full;

  sync_fifo#(
      .T(pixel_buffer_t),
      .DEPTH(64)
  ) output_fifo (
      .clk_i            (clk),
      .rst_i            (rst),
      
      .rd_en_i          (out_rd_en),
      .empty_o          (out_empty),
      .rd_data_o        (out_rd_data),
      .rd_data_valid_o  (out_rd_data_valid),

      .wr_en_i          (gpu_valid && !out_full),
      .wr_data_i        (gpu_data),
      .full_o           (out_full)
  );

  // GPU
  logic               gpu_ready;
  pixel_buffer_t      gpu_data;
  logic               gpu_valid;
  logic               gpu_done;

  // Input matrix
  mat4x4_t mvp;

  gpu gpu_inst (
      .clk_i        (clk),
      .rst_i        (rst),
      
      .in_ready_o   (gpu_ready),
      .in_data_i    (in_data_i),
      .in_valid_i   (in_data_valid),

      .in_matrix_i  (mvp),

      .out_ready_i  (!out_full),
      .out_data_o   (gpu_data),
      .out_valid_o  (gpu_valid),
      .out_done_o   (gpu_done)
  );

  // GPU should ask for data when input FIFO is not empty
  assign in_rd_en = gpu_ready && !in_empty;

  // Virtual framestore for output pixels
  pixel_t framestore [0:SCREEN_WIDTH-1][0:SCREEN_HEIGHT-1];
  
  // Finally, list of times for which each triangle entered the pipeline for debug
  time triangle_entry_times[];
  int fd; // Golden data file descriptor

  // Clock generation
  initial begin
      clk = 0;
      forever #1 clk = ~clk; // 2 time units clock period
  end

  `ifdef VERILATOR
  initial begin
      $dumpfile("wave/top_tb.fst"); // output FST
      $dumpvars(0, top_tb);         // 0 = dump everything in hierarchy
  end
  `endif // VERILATOR

  // Test sequence
  initial begin
      int num_vertices = 0;
      vertex_t test_vertex;

      // Open the golden data file
      fd = $fopen("model/test_triangle.verts_golden_data.txt", "r");
      // Very first line is the number of vertices
      $fscanf(fd, "%d\n", num_vertices);
      $display("Number of vertices to load: %0d", num_vertices);
      vertices_left = num_vertices;
      triangle_entry_times = new[num_vertices / 3];

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

          in_wr_data = test_vertex; 
          in_wr_en = 1; 
          @(posedge clk); 
          in_wr_en = 0;

          vertices_left--;

          // Record the time this triangle entered the pipeline
          if (i % 3 == 0) begin
              triangle_entry_times[i / 3] = $time;
          end
      end

      $display("\nTest completed successfully.");
  end

  // GPU output handling
  initial begin
              // Wait for GPU output
      $display("\n--- GPU Output ---");
      while (1) begin
          @ (posedge clk);
          if (!out_empty) begin
              out_rd_en = 1;
              wait (out_rd_data_valid);

              for (int p = 0; p < $bits(out_rd_data.valid_pixels); p++) begin
                  if (!out_rd_data.valid_pixels[p]) continue;

                  writescreen(
                      out_rd_data.pixels[p].r << (8 - RED_DEPTH),
                      out_rd_data.pixels[p].g << (8 - GREEN_DEPTH),
                      out_rd_data.pixels[p].b << (8 - BLUE_DEPTH),
                      out_rd_data.x * PIXELS_PER_WORD + p,
                      out_rd_data.y
                  );

                  // Also store to virtual framestore for later comparison
                  framestore[out_rd_data.x * PIXELS_PER_WORD + p][out_rd_data.y] = out_rd_data.pixels[p];
              end
              @ (posedge clk);
              out_rd_en = 0;
          end
      end
  end

  // Wait for GPU to finish processing and compare to golden data
  initial begin
    pixel_t stored_pixel;
    int golden_x, golden_y, golden_r, golden_g, golden_b, golden_index;
    int red, green, blue;
    int errors = 0;
    forever begin
        @ (posedge clk);
        if (vertices_left == 0) begin
            if (gpu_done) begin
              $display("\nGPU signalled done at time %0t. Performing comparison with golden data...", $time);
              wait (out_empty); // Wait for all output to be read
              // Each line left in the golden data file is an output pixel in the format
              // x y R G B index
              while (!$feof(fd)) begin
                  $fscanf(fd, "%d %d %d %d %d %d\n", golden_x, golden_y, golden_r, golden_g, golden_b, golden_index);


                  // Now compare with framestore
                  stored_pixel = framestore[golden_x][golden_y];

                  // Convert RGB to 8 bit colour with shifting
                  red = stored_pixel.r << (8 - RED_DEPTH);
                  green = stored_pixel.g << (8 - GREEN_DEPTH);
                  blue = stored_pixel.b << (8 - BLUE_DEPTH);

                  if (red !== golden_r || green !== golden_g || blue !== golden_b) begin
                      $warning("Mismatch at pixel (%0d, %0d): Expected (R:%0d G:%0d B:%0d), Got (R:%0d G:%0d B:%0d)",
                          golden_x, golden_y,
                          golden_r, golden_g, golden_b,
                          red, green, blue
                      );
                      $warning("The triangle that rendered this pixel entered the pipeline at time %0t",
                          triangle_entry_times[golden_index]
                      );
                      errors++;
                  end
              end

              $display("Comparison complete. Total errors: %0d", errors);
              $finish;
            end
        end
    end
  end

  // Timeout to prevent infinite simulation
  initial begin
      #40000000;
      $display("Test timed out!");
      $finish;
  end

endmodule
