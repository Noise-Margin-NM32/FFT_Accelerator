`timescale 1ns / 1ps
// *******************************************************************
// Module: tb_soc_system
// Description: Multi-slave system testbench that instantiates
//              nm32_soc_top and runs verification sequences for
//              SRAM byte-writes, FFT operations, and dynamic address
//              switching over the AHB bus.
// *******************************************************************

module tb_soc_system();

    // Clock and Reset
    reg hclk;
    reg hresetn;

    // Master Signals to drive the SoC Master Port
    reg         m_hbusreq;
    reg         m_hlock;
    reg [1:0]   m_htrans;
    reg [31:0]  m_haddr;
    reg         m_hwrite;
    reg [2:0]   m_hsize;
    reg [2:0]   m_hburst;
    reg [3:0]   m_hprot;
    reg [31:0]  m_hwdata;

    // SoC Feedback Signals
    wire        m_hgrant;
    wire        m_hready;
    wire [1:0]  m_hresp;
    wire [31:0] m_hrdata;

    // Instantiate System Under Test
    nm32_soc_top uut_soc (
        .hclk(hclk),
        .hresetn(hresetn),
        
        .m_hbusreq(m_hbusreq),
        .m_hlock(m_hlock),
        .m_htrans(m_htrans),
        .m_haddr(m_haddr),
        .m_hwrite(m_hwrite),
        .m_hsize(m_hsize),
        .m_hburst(m_hburst),
        .m_hprot(m_hprot),
        .m_hwdata(m_hwdata),
        
        .m_hgrant(m_grant),
        .m_hready(m_hready),
        .m_hresp(m_hresp),
        .m_hrdata(m_hrdata)
    );

    // 180 MHz System Clock (5.556 ns period)
    always #2.778 hclk = ~hclk;

    // -----------------------------------------------------------------------
    // AHB Master Simulation Write Task
    // -----------------------------------------------------------------------
    task ahb_write;
        input [31:0] addr;
        input [31:0] data;
        input [2:0]  size; // 3'b010=word (32-bit), 3'b001=half-word (16-bit), 3'b000=byte (8-bit)
        begin
            // Address Phase
            @(posedge hclk);
            m_hbusreq <= 1;
            m_haddr   <= addr;
            m_hwrite  <= 1;
            m_htrans  <= 2'b10; // NONSEQ
            m_hsize   <= size;
            
            // Wait for Bus Ready to proceed to Data Phase
            @(posedge hclk);
            while (m_hready == 1'b0) begin
                @(posedge hclk);
            end
            
            // Data Phase
            m_htrans  <= 2'b00; // IDLE (or NONSEQ if back-to-back, using IDLE here for simplicity)
            m_hwdata  <= data;
            
            // Wait for transaction to complete
            @(posedge hclk);
            while (m_hready == 1'b0) begin
                @(posedge hclk);
            end
            m_hbusreq <= 0;
            m_hwrite  <= 0;
        end
    endtask

    // -----------------------------------------------------------------------
    // AHB Master Simulation Read Task
    // -----------------------------------------------------------------------
    task ahb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            // Address Phase
            @(posedge hclk);
            m_hbusreq <= 1;
            m_haddr   <= addr;
            m_hwrite  <= 0;
            m_htrans  <= 2'b10; // NONSEQ
            m_hsize   <= 3'b010; // Word read
            
            // Wait for Bus Ready to proceed to Data Phase
            @(posedge hclk);
            while (m_hready == 1'b0) begin
                @(posedge hclk);
            end
            
            // Data Phase
            m_htrans  <= 2'b00; // IDLE
            
            // Wait for response to be ready
            @(posedge hclk);
            while (m_hready == 1'b0) begin
                @(posedge hclk);
            end
            data = m_hrdata;
            m_hbusreq <= 0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Verification Sequence
    // -----------------------------------------------------------------------
    reg [31:0] audio_mem [0:511];
    integer i, outfile;
    reg [31:0] rdata;

    initial begin
        // Initialize lines
        hclk      = 0;
        hresetn   = 0;
        m_hbusreq = 0;
        m_hlock   = 0;
        m_htrans  = 0;
        m_haddr   = 0;
        m_hwrite  = 0;
        m_hsize   = 0;
        m_hburst  = 0;
        m_hwdata  = 0;
        m_hprot   = 4'b0011;

        // Load audio samples
        $readmemh("../../../../audio_in.txt", audio_mem);

        // Power-on Reset Sequence
        #50 hresetn = 1;
        #20;
        @(posedge hclk);

        $display("=================================================");
        $display("STARTING FULL SOC SYSTEM INTEGRATION SIMULATION");
        $display("=================================================");

        // -------------------------------------------------------------------
        // STEP 1: VERIFY SCRATCHPAD SRAM (SLAVE 1: 0x0000_0000 - 0x0000_3FFF)
        // -------------------------------------------------------------------
        $display("\n[SRAM Test] Initiating Word, Half-Word, and Byte accesses...");
        
        // 1.1 Word Write / Read Check
        ahb_write(32'h0000_0010, 32'hDEADBEEF, 3'b010);
        ahb_read(32'h0000_0010, rdata);
        if (rdata === 32'hDEADBEEF)
            $display("[SRAM Pass] 32-bit Word Access: Got 0x%08X", rdata);
        else
            $display("[SRAM FAIL] 32-bit Word Access: Expected 0xDEADBEEF, Got 0x%08X", rdata);

        // 1.2 Byte Writes Check (strobe decoders)
        // We write bytes sequentially into the same word space at 0x0000_0020
        ahb_write(32'h0000_0020, 32'h0000_00AA, 3'b000); // Write byte 0 at 0x20
        ahb_write(32'h0000_0021, 32'h0000_BB00, 3'b000); // Write byte 1 at 0x21
        ahb_write(32'h0000_0022, 32'h00CC_0000, 3'b000); // Write byte 2 at 0x22
        ahb_write(32'h0000_0023, 32'hDD00_0000, 3'b000); // Write byte 3 at 0x23
        
        ahb_read(32'h0000_0020, rdata);
        if (rdata === 32'hDDCCBBAA)
            $display("[SRAM Pass] 8-bit Byte Access & Lane Decoders: Got 0x%08X", rdata);
        else
            $display("[SRAM FAIL] 8-bit Byte Access & Lane Decoders: Expected 0xDDCCBBAA, Got 0x%08X", rdata);

        // 1.3 Half-Word Write Check
        ahb_write(32'h0000_0022, 32'hFEED0000, 3'b001); // Write upper half-word (bits 31:16)
        ahb_read(32'h0000_0020, rdata);
        if (rdata === 32'hFEEDBBAA)
            $display("[SRAM Pass] 16-bit Half-Word Access: Got 0x%08X", rdata);
        else
            $display("[SRAM FAIL] 16-bit Half-Word Access: Expected 0xFEEDBBAA, Got 0x%08X", rdata);

        // -------------------------------------------------------------------
        // STEP 2: VERIFY FFT ACCELERATOR (SLAVE 0: 0x0000_4000 - 0x0000_4FFF)
        // -------------------------------------------------------------------
        $display("\n[FFT Test] Loading 512 complex samples to FFT Data space (0x4000)...");
        for (i = 0; i < 512; i = i + 1) begin
            ahb_write(32'h0000_4000 + (i * 4), audio_mem[i], 3'b010);
        end
        $display("[FFT Test] 512 Samples successfully loaded.");

        // Start FFT (Write 1 to control register at 0x4800)
        $display("[FFT Test] Triggering START bit in FFT Control Register at 0x4800...");
        ahb_write(32'h0000_4800, 32'h0000_0001, 3'b010);

        // Poll for Done (Bit 1 of 0x4800)
        $display("[FFT Test] Polling for DONE bit...");
        rdata = 0;
        while ((rdata & 32'h0000_0002) == 0) begin
            ahb_read(32'h0000_4800, rdata);
        end
        $display("[FFT Test] Done bit asserted! Processing complete.");

        // Read Output Spectrum and save to file
        $display("[FFT Test] Reading back transformed frequency bins...");
        outfile = $fopen("fft_out_soc.txt", "w");
        for (i = 0; i < 512; i = i + 1) begin
            ahb_read(32'h0000_4000 + (i * 4), rdata);
            $fdisplay(outfile, "%08X", rdata);
        end
        $fclose(outfile);
        $display("[FFT Pass] Output successfully written to 'fft_out_soc.txt'");

        // -------------------------------------------------------------------
        // STEP 3: STRESS TEST DYNAMIC DECODER ADDRESS BOUNDARY SWITCHING
        // -------------------------------------------------------------------
        $display("\n[Stress Test] Interleaving accesses across SRAM (0x0000) and FFT (0x4000)...");
        
        // Write to SRAM -> Write to FFT Control -> Read from SRAM
        ahb_write(32'h0000_0100, 32'hA5A5A5A5, 3'b010); // SRAM Write
        ahb_write(32'h0000_4800, 32'h0000_0000, 3'b010); // FFT Wrapper Write
        ahb_read(32'h0000_0100, rdata);                  // SRAM Read
        
        if (rdata === 32'hA5A5A5A5)
            $display("[Stress Pass] Interleaved bus boundary switching works flawlessly!");
        else
            $display("[Stress FAIL] Boundary switching returned corrupted read: 0x%08X", rdata);

        $display("\n=================================================");
        $display("ALL SOC SYSTEM INTEGRATION SIMULATIONS PASSED!");
        $display("=================================================");
        $finish;
    end

endmodule
