// *******************************************************************
// AHB system generator - AHB Slave (Wait type) (converted from VHDL)
// Original Author: Federico Aglietti, federico.aglietti@opencores.org
// *******************************************************************
// Simple AHB slave supporting OKAY/WAIT responses only (v1.0).
// Errors on unaligned or out-of-range addresses.

`include "ahb_package.vh"

module ahb_slave_wait #(
    parameter NUM_SLV          = 1,
    parameter FIFOHEMPTY_LEVEL = 2,  // unused for wait slave
    parameter FIFOHFULL_LEVEL  = 5,  // unused for wait slave
    parameter FIFO_LENGTH      = 8,  // unused for wait slave
    // Slave address range (set from ahb_configure)
    parameter [31:0] ADDR_LOW  = 32'h0000_0000,
    parameter [31:0] ADDR_HIGH = 32'h0000_FFFF
)(
    input  wire        hresetn,
    input  wire        hclk,
    input  wire        remap,
    // AHB slave bus inputs
    input  wire        slv_hsel,
    input  wire [31:0] slv_haddr,
    input  wire        slv_hwrite,
    input  wire [1:0]  slv_htrans,
    input  wire [2:0]  slv_hsize,
    input  wire [2:0]  slv_hburst,
    input  wire [31:0] slv_hwdata,
    input  wire [3:0]  slv_hprot,
    input  wire        slv_hready,
    input  wire [3:0]  slv_hmaster,
    input  wire        slv_hmastlock,
    // AHB slave outputs
    output reg         slv_hready_out,
    output reg [1:0]   slv_hresp,
    output wire [31:0] slv_hrdata,
    output wire [15:0] slv_hsplit,
    // Slave error flag
    output reg         slv_err,
    // Wrapper interface
    input  wire        mst_running,
    input  wire        prior_in,
    output wire        slv_running,
    output reg [31:0]  s_wrap_addr,
    output reg         s_wrap_take,
    output reg [31:0]  s_wrap_wdata,
    output reg         s_wrap_ask,
    input  wire        s_wrap_take_ok,
    input  wire        s_wrap_ask_ok,
    input  wire [31:0] s_wrap_rdata
);

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    localparam DATA_CYCLE  = 1'b0;
    localparam ERROR_CYCLE = 1'b1;

    reg slv_state, s_slv_state;

    // -----------------------------------------------------------------------
    // Registered slave inputs
    // -----------------------------------------------------------------------
    reg        r_hsel;
    reg [31:0] r_haddr;
    reg        r_hwrite;
    reg [1:0]  r_htrans;
    reg [2:0]  r_hsize;
    reg [2:0]  r_hburst;
    reg [3:0]  r_hprot;
    reg        r_hmastlock;
    reg        r_hready;

    // -----------------------------------------------------------------------
    // Address decode / error detection
    // -----------------------------------------------------------------------
    reg dec_error;

    always @(*) begin
        dec_error = 1'b0;
        if (r_hsel) begin
            if (r_hsize != `BITS32)
                dec_error = 1'b1;
            if (r_haddr[1:0] != 2'b00)
                dec_error = 1'b1;
            if (r_haddr[31:10] < ADDR_LOW[31:10])
                dec_error = 1'b1;
            if (r_haddr[31:10] > ADDR_HIGH[31:10])
                dec_error = 1'b1;
        end
    end

    // -----------------------------------------------------------------------
    // FSM next-state
    // -----------------------------------------------------------------------
    always @(*) begin
        s_slv_state = slv_state;
        case (slv_state)
            DATA_CYCLE:  if (dec_error) s_slv_state = ERROR_CYCLE;
            ERROR_CYCLE: s_slv_state = DATA_CYCLE;
            default:     s_slv_state = DATA_CYCLE;
        endcase
    end

    reg r_hready_reg;
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            slv_state   <= DATA_CYCLE;
            r_hready_reg <= 1'b1;
        end else begin
            slv_state    <= s_slv_state;
            r_hready_reg <= slv_hready_out;
        end
    end

    // -----------------------------------------------------------------------
    // Register slave inputs on hready
    // -----------------------------------------------------------------------
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            r_hsel      <= 1'b0;
            r_hready    <= 1'b0;
            r_haddr     <= 32'b0;
            r_hwrite    <= 1'b0;
            r_htrans    <= `IDLE;
            r_hsize     <= `BITS32;
            r_hburst    <= `INCR;
            r_hprot     <= 4'b0011;
            r_hmastlock <= 1'b0;
        end else begin
            r_hready <= slv_hready;
            if (slv_hready) begin
                r_hsel      <= slv_hsel;
                r_hburst    <= slv_hburst;
                r_hprot     <= slv_hprot;
                r_hsize     <= slv_hsize;
                r_hwrite    <= slv_hwrite;
                r_hmastlock <= slv_hmastlock;
            end
            if (slv_hready && r_htrans != `BUSY) begin
                r_haddr <= slv_haddr;
            end
            if (slv_hready) begin
                r_htrans <= slv_htrans;
            end
        end
    end

    // -----------------------------------------------------------------------
    // hready output
    // -----------------------------------------------------------------------
    wire hready_t;
    assign hready_t =
        (slv_state == ERROR_CYCLE) ||
        (r_htrans == `IDLE) ||
        (r_htrans == `BUSY) ||
        ((r_htrans == `NONSEQ || r_htrans == `SEQ) && !dec_error &&
         ((r_hwrite && s_wrap_take_ok) || (!r_hwrite && s_wrap_ask_ok)));

    // -----------------------------------------------------------------------
    // hresp output
    // -----------------------------------------------------------------------
    wire [1:0] hresp_t;
    assign hresp_t = (dec_error || slv_state == ERROR_CYCLE) ? `ERROR_RESP : `OK_RESP;

    always @(*) begin
        slv_err      = (slv_state == ERROR_CYCLE);
        slv_hready_out = hready_t;
        slv_hresp      = hresp_t;
    end

    // -----------------------------------------------------------------------
    // Wrapper outputs
    // -----------------------------------------------------------------------
    always @(*) begin
        s_wrap_addr  = r_haddr;
        s_wrap_wdata = slv_hwdata;
        s_wrap_take  = 1'b0;
        s_wrap_ask   = 1'b0;
        if (slv_state == DATA_CYCLE && !dec_error &&
            slv_htrans != `BUSY && r_hsel &&
            (r_htrans == `NONSEQ || r_htrans == `SEQ)) begin
            s_wrap_take = r_hwrite;
            s_wrap_ask  = !r_hwrite;
        end
    end

    // -----------------------------------------------------------------------
    // hrdata / hsplit
    // -----------------------------------------------------------------------
    assign slv_hrdata = s_wrap_rdata;
    assign slv_hsplit = 16'b0;

    // slv_running (unused in wait-type slave but driven for compatibility)
    assign slv_running = r_hsel && (r_htrans == `NONSEQ || r_htrans == `SEQ);

endmodule
