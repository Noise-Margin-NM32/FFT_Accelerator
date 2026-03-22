`timescale 1ns / 1ps

module butterfly_folded (
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [15:0] A_re, A_im,
    input wire signed [15:0] B_re, B_im,
    input wire signed [15:0] W_re, W_im,
    output reg signed [15:0] X_re, X_im,
    output reg signed [15:0] Y_re, Y_im,
    output reg done
);

    // DSP pipeline registers
    reg signed [31:0] m_rr, m_ii, m_ri, m_ir;
    reg signed [15:0] BW_re, BW_im;
    reg signed [15:0] A_re_d, A_im_d;
    
    // THE FIX: 17-bit intermediate wires for overflow-safe addition
    // We duplicate the 15th bit (the sign bit) to extend the number to 17 bits.
    wire signed [16:0] ext_A_re  = {A_re_d[15], A_re_d};
    wire signed [16:0] ext_A_im  = {A_im_d[15], A_im_d};
    wire signed [16:0] ext_BW_re = {BW_re[15], BW_re};
    wire signed [16:0] ext_BW_im = {BW_im[15], BW_im};

    reg [2:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 0;
            done <= 0;
            X_re <= 0; X_im <= 0; Y_re <= 0; Y_im <= 0;
        end else begin
            case (state)
                0: begin
                    done <= 0;
                    if (start) begin
                        // Cycle 1: Start 32-bit Multiplications
                        m_rr <= B_re * W_re;
                        m_ii <= B_im * W_im;
                        m_ri <= B_re * W_im;
                        m_ir <= B_im * W_re;
                        
                        // Pipeline the A inputs so they wait for the multiplication
                        A_re_d <= A_re;
                        A_im_d <= A_im;
                        state <= 1;
                    end
                end
                
                1: begin
                    // Cycle 2: Complex Subtraction/Addition & Q15 Truncation
                    BW_re <= (m_rr - m_ii) >>> 15;
                    BW_im <= (m_ri + m_ir) >>> 15;
                    state <= 2;
                end
                
                2: begin
                    // Cycle 3: 17-bit Addition & Subtraction
                    // We add the 17-bit numbers, then shift right by 1 to safely drop back to 16 bits.
                    X_re <= (ext_A_re + ext_BW_re) >>> 1;
                    X_im <= (ext_A_im + ext_BW_im) >>> 1;
                    
                    Y_re <= (ext_A_re - ext_BW_re) >>> 1;
                    Y_im <= (ext_A_im - ext_BW_im) >>> 1;
                    
                    state <= 3;
                end
                
                3: begin
                    // Cycle 4: Assert Done Flag
                    done <= 1;
                    state <= 4;
                end
                
                4: begin
                    // Cycle 5: Return to Idle
                    done <= 0;
                    state <= 0;
                end
                
                default: state <= 0;
            endcase
        end
    end

endmodule
