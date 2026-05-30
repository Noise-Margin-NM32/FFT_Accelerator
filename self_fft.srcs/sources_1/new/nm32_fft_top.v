`timescale 1ns / 1ps

module nm32_fft_top (
    input wire clk,
    input wire rst,
    input wire start,
    input wire ext_we,
    input wire [8:0] ext_addr,
    input wire [31:0] ext_din,
    output wire [31:0] ext_dout,
    
    // Twiddle RAM Write Ports (Mapped to AHB)
    input wire tw_we,
    input wire [7:0] tw_ext_addr,
    input wire [31:0] tw_ext_din,
    output wire [31:0] tw_ext_dout,
    
    output reg done
);

    reg ping_pong_sel; // 0: SoC->RAM0, FFT->RAM1. 1: SoC->RAM1, FFT->RAM0

    // FFT-side signals
    reg ram_fft_we_a, ram_fft_we_b;
    reg [8:0] ram_fft_addr_a, ram_fft_addr_b;
    reg [31:0] ram_fft_din_a, ram_fft_din_b;
    wire [31:0] ram_fft_dout_a, ram_fft_dout_b;

    // Two RAM instantiations
    wire [31:0] ram0_dout_a, ram0_dout_b;
    wire [31:0] ram1_dout_a, ram1_dout_b;
    
    wire ram0_we_a   = (ping_pong_sel == 0) ? ext_we   : ram_fft_we_a;
    wire [8:0] ram0_addr_a = (ping_pong_sel == 0) ? ext_addr : ram_fft_addr_a;
    wire [31:0] ram0_din_a  = (ping_pong_sel == 0) ? ext_din  : ram_fft_din_a;
    wire ram0_we_b   = (ping_pong_sel == 0) ? 1'b0     : ram_fft_we_b;
    wire [8:0] ram0_addr_b = (ping_pong_sel == 0) ? 9'b0     : ram_fft_addr_b;
    wire [31:0] ram0_din_b  = (ping_pong_sel == 0) ? 32'b0    : ram_fft_din_b;

    wire ram1_we_a   = (ping_pong_sel == 1) ? ext_we   : ram_fft_we_a;
    wire [8:0] ram1_addr_a = (ping_pong_sel == 1) ? ext_addr : ram_fft_addr_a;
    wire [31:0] ram1_din_a  = (ping_pong_sel == 1) ? ext_din  : ram_fft_din_a;
    wire ram1_we_b   = (ping_pong_sel == 1) ? 1'b0     : ram_fft_we_b;
    wire [8:0] ram1_addr_b = (ping_pong_sel == 1) ? 9'b0     : ram_fft_addr_b;
    wire [31:0] ram1_din_b  = (ping_pong_sel == 1) ? 32'b0    : ram_fft_din_b;

    fft_data_ram data_ram_0 (
        .clk(clk),
        .we_a(ram0_we_a), .addr_a(ram0_addr_a), .din_a(ram0_din_a), .dout_a(ram0_dout_a),
        .we_b(ram0_we_b), .addr_b(ram0_addr_b), .din_b(ram0_din_b), .dout_b(ram0_dout_b)
    );

    fft_data_ram data_ram_1 (
        .clk(clk),
        .we_a(ram1_we_a), .addr_a(ram1_addr_a), .din_a(ram1_din_a), .dout_a(ram1_dout_a),
        .we_b(ram1_we_b), .addr_b(ram1_addr_b), .din_b(ram1_din_b), .dout_b(ram1_dout_b)
    );

    assign ram_fft_dout_a = (ping_pong_sel == 0) ? ram1_dout_a : ram0_dout_a;
    assign ram_fft_dout_b = (ping_pong_sel == 0) ? ram1_dout_b : ram0_dout_b;

    // -----------------------------------------------------------------
    // Twiddle RAM (256 x 32-bit words)
    // -----------------------------------------------------------------
    reg [31:0] twiddle_ram [0:255];
    reg [31:0] tw_rdata_ext;
    reg [31:0] tw_rdata_math;
    reg [7:0] tw_addr;
    
    always @(posedge clk) begin
        // Port A: External AHB Write/Read
        if (tw_we) begin
            twiddle_ram[tw_ext_addr] <= tw_ext_din;
        end
        tw_rdata_ext <= twiddle_ram[tw_ext_addr];
        
        // Port B: Internal Math Engine Read
        tw_rdata_math <= twiddle_ram[tw_addr];
    end
    
    assign tw_ext_dout = tw_rdata_ext;
    
    wire signed [15:0] tw_re = tw_rdata_math[31:16];
    wire signed [15:0] tw_im = tw_rdata_math[15:0];

    reg bf_start;
    wire bf_done;
    reg signed [15:0] bf_A_re, bf_A_im, bf_B_re, bf_B_im, bf_W_re, bf_W_im;
    wire signed [15:0] bf_X_re, bf_X_im, bf_Y_re, bf_Y_im;

    butterfly_folded math_engine (
        .clk(clk),
        .rst(rst),
        .start(bf_start),
        .A_re(bf_A_re), .A_im(bf_A_im),
        .B_re(bf_B_re), .B_im(bf_B_im),
        .W_re(bf_W_re), .W_im(bf_W_im),
        .X_re(bf_X_re), .X_im(bf_X_im),
        .Y_re(bf_Y_re), .Y_im(bf_Y_im),
        .done(bf_done)
    );

    assign ext_dout = (ping_pong_sel == 0) ? ram0_dout_a : ram1_dout_a;

    reg [3:0] s;
    reg [9:0] m;
    reg [8:0] m2;
    reg [9:0] k;
    reg [8:0] j;
    reg [2:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 0;
            done <= 0;
            bf_start <= 0;
            ram_fft_we_a <= 0; ram_fft_we_b <= 0;
            s <= 1; m <= 2; m2 <= 1; k <= 0; j <= 0;
            ping_pong_sel <= 0;
        end else begin
            case (state)
                0: begin
                    done <= 0;
                    ram_fft_we_a <= 0;
                    ram_fft_we_b <= 0;
                    
                    if (start) begin
                        ping_pong_sel <= ~ping_pong_sel; // Swap buffers
                        s <= 1; m <= 2; m2 <= 1; k <= 0; j <= 0;
                        state <= 1;
                    end
                end
                
                1: begin
                    ram_fft_addr_a <= k + j;
                    ram_fft_addr_b <= k + j + m2;
                    tw_addr <= j << (9 - s);
                    state <= 2;
                end
                
                2: begin
                    state <= 3;
                end
                
                3: begin
                    bf_A_re <= ram_fft_dout_a[31:16]; bf_A_im <= ram_fft_dout_a[15:0];
                    bf_B_re <= ram_fft_dout_b[31:16]; bf_B_im <= ram_fft_dout_b[15:0];
                    bf_W_re <= tw_re; bf_W_im <= tw_im;
                    bf_start <= 1;
                    state <= 4;
                end
                
                4: begin
                    bf_start <= 0;
                    if (bf_done) begin
                        ram_fft_din_a <= {bf_X_re, bf_X_im};
                        ram_fft_din_b <= {bf_Y_re, bf_Y_im};
                        ram_fft_we_a <= 1; ram_fft_we_b <= 1;
                        state <= 5;
                    end
                end
                
                5: begin
                    ram_fft_we_a <= 0; ram_fft_we_b <= 0;
                    if (j + 1 == m2) begin
                        j <= 0;
                        if (k + m >= 512) begin
                            k <= 0;
                            if (s == 9) begin
                                state <= 6;
                            end else begin
                                s <= s + 1;
                                m <= m << 1;
                                m2 <= m2 << 1;
                                state <= 7; // Go to idle latching state
                            end
                        end else begin
                            k <= k + m;
                            state <= 7; // Go to idle latching state
                        end
                    end else begin
                        j <= j + 1;
                        state <= 7; // Go to idle latching state
                    end
                end
                
                7: begin
                    // Idle latching state to ensure counters (j, k, s) are entirely stable 
                    // for a full clock cycle before they are used to compute ram_addr_a/b
                    state <= 1;
                end
                
                6: begin
                    done <= 1;
                    state <= 0;
                end
                
                default: state <= 0;
            endcase
        end
    end

endmodule