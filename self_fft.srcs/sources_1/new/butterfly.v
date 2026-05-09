`timescale 1ns / 1ps

module butterfly(input wire clk, input wire rst, input wire start, 
    input wire signed [15:0] A_re, A_im, B_re, B_im, W_re, W_im, 
    output reg signed [15:0] X_re, X_im, Y_re, Y_im, output reg done
);

    reg signed [15:0] op1, op2;
    wire signed [31:0] mult_out;
    
    assign mult_out = $signed(op1) * $signed(op2);

    reg signed [31:0] P1, P2, P3, P4;
    reg [2:0] state;

    wire signed [15:0] B_W_re, B_W_im;
    wire signed [17:0] add_re, add_im, sub_re, sub_im;

    assign B_W_re = (P1 - P2) >>> 15;
    assign B_W_im = (P3 + P4) >>> 15;

    assign add_re = A_re + B_W_re;
    assign add_im = A_im + B_W_im;
    assign sub_re = A_re - B_W_re;
    assign sub_im = A_im - B_W_im;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 0; 
            done <= 0;
            X_re <= 16'd0; X_im <= 16'd0;
            Y_re <= 16'd0; Y_im <= 16'd0;
            op1 <= 16'd0;  op2 <= 16'd0;
            P1 <= 32'd0; P2 <= 32'd0; P3 <= 32'd0; P4 <= 32'd0;
        end else begin
            case (state)
                0: begin
                    done <= 0;
                    if (start) begin
                        op1 <= B_re; op2 <= W_re;
                        state <= 1;
                    end
                end
                
                1: begin
                    P1 <= mult_out;
                    op1 <= B_im; op2 <= W_im;
                    state <= 2;
                end
                
                2: begin
                    P2 <= mult_out;
                    op1 <= B_re; op2 <= W_im;
                    state <= 3;
                end
                
                3: begin
                    P3 <= mult_out;
                    op1 <= B_im; op2 <= W_re;
                    state <= 4;
                end
                
                4: begin
                    P4 <= mult_out;
                    state <= 5;
                end
                
                5: begin
                    X_re <= add_re >>> 1;
                    X_im <= add_im >>> 1;
                    Y_re <= sub_re >>> 1;
                    Y_im <= sub_im >>> 1;
                    done <= 1;
                    state <= 0;
                end
                default: state <= 0;
            endcase
        end
    end
endmodule