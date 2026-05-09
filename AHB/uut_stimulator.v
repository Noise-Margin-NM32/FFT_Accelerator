// *******************************************************************
// AHB system generator - UUT Stimulator (converted from VHDL)
// Original Author: Federico Aglietti, federico.aglietti@opencores.org
// *******************************************************************
// Non-synthesizable testbench stimulus generator for one AHB master.
// Drives DMA configuration registers through a sequence of burst types.

`include "ahb_package.vh"
`timescale 1ns/1ps

module uut_stimulator #(
    // stim_type fields (replaces VHDL uut_params_t record)
    parameter [2:0]  HSIZE_TB         = `BITS32,
    parameter        SPLIT_TB         = `RETRY_MODE,
    parameter        PRIOR_TB         = `MASTER_PRI,
    parameter        HBURST_CYCLE     = 1'b0,  // 1=use fixed HBURST_TB, 0=sweep counter
    parameter [2:0]  HBURST_TB        = `SINGLE,
    parameter integer EXT_ADDR_INCR_TB  = 2,
    parameter integer INTMOD_TB         = 4,
    parameter [3:0]  HPROT_TB         = `HPROT_POSTED,
    parameter integer BASE_TB           = 2048,
    parameter integer INT_ADDR_INCR_TB  = 1,
    parameter integer INT_BASE_TB       = 0,
    parameter        LOCKED_REQUEST   = 1'b0,
    parameter integer ENABLE            = 0,    // 1 = actually trigger DMA count writes
    parameter integer EOT_ENABLE        = 0     // 1 = wait for eot_int between stimuli
)(
    input  wire hclk,
    input  wire hresetn,
    input  wire amba_error,
    input  wire eot_int,
    output reg  conf_write,
    output reg  [3:0]  conf_addr,
    output reg  [31:0] conf_wdata,
    output reg  sim_end
);

    // -----------------------------------------------------------------------
    // Internal
    // -----------------------------------------------------------------------
    integer counter;
    reg     cycle;

    // Error assertion
    always @(amba_error) begin
        if (amba_error)
            $display("###ERROR in AMBA operation!!!");
    end

    // -----------------------------------------------------------------------
    // sim_end / counter process
    // -----------------------------------------------------------------------
    initial begin
        counter  = 1;
        sim_end  = 1'b0;
        conf_write = 1'b0;
        conf_addr  = 4'b0;
        conf_wdata = 32'b0;
        cycle      = 1'b0;

        if (EOT_ENABLE != 1)
            #4000;
        else begin
            @(posedge eot_int or posedge amba_error);
            @(posedge eot_int or posedge amba_error);
        end

        forever begin
            if (counter > 15) begin
                $display("* Simulator Exit..");
                sim_end = 1'b1;
                $finish;
            end else begin
                sim_end  = 1'b0;
                counter  = counter + 1;
            end

            if (EOT_ENABLE != 1)
                #4000;
            else begin
                @(posedge eot_int or posedge amba_error);
                @(posedge eot_int or posedge amba_error);
            end
        end
    end

    // -----------------------------------------------------------------------
    // Cycle toggle
    // -----------------------------------------------------------------------
    initial begin
        cycle = 1'b0;
        forever begin
            if (EOT_ENABLE != 1)
                #2000;
            else
                @(posedge eot_int or posedge amba_error);
            cycle = ~cycle;
        end
    end

    // -----------------------------------------------------------------------
    // Configuration write process
    // -----------------------------------------------------------------------
    initial begin
        @(posedge hresetn);  // wait for reset release
        forever begin
            if (counter <= 16) begin
                reg [2:0] hburst;

                conf_write = 1'b0;
                #30;
                conf_write = 1'b1;

                // --- DMA_TYPE ---
                conf_addr = `DMA_TYPE_ADDR;
                hburst = HBURST_CYCLE ? HBURST_TB : counter[2:0];
                conf_wdata = {14'b0,
                              SPLIT_TB, PRIOR_TB,
                              HSIZE_TB,
                              hburst,
                              HPROT_TB,
                              cycle, LOCKED_REQUEST};
                #10;

                // --- DMA_EXTADD ---
                conf_addr = `DMA_EXTADD_ADDR;
                case (EXT_ADDR_INCR_TB)
                    1: conf_wdata = BASE_TB[31:0];
                    2: conf_wdata = (BASE_TB + (counter-1)*4);
                    default: conf_wdata = (BASE_TB + (counter-1)*(EXT_ADDR_INCR_TB-4));
                endcase
                #10;

                // --- DMA_INTADD ---
                conf_addr = `DMA_INTADD_ADDR;
                case (INT_ADDR_INCR_TB)
                    1: conf_wdata = INT_BASE_TB[31:0];
                    2: conf_wdata = (INT_BASE_TB + (counter-1)*4);
                    default: conf_wdata = (INT_BASE_TB + (counter-1)*(INT_ADDR_INCR_TB-4));
                endcase
                #10;

                // --- DMA_INTMOD ---
                conf_addr  = `DMA_INTMOD_ADDR;
                conf_wdata = INTMOD_TB[31:0];
                #10;

                // --- DMA_COUNT ---
                if (ENABLE == 1) begin
                    conf_addr  = `DMA_COUNT_ADDR;
                    conf_wdata = counter[31:0];
                    #10;
                end else begin
                    #10;
                end

                conf_write = 1'b0;
                conf_addr  = 4'b0;
                conf_wdata = 32'bx;

                if (EOT_ENABLE != 1)
                    @(posedge cycle or negedge cycle); // wait cycle edge
                else
                    @(posedge eot_int or posedge amba_error);
            end else begin
                wait(1'b0); // stop
            end
        end
    end

endmodule
