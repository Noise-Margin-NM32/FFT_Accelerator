// *******************************************************************
// AHB system generator - AHB Master (converted from VHDL)
// Original Author: Federico Aglietti, federico.aglietti@opencores.org
// *******************************************************************
// AHB master with internal FIFO, supporting burst types single/incr/wrap/incr4/8/16,
// 1K page boundary checks, split/retry handling, and locked transfers.

`include "ahb_package.vh"

module ahb_master #(
    parameter FIFOHEMPTY_LEVEL = 2,
    parameter FIFOHFULL_LEVEL  = 6,
    parameter FIFO_LENGTH      = 8,
    parameter FIFO_PTR_WIDTH   = 4  // ceil(log2(FIFO_LENGTH))+1
)(
    // AHB master signals
    input  wire        hresetn,
    input  wire        hclk,
    // Master inputs from arbiter
    input  wire        hgrant,
    input  wire        hready,
    input  wire [1:0]  hresp,
    input  wire [31:0] hrdata,
    // Master outputs to arbiter
    output wire        hbusreq,
    output wire        hlock,
    output wire [1:0]  htrans,
    output wire [31:0] haddr,
    output wire        hwrite,
    output wire [2:0]  hsize,
    output wire [2:0]  hburst,
    output wire [3:0]  hprot,
    output wire [31:0] hwdata,
    // DMA start configuration
    input  wire        dma_start,
    input  wire [31:0] dma_extaddr,
    input  wire [15:0] dma_intaddr,
    input  wire [15:0] dma_intmod,
    input  wire [15:0] dma_count_in,
    input  wire [15:0] dma_hparams,
    // Wrapper interface
    output wire [31:0] m_wrap_addr,
    output wire        m_wrap_take,
    output wire [31:0] m_wrap_wdata,
    output wire        m_wrap_ask,
    input  wire        m_wrap_take_ok,
    input  wire        m_wrap_ask_ok,
    input  wire [31:0] m_wrap_rdata,
    // Control signals
    input  wire        slv_running,
    output wire        mst_running,
    output wire        eot_int
);

    // -----------------------------------------------------------------------
    // Parameter decode from hparams
    // -----------------------------------------------------------------------
    wire start_hlocked = dma_hparams[0];
    wire start_hwrite  = dma_hparams[1];
    wire [3:0] start_hprot  = dma_hparams[5:2];
    wire [2:0] start_hburst = dma_hparams[8:6];
    wire [2:0] start_hsize  = dma_hparams[11:9];
    wire start_prior = dma_hparams[12];

    // -----------------------------------------------------------------------
    // Master FSM encoding
    // -----------------------------------------------------------------------
    localparam IDLE_PHASE  = 4'd0;
    localparam WAIT_PHASE  = 4'd1;
    localparam REQ_PHASE   = 4'd2;
    localparam ADDR        = 4'd3;
    localparam ADDR_DATA   = 4'd4;
    localparam DATA        = 4'd5;
    localparam RETRY_PHASE = 4'd6;
    localparam ERROR_PHASE = 4'd7;
    localparam BE_PHASE    = 4'd8;

    reg [3:0] mst_state, s_mst_state;

    // -----------------------------------------------------------------------
    // Registered master outputs
    // -----------------------------------------------------------------------
    reg [31:0] r_haddr;
    reg [1:0]  r_htrans;
    reg        r_hlock;
    reg        r_hwrite;
    reg [2:0]  r_hsize;
    reg [2:0]  r_hburst;
    reg [3:0]  r_hprot;

    reg [31:0] s_haddr;
    reg [1:0]  s_htrans_r;
    reg        s_hlock;
    reg        s_hwrite;
    reg [2:0]  s_hsize;
    reg [2:0]  s_hburst;
    reg [3:0]  s_hprot;

    // -----------------------------------------------------------------------
    // FIFO interface
    // -----------------------------------------------------------------------
    wire [FIFO_PTR_WIDTH-1:0] fifo_count_w;
    wire fifo_full_w, fifo_hfull_w, fifo_empty_w, fifo_hempty_w;
    reg  fifo_write_r, fifo_read_r, fifo_reset_r;
    wire fifo_write_w, fifo_read_w;
    reg  [31:0] fifo_datain_r;
    wire [31:0] fifo_dataout_w;

    // Auxiliary fifo signals (mst side AHB)
    wire fifo_hwrite_w;
    wire fifo_hread_w;

    fifo #(
        .FIFOHEMPTY_LEVEL(FIFOHEMPTY_LEVEL),
        .FIFOHFULL_LEVEL (FIFOHFULL_LEVEL),
        .FIFO_LENGTH     (FIFO_LENGTH),
        .PTR_WIDTH       (FIFO_PTR_WIDTH)
    ) fifo_inst (
        .hresetn     (hresetn),
        .clk         (hclk),
        .fifo_reset  (fifo_reset_r),
        .fifo_write  (fifo_write_w),
        .fifo_read   (fifo_read_w),
        .fifo_count  (fifo_count_w),
        .fifo_full   (fifo_full_w),
        .fifo_hfull  (fifo_hfull_w),
        .fifo_empty  (fifo_empty_w),
        .fifo_hempty (fifo_hempty_w),
        .fifo_datain (fifo_datain_r),
        .fifo_dataout(fifo_dataout_w)
    );

    // -----------------------------------------------------------------------
    // DMA count, old burst, priority registers
    // -----------------------------------------------------------------------
    reg [15:0] dma_count, dma_count_s;
    reg [15:0] right_count;
    reg [2:0]  old_hburst, old_hburst_s;
    reg        prior_reg, prior_s;

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            old_hburst <= `INCR;
            prior_reg  <= `SLAVE_PRI;
        end else begin
            old_hburst <= old_hburst_s;
            prior_reg  <= prior_s;
        end
    end

    always @(*) begin
        old_hburst_s = dma_start ? start_hburst : old_hburst;
        prior_s      = dma_start ? start_prior   : prior_reg;
    end

    // -----------------------------------------------------------------------
    // granted register
    // -----------------------------------------------------------------------
    reg granted;
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn)
            granted <= 1'b0;
        else
            granted <= (hready && hgrant);
    end

    // -----------------------------------------------------------------------
    // Page fault logic
    // -----------------------------------------------------------------------
    wire [7:0] haddr_t_8; // bits [9:2] of next addr
    wire page_attention;
    wire old_page_attention;
    wire pf_incr, pf_wrap4, pf_wrap8, pf_wrap16;
    wire page_fault;
    wire haddr_incr;

    assign page_attention = (r_hburst == `INCR  || r_hburst == `INCR4 ||
                             r_hburst == `INCR8  || r_hburst == `INCR16);
    assign old_page_attention = (old_hburst == `INCR  || old_hburst == `INCR4 ||
                                 old_hburst == `INCR8  || old_hburst == `INCR16);

    // Compute next address bits [9:2] based on hburst
    reg [7:0] haddr_t_mux;
    always @(*) begin
        case (r_hburst)
            `INCR, `INCR4, `INCR8, `INCR16:
                haddr_t_mux = r_haddr[9:2] + 8'd1;
            `WRAP4:
                haddr_t_mux = {r_haddr[9:4], r_haddr[3:2] + 2'd1};
            `WRAP8:
                haddr_t_mux = {r_haddr[9:5], r_haddr[4:2] + 3'd1};
            `WRAP16:
                haddr_t_mux = {r_haddr[9:6], r_haddr[5:2] + 4'd1};
            default:
                haddr_t_mux = r_haddr[9:2];
        endcase
    end

    assign pf_incr  = (haddr_t_mux == 8'b0);
    assign pf_wrap4 = (haddr_t_mux[1:0] == 2'b0) && (old_hburst == `WRAP4);
    assign pf_wrap8 = (haddr_t_mux[2:0] == 3'b0) && (old_hburst == `WRAP8);
    assign pf_wrap16= (haddr_t_mux[3:0] == 4'b0) && (old_hburst == `WRAP16);
    assign page_fault = page_attention && (pf_incr || pf_wrap4 || pf_wrap8 || pf_wrap16);

    assign haddr_incr = hready &&
        (s_htrans_combined == `NONSEQ || s_htrans_combined == `SEQ ||
         s_htrans_combined == `BUSY) && (r_htrans != `BUSY);

    // -----------------------------------------------------------------------
    // old_addr – used for retry address restore
    // -----------------------------------------------------------------------
    reg [31:0] old_addr;
    wire old_addr_incr;
    assign old_addr_incr = ((mst_state == ADDR || mst_state == ADDR_DATA || mst_state == DATA)
                            && hready && s_htrans_combined != `BUSY && r_htrans != `BUSY);

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn)
            old_addr <= 32'b0;
        else begin
            if (old_addr_incr)
                old_addr <= r_haddr;
            else if (dma_start)
                old_addr <= dma_extaddr;
        end
    end

    // -----------------------------------------------------------------------
    // Next-state address computation s_haddr
    // -----------------------------------------------------------------------
    always @(*) begin
        // Default: hold
        s_haddr = r_haddr;
        if (dma_start) begin
            s_haddr = dma_extaddr;
        end else if (mst_state == RETRY_PHASE || mst_state == IDLE_PHASE) begin
            s_haddr = old_addr;
        end else if (haddr_incr) begin
            // High bits (31:10)
            if (page_attention && old_page_attention && pf_incr)
                s_haddr[31:10] = r_haddr[31:10] + 22'd1;
            else
                s_haddr[31:10] = r_haddr[31:10];
            // Low bits [1:0] unchanged
            s_haddr[1:0] = r_haddr[1:0];
            // Bits [9:2]
            if (page_fault && pf_wrap4)
                s_haddr[9:2] = {r_haddr[9:4], 2'b00};
            else if (page_fault && pf_wrap8)
                s_haddr[9:2] = {r_haddr[9:5], 3'b000};
            else if (page_fault && pf_wrap16)
                s_haddr[9:2] = {r_haddr[9:6], 4'b0000};
            else
                s_haddr[9:2] = haddr_t_mux;
        end
    end

    // -----------------------------------------------------------------------
    // htrans combinational
    // -----------------------------------------------------------------------
    wire [1:0] s_htrans_combined;
    assign s_htrans_combined =
        ((mst_state == ADDR_DATA) &&
         ((dma_count >= 16'd2 && ((fifo_count_w <= 1 && r_hwrite) ||
                                  (fifo_count_w >= FIFO_LENGTH-1 && !r_hwrite))) ||
          (dma_count == 16'd1 && ((fifo_count_w <= 1 && r_hwrite) ||
                                  (fifo_count_w == FIFO_LENGTH && !r_hwrite))))) ? `BUSY  :
        (mst_state == ADDR)      ? `NONSEQ :
        (mst_state == ADDR_DATA) ? `SEQ    : `IDLE;

    // -----------------------------------------------------------------------
    // hbusreq
    // -----------------------------------------------------------------------
    wire hbusreq_t;
    assign hbusreq_t = ((dma_count > 0) && (mst_state == REQ_PHASE)) ||
                       ((dma_count > 1) && (mst_state == ADDR || mst_state == ADDR_DATA));

    wire mst_req_w = (!r_hwrite) || (!fifo_empty_w);

    // hlock
    wire hlock_t = hbusreq_t && r_hlock;

    // -----------------------------------------------------------------------
    // Master FSM next-state
    // -----------------------------------------------------------------------
    always @(*) begin
        s_mst_state = mst_state;
        case (mst_state)
            IDLE_PHASE: begin
                if (dma_count > 0 && (!slv_running || prior_reg == `MASTER_PRI))
                    s_mst_state = WAIT_PHASE;
            end
            WAIT_PHASE: begin
                if (mst_req_w)
                    s_mst_state = REQ_PHASE;
            end
            REQ_PHASE: begin
                if (hbusreq_t && hgrant && hready)
                    s_mst_state = ADDR;
            end
            ADDR: begin
                if (hready) begin
                    if (page_fault || !hgrant || dma_count == 16'd1)
                        s_mst_state = DATA;
                    else
                        s_mst_state = ADDR_DATA;
                end
            end
            ADDR_DATA: begin
                if (hready) begin
                    if (hresp == `OK_RESP) begin
                        if (r_htrans != `BUSY) begin
                            if (dma_count == 16'd1)
                                s_mst_state = DATA;
                            else if (page_fault || !hgrant)
                                s_mst_state = DATA;
                        end else begin
                            if (!hgrant)
                                s_mst_state = DATA;
                        end
                    end
                end else begin
                    case (hresp)
                        `RETRY_RESP, `SPLIT_RESP: s_mst_state = RETRY_PHASE;
                        `ERROR_RESP:              s_mst_state = ERROR_PHASE;
                        default:                  s_mst_state = ADDR_DATA;
                    endcase
                end
            end
            DATA: begin
                if (hready) begin
                    if (hresp == `OK_RESP && r_htrans != `BUSY) begin
                        if (r_hwrite)
                            s_mst_state = IDLE_PHASE;
                        else
                            s_mst_state = BE_PHASE;
                    end
                end else begin
                    case (hresp)
                        `RETRY_RESP, `SPLIT_RESP: s_mst_state = RETRY_PHASE;
                        `ERROR_RESP:              s_mst_state = ERROR_PHASE;
                        default:                  s_mst_state = DATA;
                    endcase
                end
            end
            RETRY_PHASE: begin
                if (hready) s_mst_state = IDLE_PHASE;
            end
            ERROR_PHASE: begin
                if (hready) s_mst_state = IDLE_PHASE;
            end
            BE_PHASE: begin
                if (fifo_empty_w) s_mst_state = IDLE_PHASE;
            end
            default: s_mst_state = IDLE_PHASE;
        endcase
    end

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn)
            mst_state <= IDLE_PHASE;
        else
            mst_state <= s_mst_state;
    end

    // -----------------------------------------------------------------------
    // Registered output pipeline
    // -----------------------------------------------------------------------
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            r_haddr  <= 32'b0;
            r_htrans <= `IDLE;
            r_hlock  <= 1'b0;
            r_hwrite <= 1'b0;
            r_hsize  <= `BITS32;
            r_hburst <= `INCR;
            r_hprot  <= 4'b0011;
        end else begin
            r_haddr  <= s_haddr;
            r_htrans <= s_htrans_combined;
            r_hlock  <= s_hlock;
            r_hwrite <= s_hwrite;
            r_hsize  <= s_hsize;
            r_hburst <= s_hburst;
            r_hprot  <= s_hprot;
        end
    end

    always @(*) begin
        s_hlock  = dma_start ? start_hlocked : r_hlock;
        s_hwrite = dma_start ? start_hwrite  : r_hwrite;
        s_hsize  = dma_start ? start_hsize   : r_hsize;
        s_hprot  = dma_start ? start_hprot   : r_hprot;
        if (dma_start)
            s_hburst = start_hburst;
        else if (mst_state == RETRY_PHASE || mst_state == DATA)
            s_hburst = `INCR; // dma_restart
        else
            s_hburst = r_hburst;
    end

    // -----------------------------------------------------------------------
    // DMA count
    // -----------------------------------------------------------------------
    always @(*) begin
        case (start_hburst)
            `SINGLE:             right_count = 16'd1;
            `INCR:               right_count = dma_count_in;
            `WRAP4, `INCR4:      right_count = 16'd4;
            `WRAP8, `INCR8:      right_count = 16'd8;
            default:             right_count = 16'd16; // WRAP16/INCR16
        endcase
    end

    always @(*) begin
        if (fifo_reset_r)
            dma_count_s = 16'b0;
        else if ((mst_state == ADDR || mst_state == ADDR_DATA) && haddr_incr)
            dma_count_s = dma_count - 16'd1;
        else if (mst_state == RETRY_PHASE && hready)
            dma_count_s = dma_count + 16'd1;
        else if (dma_start)
            dma_count_s = right_count;
        else
            dma_count_s = dma_count;
    end

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn)
            dma_count <= 16'b0;
        else
            dma_count <= dma_count_s;
    end

    // fifo_reset
    always @(*) begin
        fifo_reset_r = (mst_state == ERROR_PHASE) ||
            (hresp == `OK_RESP && r_htrans != `BUSY && r_hwrite && hready &&
             mst_state == DATA && dma_count == 16'b0);
    end

    // -----------------------------------------------------------------------
    // FIFO data path
    // -----------------------------------------------------------------------
    // AHB-side transfers
    assign fifo_hwrite_w = (!r_hwrite) && data_trx && (!fifo_full_w);
    assign fifo_hread_w  = r_hwrite   && data_trx && (!fifo_empty_w);

    wire data_trx = hready && (hresp == `OK_RESP) && (r_htrans != `BUSY) &&
                    (mst_state == ADDR_DATA || mst_state == DATA);

    assign fifo_write_w = fifo_hwrite_w || m_wrap_ask_ok;
    assign fifo_read_w  = fifo_hread_w  || m_wrap_take_ok;

    always @(*) begin
        fifo_datain_r = fifo_hwrite_w ? hrdata : m_wrap_rdata;
    end

    // -----------------------------------------------------------------------
    // Wrapper interface
    // -----------------------------------------------------------------------
    assign m_wrap_wdata = fifo_dataout_w;
    assign m_wrap_take  = (!r_hwrite) && (!fifo_empty_w);
    assign m_wrap_ask   = r_hwrite && (!fifo_full_w) &&
                          (mst_running_w || (dma_count != 16'b0));

    // Internal address for wrapper
    reg [31:0] int_addr;
    reg [15:0] int_mod;
    wire int_addr_incr = (!r_hwrite && m_wrap_take_ok) || (r_hwrite && m_wrap_ask_ok);
    wire int_page_fault = (int_addr[9:2] == 8'b0) && page_attention;

    reg [7:0] int_addr_t8;
    always @(*) begin
        case (r_hburst)
            `INCR, `INCR4, `INCR8, `INCR16:
                int_addr_t8 = int_addr[9:2] + int_mod[9:2];
            `WRAP4:
                int_addr_t8 = {int_addr[9:4], int_addr[3:2] + 2'd1};
            `WRAP8:
                int_addr_t8 = {int_addr[9:5], int_addr[4:2] + 3'd1};
            `WRAP16:
                int_addr_t8 = {int_addr[9:6], int_addr[5:2] + 4'd1};
            default:
                int_addr_t8 = int_addr[9:2];
        endcase
    end

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            int_addr <= 32'b0;
            int_mod  <= 16'b0;
        end else begin
            int_mod <= dma_start ? dma_intmod : int_mod;
            if (dma_start) begin
                int_addr <= {16'b0, dma_intaddr};
            end else begin
                int_addr[31:16] <= 16'b0;
                int_addr[1:0]   <= int_addr[1:0];
                if (int_addr_incr) begin
                    int_addr[15:10] <= (int_page_fault) ? int_addr[15:10] + 6'd1 : int_addr[15:10];
                    int_addr[9:2]   <= int_addr_t8;
                end else begin
                    int_addr[15:10] <= int_addr[15:10];
                    int_addr[9:2]   <= int_addr[9:2];
                end
            end
        end
    end

    assign m_wrap_addr = int_addr;

    // -----------------------------------------------------------------------
    // mst_running, eot_int
    // -----------------------------------------------------------------------
    wire mst_running_w = !(mst_state == IDLE_PHASE || mst_state == WAIT_PHASE ||
                           mst_state == REQ_PHASE);
    assign mst_running = mst_running_w;

    reg eot_int_reg;
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn)
            eot_int_reg <= 1'b0;
        else begin
            if (mst_state == IDLE_PHASE)
                eot_int_reg <= 1'b0;
            else if (s_mst_state == IDLE_PHASE && mst_running_w && dma_count_s == 16'b0)
                eot_int_reg <= 1'b1;
        end
    end
    assign eot_int = eot_int_reg;

    // -----------------------------------------------------------------------
    // AHB output assignments
    // -----------------------------------------------------------------------
    assign hbusreq = hbusreq_t;
    assign hlock   = hlock_t;
    assign htrans  = s_htrans_combined;
    assign haddr   = r_haddr;
    assign hwrite  = r_hwrite;
    assign hsize   = r_hsize;
    assign hburst  = r_hburst;
    assign hprot   = r_hprot;
    assign hwdata  = fifo_dataout_w;

endmodule
