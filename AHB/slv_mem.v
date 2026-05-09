// *******************************************************************
// AHB system generator - Slave Memory (converted from VHDL)
// Original Author: Federico Aglietti, federico.aglietti@opencores.org
// *******************************************************************
// Acts as the internal memory that the AHB slave accesses.
// Supports programmable read/write latency and burst mode.

`include "ahb_package.vh"

module slv_mem #(
    parameter AHB_MAX_ADDR      = 8,
    parameter S_CONST_LAT_WRITE = 1,
    parameter S_CONST_LAT_READ  = 2,
    parameter S_WRITE_BURST     = `NO_BURST_SUPPORT,
    parameter S_READ_BURST      = `NO_BURST_SUPPORT
)(
    input  wire        hresetn,
    input  wire        clk,

    // Configuration bus
    input  wire        conf_write,
    input  wire [3:0]  conf_addr,
    input  wire [31:0] conf_wdata,

    // DMA start outputs (slave can also initiate DMA)
    output reg         dma_start,
    output reg [31:0]  dma_extaddr,
    output reg [15:0]  dma_intaddr,
    output reg [15:0]  dma_intmod,
    output reg [15:0]  dma_count,
    output reg [15:0]  dma_hparams,

    // Handshake with slave (wrap_in = what slave sends us)
    input  wire [31:0] s_wrap_addr,
    input  wire        s_wrap_take,
    input  wire [31:0] s_wrap_wdata,
    input  wire        s_wrap_ask,

    // Handshake response back to slave
    output wire        s_wrap_take_ok,
    output wire        s_wrap_ask_ok,
    output wire [31:0] s_wrap_rdata
);

    // -----------------------------------------------------------------------
    // Internal memory
    // -----------------------------------------------------------------------
    reg [31:0] mem [0:(1<<AHB_MAX_ADDR)-1];

    integer ii;
    always @(posedge clk or negedge hresetn) begin
        if (!hresetn) begin
            for (ii = 0; ii < (1<<AHB_MAX_ADDR); ii = ii + 1)
                mem[ii] <= ii[31:0];
        end else begin
            if (s_wrap_take && s_lat_write_ok)
                mem[s_wrap_addr[AHB_MAX_ADDR+1:2]] <= s_wrap_wdata;
        end
    end

    // -----------------------------------------------------------------------
    // Write latency counter
    // -----------------------------------------------------------------------
    reg [$clog2(S_CONST_LAT_WRITE+1)-1:0] s_lat_write;
    wire s_lat_write_ok = (s_lat_write == 0);

    always @(posedge clk or negedge hresetn) begin
        if (!hresetn) begin
            s_lat_write <= S_CONST_LAT_WRITE[$clog2(S_CONST_LAT_WRITE+1)-1:0];
        end else begin
            if (s_wrap_take) begin
                if (!s_lat_write_ok)
                    s_lat_write <= s_lat_write - 1;
                else if (S_WRITE_BURST == 1)
                    s_lat_write <= 0;
                else
                    s_lat_write <= S_CONST_LAT_WRITE[$clog2(S_CONST_LAT_WRITE+1)-1:0];
            end else begin
                s_lat_write <= S_CONST_LAT_WRITE[$clog2(S_CONST_LAT_WRITE+1)-1:0];
            end
        end
    end

    assign s_wrap_take_ok = s_wrap_take && s_lat_write_ok;

    // -----------------------------------------------------------------------
    // Read latency counter
    // -----------------------------------------------------------------------
    reg [$clog2(S_CONST_LAT_READ+1)-1:0] s_lat_read;
    wire s_lat_read_ok = (s_lat_read == 0);

    always @(posedge clk or negedge hresetn) begin
        if (!hresetn) begin
            s_lat_read <= S_CONST_LAT_READ[$clog2(S_CONST_LAT_READ+1)-1:0];
        end else begin
            if (s_wrap_ask) begin
                if (!s_lat_read_ok)
                    s_lat_read <= s_lat_read - 1;
                else if (S_READ_BURST == 1)
                    s_lat_read <= 0;
                else
                    s_lat_read <= S_CONST_LAT_READ[$clog2(S_CONST_LAT_READ+1)-1:0];
            end else begin
                s_lat_read <= S_CONST_LAT_READ[$clog2(S_CONST_LAT_READ+1)-1:0];
            end
        end
    end

    assign s_wrap_ask_ok = s_wrap_ask && s_lat_read_ok;
    assign s_wrap_rdata  = (s_wrap_ask && s_lat_read_ok) ?
                           mem[s_wrap_addr[AHB_MAX_ADDR+1:2]] : 32'bx;

    // -----------------------------------------------------------------------
    // Configuration registers (same layout as mst_wrap)
    // -----------------------------------------------------------------------
    reg [2:0]  hsize_reg;
    reg        priority_reg;
    reg [2:0]  hburst_reg;
    reg [3:0]  hprot_reg;
    reg        trx_dir_reg;
    reg        hlock_reg;
    reg [31:0] extaddr_reg;
    reg [15:0] intaddr_reg;
    reg [15:0] intmod_reg;
    reg [15:0] count_reg;
    reg        dma_go;

    always @(posedge clk or negedge hresetn) begin
        if (!hresetn) begin
            hsize_reg    <= `BITS32;
            priority_reg <= `SLAVE_PRI;
            hburst_reg   <= `INCR;
            hprot_reg    <= 4'b0011;
            trx_dir_reg  <= 1'b0;
            hlock_reg    <= `LOCKED;
            extaddr_reg  <= 32'b0;
            intaddr_reg  <= 16'b0;
            intmod_reg   <= 16'd4;
            count_reg    <= 16'b0;
            dma_go       <= 1'b0;
        end else begin
            dma_go <= 1'b0;
            if (conf_write) begin
                case (conf_addr)
                    `DMA_EXTADD_ADDR: extaddr_reg <= conf_wdata;
                    `DMA_INTADD_ADDR: intaddr_reg <= conf_wdata[15:0];
                    `DMA_INTMOD_ADDR: intmod_reg  <= conf_wdata[15:0];
                    `DMA_TYPE_ADDR: begin
                        priority_reg <= conf_wdata[12];
                        hsize_reg    <= conf_wdata[11:9];
                        hburst_reg   <= conf_wdata[8:6];
                        hprot_reg    <= conf_wdata[5:2];
                        trx_dir_reg  <= conf_wdata[1];
                        hlock_reg    <= conf_wdata[0];
                    end
                    `DMA_COUNT_ADDR: begin
                        count_reg <= conf_wdata[15:0];
                        dma_go    <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        dma_start   = dma_go;
        dma_extaddr = extaddr_reg;
        dma_intaddr = intaddr_reg;
        dma_intmod  = intmod_reg;
        dma_count   = count_reg;
        dma_hparams = {3'b0, priority_reg, hsize_reg, hburst_reg, hprot_reg, trx_dir_reg, hlock_reg};
    end

endmodule
