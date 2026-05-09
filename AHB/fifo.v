// *******************************************************************
// AHB system generator - FIFO (converted from VHDL)
// Original Author: Federico Aglietti, federico.aglietti@opencores.org
// *******************************************************************
// Parameterized synchronous FIFO with programmable almost-full/almost-empty
// flags. fifo_length must be a power of 2 and >= 2.
// The count/pointer width = ceil(log2(fifo_length)) + 1 bits.

`include "ahb_package.vh"

module fifo #(
    parameter FIFOHEMPTY_LEVEL = 1,
    parameter FIFOHFULL_LEVEL  = 3,
    parameter FIFO_LENGTH      = 4,
    // Derived: address width = ceil(log2(FIFO_LENGTH))
    parameter PTR_WIDTH        = 3   // must be set by user to ceil(log2(FIFO_LENGTH))+1
)(
    input  wire                   hresetn,
    input  wire                   clk,
    input  wire                   fifo_reset,
    input  wire                   fifo_write,
    input  wire                   fifo_read,
    output wire [PTR_WIDTH-1:0]   fifo_count,
    output wire                   fifo_full,
    output wire                   fifo_hfull,
    output wire                   fifo_empty,
    output wire                   fifo_hempty,
    input  wire [31:0]            fifo_datain,
    output wire [31:0]            fifo_dataout
);

    // -----------------------------------------------------------------------
    // Storage
    // -----------------------------------------------------------------------
    reg [31:0] mem [0:FIFO_LENGTH-1];

    // Read and write pointers are one bit wider than the address to allow
    // full vs empty discrimination (MSBs differ when full, equal when empty).
    reg [PTR_WIDTH-1:0] wptr;
    reg [PTR_WIDTH-1:0] rptr;

    // -----------------------------------------------------------------------
    // Write pointer
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge hresetn) begin
        if (!hresetn) begin
            wptr <= {PTR_WIDTH{1'b0}};
        end else begin
            if (fifo_reset) begin
                wptr <= {PTR_WIDTH{1'b0}};
            end else if (fifo_write) begin
                mem[wptr[PTR_WIDTH-2:0]] <= fifo_datain;
                wptr <= wptr + 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Read pointer
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge hresetn) begin
        if (!hresetn) begin
            rptr <= {PTR_WIDTH{1'b0}};
        end else begin
            if (fifo_reset) begin
                rptr <= {PTR_WIDTH{1'b0}};
            end else if (fifo_read) begin
                rptr <= rptr + 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Outputs
    // -----------------------------------------------------------------------
    assign fifo_dataout = mem[rptr[PTR_WIDTH-2:0]];

    wire [PTR_WIDTH-1:0] count_s = wptr - rptr;

    assign fifo_full   = (count_s == FIFO_LENGTH);
    assign fifo_empty  = (count_s == {PTR_WIDTH{1'b0}});
    assign fifo_hfull  = (count_s >= FIFOHFULL_LEVEL);
    assign fifo_hempty = (count_s <= FIFOHEMPTY_LEVEL);
    assign fifo_count  = count_s;

endmodule
