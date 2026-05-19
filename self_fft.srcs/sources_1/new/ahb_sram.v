`timescale 1ns / 1ps
// *******************************************************************
// Module: ahb_sram
// Description: Fully compliant AMBA AHB (v2.0) Slave SRAM Controller.
//              Supports byte, half-word, and word write operations
//              using byte-lane strobe generation based on HSIZE & HADDR.
//              Implements zero wait-state reads/writes with a write-read
//              address collision bypass.
// *******************************************************************

module ahb_sram #(
    parameter AHB_MAX_ADDR = 12 // 2^12 = 4096 words = 16KB of Scratchpad RAM
)(
    input  wire        hclk,
    input  wire        hresetn,
    
    // AHB slave bus interface
    input  wire        hsel,
    input  wire [31:0] haddr,
    input  wire        hwrite,
    input  wire [1:0]  htrans,
    input  wire [2:0]  hsize,
    input  wire [2:0]  hburst,
    input  wire [31:0] hwdata,
    input  wire [3:0]  hprot,
    input  wire        hready_in, // Bus status indicating previous master transfer has completed
    
    // AHB slave outputs
    output wire        hready_out,
    output wire [1:0]  hresp,
    output wire [31:0] hrdata
);

    // -----------------------------------------------------------------------
    // AHB Transfer Definitions
    // -----------------------------------------------------------------------
    localparam TR_IDLE   = 2'b00;
    localparam TR_BUSY   = 2'b01;
    localparam TR_NONSEQ = 2'b10;
    localparam TR_SEQ    = 2'b11;
    
    localparam RESP_OKAY = 2'b00;
    
    // -----------------------------------------------------------------------
    // Pipelined Address Phase Registers (Latch control for Data Phase)
    // -----------------------------------------------------------------------
    reg [31:0] r_haddr;
    reg        r_hwrite;
    reg [1:0]  r_htrans;
    reg [2:0]  r_hsize;
    reg        r_hsel;
    
    wire active_transfer = hsel && hready_in && (htrans == TR_NONSEQ || htrans == TR_SEQ);
    
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            r_haddr  <= 32'b0;
            r_hwrite <= 1'b0;
            r_htrans <= TR_IDLE;
            r_hsize  <= 3'b010;
            r_hsel   <= 1'b0;
        end else if (hready_in) begin
            r_haddr  <= haddr;
            r_hwrite <= hwrite;
            r_htrans <= htrans;
            r_hsize  <= hsize;
            r_hsel   <= hsel;
        end else begin
            // If the bus is stalled (hready_in is low), we must maintain
            // our pipelined state until it clears.
            r_htrans <= TR_IDLE; 
        end
    end

    // -----------------------------------------------------------------------
    // Byte-lane Write Strobe Decoder
    // -----------------------------------------------------------------------
    reg [3:0] write_strobe;
    wire active_write = r_hsel && r_hwrite && (r_htrans == TR_NONSEQ || r_htrans == TR_SEQ);
    
    always @(*) begin
        write_strobe = 4'b0000;
        if (active_write) begin
            case (r_hsize)
                3'b000: begin // 8-bit (Byte) write
                    case (r_haddr[1:0])
                        2'b00: write_strobe = 4'b0001;
                        2'b01: write_strobe = 4'b0010;
                        2'b10: write_strobe = 4'b0100;
                        2'b11: write_strobe = 4'b1000;
                    endcase
                end
                3'b001: begin // 16-bit (Half-word) write
                    if (r_haddr[1] == 1'b0)
                        write_strobe = 4'b0011;
                    else
                        write_strobe = 4'b1100;
                end
                3'b010: begin // 32-bit (Word) write
                    write_strobe = 4'b1111;
                end
                default: begin
                    write_strobe = 4'b1111; // Fallback
                end
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Memory Instance: 4 Byte-Wide Memory Blocks (Block RAM Inference)
    // -----------------------------------------------------------------------
    reg [7:0] ram0 [0:(1<<AHB_MAX_ADDR)-1];
    reg [7:0] ram1 [0:(1<<AHB_MAX_ADDR)-1];
    reg [7:0] ram2 [0:(1<<AHB_MAX_ADDR)-1];
    reg [7:0] ram3 [0:(1<<AHB_MAX_ADDR)-1];

    // RAM address is mapped directly using words (byte address aligned / 4)
    wire [AHB_MAX_ADDR-1:0] ram_write_addr = r_haddr[AHB_MAX_ADDR+1:2];
    wire [AHB_MAX_ADDR-1:0] ram_read_addr  = haddr[AHB_MAX_ADDR+1:2];
    
    // RAM write port
    always @(posedge hclk) begin
        if (write_strobe[0]) ram0[ram_write_addr] <= hwdata[7:0];
        if (write_strobe[1]) ram1[ram_write_addr] <= hwdata[15:8];
        if (write_strobe[2]) ram2[ram_write_addr] <= hwdata[23:16];
        if (write_strobe[3]) ram3[ram_write_addr] <= hwdata[31:24];
    end
    
    // RAM read ports (synchronous RAM read)
    reg [7:0] r_ram0_out;
    reg [7:0] r_ram1_out;
    reg [7:0] r_ram2_out;
    reg [7:0] r_ram3_out;
    
    wire active_read = hsel && !hwrite && hready_in && (htrans == TR_NONSEQ || htrans == TR_SEQ);
    
    always @(posedge hclk) begin
        if (hready_in) begin
            r_ram0_out <= ram0[ram_read_addr];
            r_ram1_out <= ram1[ram_read_addr];
            r_ram2_out <= ram2[ram_read_addr];
            r_ram3_out <= ram3[ram_read_addr];
        end
    end
    
    wire [31:0] ram_rdata = {r_ram3_out, r_ram2_out, r_ram1_out, r_ram0_out};

    // -----------------------------------------------------------------------
    // Write-After-Read (WAR) & Read-After-Write (RAW) Data Bypass Logic
    // -----------------------------------------------------------------------
    // If a read is active in the data phase, but we wrote to the same word
    // in the previous cycle, the memory output won't have registered the write yet.
    // We detect this address collision and bypass the newly written data.
    reg        r_bypass_en;
    reg [3:0]  r_bypass_strobe;
    reg [31:0] r_bypass_data;
    
    wire read_data_phase = r_hsel && !r_hwrite && (r_htrans == TR_NONSEQ || r_htrans == TR_SEQ);
    
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            r_bypass_en     <= 1'b0;
            r_bypass_strobe <= 4'b0;
            r_bypass_data   <= 32'b0;
        end else if (hready_in) begin
            // Detect if a read address currently matches the write address latched in the write phase
            r_bypass_en     <= active_write && active_read && (ram_write_addr == ram_read_addr);
            r_bypass_strobe <= write_strobe;
            r_bypass_data   <= hwdata;
        end
    end
    
    // Combine memory output and write bypass data
    wire [31:0] final_rdata;
    assign final_rdata[7:0]   = (r_bypass_en && r_bypass_strobe[0]) ? r_bypass_data[7:0]   : ram_rdata[7:0];
    assign final_rdata[15:8]  = (r_bypass_en && r_bypass_strobe[1]) ? r_bypass_data[15:8]  : ram_rdata[15:8];
    assign final_rdata[23:16] = (r_bypass_en && r_bypass_strobe[2]) ? r_bypass_data[23:16] : ram_rdata[23:16];
    assign final_rdata[31:24] = (r_bypass_en && r_bypass_strobe[3]) ? r_bypass_data[31:24] : ram_rdata[31:24];

    // -----------------------------------------------------------------------
    // AHB Response Output Drivers (Zero Wait States)
    // -----------------------------------------------------------------------
    assign hready_out = 1'b1;        // SRAM responds instantly, zero wait-states
    assign hresp      = RESP_OKAY;   // Always return OKAY responses
    assign hrdata     = read_data_phase ? final_rdata : 32'b0;

endmodule
