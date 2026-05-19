`timescale 1ns / 1ps
// *******************************************************************
// Module: nm32_soc_top
// Description: Top-level SoC wrapper containing the central AHB
//              interconnect (Arbiter + Decoder + Multiplexers),
//              the NM32 FFT Accelerator (Slave 0), and a 16KB
//              custom Scratchpad RAM (Slave 1).
// *******************************************************************

module nm32_soc_top (
    input  wire        hclk,
    input  wire        hresetn,
    
    // Master Port (Exposed to drive the system via testbench or processor)
    input  wire        m_hbusreq,
    input  wire        m_hlock,
    input  wire [1:0]  m_htrans,
    input  wire [31:0] m_haddr,
    input  wire        m_hwrite,
    input  wire [2:0]  m_hsize,
    input  wire [2:0]  m_hburst,
    input  wire [3:0]  m_hprot,
    input  wire [31:0] m_hwdata,
    
    // Master Feedback outputs
    output wire        m_hgrant,
    output wire        m_hready,
    output wire [1:0]  m_hresp,
    output wire [31:0] m_hrdata
);

    // -----------------------------------------------------------------------
    // Address Map Flat Parameters
    // -----------------------------------------------------------------------
    // In ahb_arbiter, address low/high is flat-mapped into a 512-bit vector.
    // Each slave 'i' takes a 32-bit slice at [32*i +: 32].
    //
    // Slave 0 (FFT Wrapper): 0x0000_4000 to 0x0000_4FFF (4KB)
    // Slave 1 (SRAM Scratch): 0x0000_0000 to 0x0000_3FFF (16KB)
    //
    // Slice 0 = 32'h0000_4000 (S0 Low), Slice 1 = 32'h0000_0000 (S1 Low)
    // Slice 0 = 32'h0000_4FFF (S0 High), Slice 1 = 32'h0000_3FFF (S1 High)
    
    localparam [511:0] ADDR_LOW_FLAT  = { 448'h0, 32'h0000_0000, 32'h0000_4000 };
    localparam [511:0] ADDR_HIGH_FLAT = { 448'h0, 32'h0000_3FFF, 32'h0000_4FFF };

    // -----------------------------------------------------------------------
    // Master Unpacked Arrays for ahb_arbiter
    // -----------------------------------------------------------------------
    wire [14:0] mst_hbusreq;
    wire [14:0] mst_hlock;
    wire [29:0] mst_htrans;
    
    wire [31:0] arb_mst_haddr   [0:14];
    wire [2:0]  arb_mst_hsize   [0:14];
    wire [2:0]  arb_mst_hburst  [0:14];
    wire [3:0]  arb_mst_hprot   [0:14];
    wire [31:0] arb_mst_hwdata  [0:14];
    wire [14:0] mst_hgrant;
    
    // Connect Master 0 to our top-level master port
    assign mst_hbusreq[0]     = m_hbusreq;
    assign mst_hlock[0]       = m_hlock;
    assign mst_htrans[1:0]    = m_htrans;
    
    assign arb_mst_haddr[0]   = m_haddr;
    assign arb_mst_hsize[0]   = m_hsize;
    assign arb_mst_hburst[0]  = m_hburst;
    assign arb_mst_hprot[0]   = m_hprot;
    assign arb_mst_hwdata[0]  = m_hwdata;
    
    assign m_hgrant           = mst_hgrant[0];

    // Connect unused master inputs to safe defaults (0)
    generate
        genvar m;
        for (m = 1; m < 15; m = m + 1) begin : gen_unused_msts
            assign mst_hbusreq[m]      = 1'b0;
            assign mst_hlock[m]        = 1'b0;
            assign mst_htrans[2*m+:2]  = 2'b00;
            assign arb_mst_haddr[m]    = 32'b0;
            assign arb_mst_hsize[m]    = 3'b000;
            assign arb_mst_hburst[m]   = 3'b000;
            assign arb_mst_hprot[m]    = 4'b0000;
            assign arb_mst_hwdata[m]   = 32'b0;
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Slave Signals from Arbiter to Slaves
    // -----------------------------------------------------------------------
    wire [1:0]  slv_hsel;
    wire [31:0] slv_haddr_out;
    wire        slv_hwrite_out;
    wire [1:0]  slv_htrans_out;
    wire [2:0]  slv_hsize_out;
    wire [2:0]  slv_hburst_out;
    wire [3:0]  slv_hprot_out;
    wire [31:0] slv_hwdata_out;
    wire [3:0]  slv_hmaster_out;
    wire        slv_hmastlock_out;
    wire        slv_hready_in;

    // Slave Outputs back to Interconnect Mux
    wire [1:0]  slv_hready_in_v;
    wire [1:0]  arb_slv_hresp   [0:14];
    wire [31:0] arb_slv_hrdata  [0:14];
    wire [15:0] arb_slv_hsplit  [0:14];

    // -----------------------------------------------------------------------
    // Instantiate AHB Arbiter & Address Decoder
    // -----------------------------------------------------------------------
    ahb_arbiter #(
        .NUM_ARB(0),
        .NUM_ARB_MSTS(1),
        .DEF_ARB_MST(0),
        .NUM_SLVS(2),
        .ALG_NUMBER(0), // Fixed priority
        .ADDR_LOW_FLAT(ADDR_LOW_FLAT),
        .ADDR_HIGH_FLAT(ADDR_HIGH_FLAT)
    ) interconnect_inst (
        .hresetn(hresetn),
        .hclk(hclk),
        .remap(1'b0),
        
        // Master Ports
        .mst_hbusreq(mst_hbusreq),
        .mst_hlock(mst_hlock),
        .mst_htrans(mst_htrans),
        .mst_haddr(arb_mst_haddr),
        .mst_hwrite({14'b0, m_hwrite}),
        .mst_hsize(arb_mst_hsize),
        .mst_hburst(arb_mst_hburst),
        .mst_hprot(arb_mst_hprot),
        .mst_hwdata(arb_mst_hwdata),
        
        .mst_hgrant(mst_hgrant),
        .mst_hready_out(m_hready),
        .mst_hresp_out(m_hresp),
        .mst_hrdata_out(m_hrdata),
        
        // Slave Interconnect signals
        .slv_hsel(slv_hsel),
        .slv_haddr_out(slv_haddr_out),
        .slv_hwrite_out(slv_hwrite_out),
        .slv_htrans_out(slv_htrans_out),
        .slv_hsize_out(slv_hsize_out),
        .slv_hburst_out(slv_hburst_out),
        .slv_hprot_out(slv_hprot_out),
        .slv_hwdata_out(slv_hwdata_out),
        .slv_hmaster_out(slv_hmaster_out),
        .slv_hmastlock_out(slv_hmastlock_out),
        .slv_hready_in(slv_hready_in),
        
        .slv_hready_in_v(slv_hready_in_v),
        .slv_hresp_v(arb_slv_hresp),
        .slv_hrdata_v(arb_slv_hrdata),
        .slv_hsplit_v(arb_slv_hsplit)
    );

    // -----------------------------------------------------------------------
    // Connect Unused Slave Ports on Interconnect Mux to Safe Defaults
    // -----------------------------------------------------------------------
    generate
        genvar s;
        for (s = 2; s < 15; s = s + 1) begin : gen_unused_slvs
            assign arb_slv_hresp[s]  = 2'b00; // OKAY response
            assign arb_slv_hrdata[s] = 32'b0;
            assign arb_slv_hsplit[s] = 16'b0;
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Slave 0: FFT Accelerator Wrapper
    // -----------------------------------------------------------------------
    wire [1:0]  s0_hresp;
    wire [31:0] s0_hrdata;
    wire [15:0] s0_hsplit;
    wire        s0_err;

    nm32_fft_ahb_wrapper #(
        .BASE_ADDR(32'h0000_4000),
        .ADDR_MASK(32'h0000_0FFF) // 4KB segment
    ) fft_wrapper_inst (
        .hclk(hclk),
        .hresetn(hresetn),
        
        .slv_hsel(slv_hsel[0]),
        .slv_haddr(slv_haddr_out),
        .slv_hwrite(slv_hwrite_out),
        .slv_htrans(slv_htrans_out),
        .slv_hsize(slv_hsize_out),
        .slv_hburst(slv_hburst_out),
        .slv_hwdata(slv_hwdata_out),
        .slv_hprot(slv_hprot_out),
        .slv_hready(slv_hready_in),
        .slv_hmaster(slv_hmaster_out),
        .slv_hmastlock(slv_hmastlock_out),
        
        .slv_hready_out(slv_hready_in_v[0]),
        .slv_hresp(s0_hresp),
        .slv_hrdata(s0_hrdata),
        .slv_hsplit(s0_hsplit),
        .slv_err(s0_err)
    );
    
    assign arb_slv_hresp[0]  = s0_hresp;
    assign arb_slv_hrdata[0] = s0_hrdata;
    assign arb_slv_hsplit[0] = s0_hsplit;

    // -----------------------------------------------------------------------
    // Slave 1: Custom Scratchpad RAM (16KB)
    // -----------------------------------------------------------------------
    wire [1:0]  s1_hresp;
    wire [31:0] s1_hrdata;

    ahb_sram #(
        .AHB_MAX_ADDR(12) // 16KB SRAM
    ) sram_scratch_inst (
        .hclk(hclk),
        .hresetn(hresetn),
        
        .hsel(slv_hsel[1]),
        .haddr(slv_haddr_out),
        .hwrite(slv_hwrite_out),
        .htrans(slv_htrans_out),
        .hsize(slv_hsize_out),
        .hburst(slv_hburst_out),
        .hwdata(slv_hwdata_out),
        .hprot(slv_hprot_out),
        .hready_in(slv_hready_in),
        
        .hready_out(slv_hready_in_v[1]),
        .hresp(s1_hresp),
        .hrdata(s1_hrdata)
    );
    
    assign arb_slv_hresp[1]  = s1_hresp;
    assign arb_slv_hrdata[1] = s1_hrdata;
    assign arb_slv_hsplit[1] = 16'b0; // SRAM doesn't issue SPLITs

endmodule
