`timescale 1ns / 1ps

module nm32_fft_top (
    input wire clk,
    input wire rst,
    input wire start,
    input wire ext_we,
    input wire [8:0] ext_addr,
    input wire [31:0] ext_din,
    output wire [31:0] ext_dout,
    output reg done
);

    wire [31:0] ram_dout_a, ram_dout_b;
    reg [31:0] ram_din_a, ram_din_b;
    reg [8:0] ram_addr_a, ram_addr_b;
    reg ram_we_a, ram_we_b;

    fft_data_ram data_ram (
        .clk(clk),
        .we_a(ram_we_a), .addr_a(ram_addr_a), .din_a(ram_din_a), .dout_a(ram_dout_a),
        .we_b(ram_we_b), .addr_b(ram_addr_b), .din_b(ram_din_b), .dout_b(ram_dout_b)
    );

    wire signed [15:0] tw_re, tw_im;
    reg [7:0] tw_addr;

    twiddle_rom_512 twiddle_rom (
        .addr(tw_addr),
        .wr(tw_re),
        .wi(tw_im)
    );

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

    assign ext_dout = ram_dout_a;

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
            ram_we_a <= 0; ram_we_b <= 0;
            s <= 1; m <= 2; m2 <= 1; k <= 0; j <= 0;
        end else begin
            case (state)
                0: begin
                    done <= 0;
                    ram_we_a <= ext_we;
                    ram_we_b <= 0;
                    ram_addr_a <= ext_addr;
                    ram_din_a <= ext_din;
                    
                    if (start) begin
                        s <= 1; m <= 2; m2 <= 1; k <= 0; j <= 0;
                        ram_we_a <= 0;
                        state <= 1;
                    end
                end
                
                1: begin
                    ram_addr_a <= k + j;
                    ram_addr_b <= k + j + m2;
                    tw_addr <= j << (9 - s);
                    state <= 2;
                end
                
                2: begin
                    state <= 3;
                end
                
                3: begin
                    bf_A_re <= ram_dout_a[31:16]; bf_A_im <= ram_dout_a[15:0];
                    bf_B_re <= ram_dout_b[31:16]; bf_B_im <= ram_dout_b[15:0];
                    bf_W_re <= tw_re; bf_W_im <= tw_im;
                    bf_start <= 1;
                    state <= 4;
                end
                
                4: begin
                    bf_start <= 0;
                    if (bf_done) begin
                        ram_din_a <= {bf_X_re, bf_X_im};
                        ram_din_b <= {bf_Y_re, bf_Y_im};
                        ram_we_a <= 1; ram_we_b <= 1;
                        state <= 5;
                    end
                end
                
                5: begin
                    ram_we_a <= 0; ram_we_b <= 0;
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
                                state <= 1;
                            end
                        end else begin
                            k <= k + m;
                            state <= 1;
                        end
                    end else begin
                        j <= j + 1;
                        state <= 1;
                    end
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
