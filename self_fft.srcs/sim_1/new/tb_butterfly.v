`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.03.2026 10:51:16
// Design Name: 
// Module Name: tb_butterfly
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_butterfly();

    reg clk;
    reg rst;
    reg start;
    reg signed [15:0] A_re, A_im, B_re, B_im, W_re, W_im;
    
    wire signed [15:0] X_re, X_im, Y_re, Y_im;
    wire done;

    butterfly uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .A_re(A_re), .A_im(A_im),
        .B_re(B_re), .B_im(B_im),
        .W_re(W_re), .W_im(W_im),
        .X_re(X_re), .X_im(X_im),
        .Y_re(Y_re), .Y_im(Y_im),
        .done(done)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        
        A_re = 16'd100; A_im = 16'd0;
        B_re = 16'd200; B_im = 16'd0;
        W_re = 16'd32767; W_im = 16'd0;

        #20 rst = 0;
        
        #10 start = 1;
        #10 start = 0;

        wait(done);

        $display("\n========================================");
        $display("          BUTTERFLY TEST RESULTS        ");
        $display("========================================");
        $display(" Inputs: A = %0d, B = %0d, W = 1.0 (Q15)", A_re, B_re);
        $display(" Expected X = (A + B*W)/2 = (100 + 200)/2 = 150");
        $display(" Expected Y = (A - B*W)/2 = (100 - 200)/2 = -50");
        $display("----------------------------------------");
        $display(" Actual X_re: %0d", X_re);
        $display(" Actual Y_re: %0d", Y_re);
        $display("========================================\n");
        
        #10 $finish;
    end

endmodule
