`timescale 1ns / 1ps

module tb_ahb_fft();

    // Clock and Reset
    reg hclk;
    reg hresetn;

    // AHB Master Signals
    reg        slv_hsel;
    reg [31:0] slv_haddr;
    reg        slv_hwrite;
    reg [1:0]  slv_htrans;
    reg [2:0]  slv_hsize;
    reg [2:0]  slv_hburst;
    reg [31:0] slv_hwdata;
    reg [3:0]  slv_hprot;
    reg        slv_hready;
    reg [3:0]  slv_hmaster;
    reg        slv_hmastlock;

    // AHB Slave Outputs
    wire        slv_hready_out;
    wire [1:0]  slv_hresp;
    wire [31:0] slv_hrdata;
    wire [15:0] slv_hsplit;
    wire        slv_err;

    // Device Under Test
    nm32_fft_ahb_wrapper #(
        .BASE_ADDR(32'h0000_0000),
        .ADDR_MASK(32'h0000_0FFF)
    ) uut (
        .hclk(hclk),
        .hresetn(hresetn),
        .slv_hsel(slv_hsel),
        .slv_haddr(slv_haddr),
        .slv_hwrite(slv_hwrite),
        .slv_htrans(slv_htrans),
        .slv_hsize(slv_hsize),
        .slv_hburst(slv_hburst),
        .slv_hwdata(slv_hwdata),
        .slv_hprot(slv_hprot),
        .slv_hready(slv_hready),
        .slv_hmaster(slv_hmaster),
        .slv_hmastlock(slv_hmastlock),
        .slv_hready_out(slv_hready_out),
        .slv_hresp(slv_hresp),
        .slv_hrdata(slv_hrdata),
        .slv_hsplit(slv_hsplit),
        .slv_err(slv_err)
    );

    // 180 MHz Clock Generation (5.55 ns period)
    always #2.778 hclk = ~hclk;

    // AHB Write Task
    task ahb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // Address Phase
            @(posedge hclk);
            slv_hsel <= 1;
            slv_haddr <= addr;
            slv_hwrite <= 1;
            slv_htrans <= 2'b10; // NONSEQ
            slv_hsize <= 3'b010; // 32-bit word
            slv_hready <= 1;
            
            // Data Phase
            @(posedge hclk);
            slv_hsel <= 0;
            slv_htrans <= 2'b00; // IDLE
            slv_hwdata <= data;
            
            // Wait for HREADY_OUT
            while (slv_hready_out == 1'b0) begin
                @(posedge hclk);
            end
        end
    endtask

    // AHB Read Task
    task ahb_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            // Address Phase
            @(posedge hclk);
            slv_hsel <= 1;
            slv_haddr <= addr;
            slv_hwrite <= 0;
            slv_htrans <= 2'b10; // NONSEQ
            slv_hsize <= 3'b010; // 32-bit word
            slv_hready <= 1;
            
            // Data Phase
            @(posedge hclk);
            slv_hsel <= 0;
            slv_htrans <= 2'b00; // IDLE
            
            // Wait for HREADY_OUT
            while (slv_hready_out == 1'b0) begin
                @(posedge hclk);
            end
            data = slv_hrdata;
        end
    endtask

    // Main Test Sequence
    reg [31:0] audio_mem [0:511];
    integer i, outfile;
    reg [31:0] read_data;

    initial begin
        // Initialize Signals
        hclk = 0;
        hresetn = 0;
        slv_hsel = 0;
        slv_haddr = 0;
        slv_hwrite = 0;
        slv_htrans = 0;
        slv_hsize = 0;
        slv_hburst = 0;
        slv_hwdata = 0;
        slv_hprot = 4'b0011;
        slv_hready = 1;
        slv_hmaster = 0;
        slv_hmastlock = 0;

        // Load Input Data (Using Relative Path)
        $readmemh("audio_in.txt", audio_mem);

        // Reset Sequence
        #50 hresetn = 1;
        #20;
        @(posedge hclk);

        $display("-----------------------------------------");
        $display("Starting AHB Mic DMA Transfer...");
        // 1. DMA: Write 512 samples to 0x000 - 0x7FC
        for (i = 0; i < 512; i = i + 1) begin
            ahb_write(i * 4, audio_mem[i]);
        end
        $display("DMA Transfer Complete.");

        // 2. SoC: Start FFT (Write 1 to 0x800)
        $display("Sending START command over AHB...");
        ahb_write(32'h800, 32'h0000_0001);

        // 3. SoC: Poll for DONE (Read bit 1 of 0x800)
        $display("Polling for DONE bit...");
        read_data = 0;
        while ((read_data & 32'h0000_0002) == 0) begin
            ahb_read(32'h800, read_data);
        end
        $display("FFT Processing Complete!");

        // 4. DMA: Read Output Data to 0x000 - 0x7FC
        $display("Reading Output Frequencies over AHB...");
        outfile = $fopen("fft_out.txt", "w");
        for (i = 0; i < 512; i = i + 1) begin
            ahb_read(i * 4, read_data);
            $fdisplay(outfile, "%08X", read_data);
        end
        $fclose(outfile);
        
        $display("-----------------------------------------");
        $display("Testbench Finished Successfully.");
        $display("Output written to 'fft_out.txt'");
        $display("-----------------------------------------");
        
        $finish;
    end

endmodule
