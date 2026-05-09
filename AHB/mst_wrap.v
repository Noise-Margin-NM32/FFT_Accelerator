// *******************************************************************
// AHB system generator - Master Wrapper (converted from VHDL)
// Original Author: Federico Aglietti, federico.aglietti@opencores.org
// *******************************************************************
// Acts as the internal memory/core that the AHB master reads from or
// writes to.  Supports programmable read/write latency and burst mode.

`include "ahb_package.vh"

module mst_wrap #(
    parameter AHB_MAX_ADDR     = 4,
    parameter M_CONST_LAT_WRITE = 0,
    parameter M_CONST_LAT_READ  = 2,
    parameter M_WRITE_BURST     = `BURST_SUPPORT,
    parameter M_READ_BURST      = `BURST_SUPPORT
)(
    input  wire        hresetn,
    input  wire        clk,

    // Configuration bus
    input  wire        conf_write,
    input  wire [3:0]  conf_addr,
    input  wire [31:0] conf_wdata,

    // DMA start signals to master
    output reg         dma_start,
    output reg [31:0]  dma_extaddr,
    output reg [15:0]  dma_intaddr,
    output reg [15:0]  dma_intmod,
    output reg [15:0]  dma_count,
    output reg [15:0]  dma_hparams,

    // Handshake with master (wrap_out = what master sends us)
    input  wire [31:0] m_wrap_addr,
    input  wire        m_wrap_take,
    input  wire [31:0] m_wrap_wdata,
    input  wire        m_wrap_ask,

    // Handshake response back to master
    output wire        m_wrap_take_ok,
    output wire        m_wrap_ask_ok,
    output wire [31:0] m_wrap_rdata
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
            if (m_wrap_take && m_lat_write_ok)
                mem[m_wrap_addr[AHB_MAX_ADDR+1:2]] <= m_wrap_wdata;
        end
    end

    // -----------------------------------------------------------------------
    // Write latency counter
    // -----------------------------------------------------------------------
    reg [$clog2(M_CONST_LAT_WRITE+1)-1:0] m_lat_write;
    wire m_lat_write_ok = (m_lat_write == 0);

    always @(posedge clk or negedge hresetn) begin
        if (!hresetn) begin
            m_lat_write <= M_CONST_LAT_WRITE[$clog2(M_CONST_LAT_WRITE+1)-1:0];
        end else begin
            if (m_wrap_take) begin
                if (!m_lat_write_ok)
                    m_lat_write <= m_lat_write - 1;
                else if (M_WRITE_BURST == 1)
                    m_lat_write <= 0;
                else
                    m_lat_write <= M_CONST_LAT_WRITE[$clog2(M_CONST_LAT_WRITE+1)-1:0];
            end else begin
                m_lat_write <= M_CONST_LAT_WRITE[$clog2(M_CONST_LAT_WRITE+1)-1:0];
            end
        end
    end

    assign m_wrap_take_ok = m_wrap_take && m_lat_write_ok;

    // -----------------------------------------------------------------------
    // Read latency counter
    // -----------------------------------------------------------------------
    reg [$clog2(M_CONST_LAT_READ+1)-1:0] m_lat_read;
    wire m_lat_read_ok = (m_lat_read == 0);

    always @(posedge clk or negedge hresetn) begin
        if (!hresetn) begin
            m_lat_read <= M_CONST_LAT_READ[$clog2(M_CONST_LAT_READ+1)-1:0];
        end else begin
            if (m_wrap_ask) begin
                if (!m_lat_read_ok)
                    m_lat_read <= m_lat_read - 1;
                else if (M_READ_BURST == 1)
                    m_lat_read <= 0;
                else
                    m_lat_read <= M_CONST_LAT_READ[$clog2(M_CONST_LAT_READ+1)-1:0];
            end else begin
                m_lat_read <= M_CONST_LAT_READ[$clog2(M_CONST_LAT_READ+1)-1:0];
            end
        end
    end

    assign m_wrap_ask_ok = m_wrap_ask && m_lat_read_ok;
    assign m_wrap_rdata  = (m_wrap_ask && m_lat_read_ok) ?
                           mem[m_wrap_addr[AHB_MAX_ADDR+1:2]] : 32'bx;

    // -----------------------------------------------------------------------
    // Configuration registers
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

    // -----------------------------------------------------------------------
    // DMA start outputs
    // -----------------------------------------------------------------------
    always @(*) begin
        dma_start   = dma_go;
        dma_extaddr = extaddr_reg;
        dma_intaddr = intaddr_reg;
        dma_intmod  = intmod_reg;
        dma_count   = count_reg;
        dma_hparams = {3'b0, priority_reg, hsize_reg, hburst_reg, hprot_reg, trx_dir_reg, hlock_reg};
    end

endmodule
