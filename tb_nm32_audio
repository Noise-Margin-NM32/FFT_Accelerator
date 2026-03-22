`timescale 1ns / 1ps

module tb_nm32_audio();

    reg clk;
    reg rst;
    reg start;
    reg ext_we;
    reg [8:0] ext_addr;
    reg [31:0] ext_din;
    wire [31:0] ext_dout;
    wire done;

    nm32_fft_top uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .ext_we(ext_we),
        .ext_addr(ext_addr),
        .ext_din(ext_din),
        .ext_dout(ext_dout),
        .done(done)
    );

    always #2.778 clk = ~clk; 

    reg [31:0] audio_mem [0:511];
    integer i, outfile;

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        ext_we = 0;
        ext_addr = 0;
        ext_din = 0;

        $readmemh("audio_in.txt", audio_mem);

        #50 rst = 0;
        #20;

        for (i = 0; i < 512; i = i + 1) begin
            @(posedge clk);
            ext_we = 1;
            ext_addr = i;
            ext_din = audio_mem[i];
        end
        
        @(posedge clk);
        ext_we = 0;

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        @(posedge clk);

        outfile = $fopen("fft_out.txt", "w");
        
        for (i = 0; i < 512; i = i + 1) begin
            ext_addr = i;
            @(posedge clk); 
            @(posedge clk); 
            $fdisplay(outfile, "%08X", ext_dout);
        end
        
        $fclose(outfile);
        
        $display("\n========================================");
        $display(" A.U.R.A. SoC - NM32 kavach FFT Engine  ");
        $display(" 180 MHz Audio Frame Processing Complete");
        $display(" Output successfully saved to fft_out.txt");
        $display("========================================\n");
        
        $finish;
    end

endmodule
