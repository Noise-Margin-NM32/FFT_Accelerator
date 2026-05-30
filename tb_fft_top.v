`timescale 1ns / 1ps

// ================================================================
// tb_fft_top.v  -  Vivado testbench for nm32_fft_top
//
// Flow:
//   1. Load fft_input.txt    -> 512 complex samples
//   2. Load fft_expected.txt -> 512 reference FFT bins
//   3. Write twiddle RAM (256 entries) via tw_we/tw_ext_addr/tw_ext_din
//   4. Write 512 input samples via ext_we/ext_addr/ext_din
//   5. Assert start for one cycle, wait for done
//   6. Read all 512 output bins via ext_addr/ext_dout
//   7. Compare bin-by-bin; display err_re/err_im in waveform
//
// Vivado runtime: set xsim.simulate.runtime to 500000ns
// ================================================================

module tb_fft_top;

    // ----------------------------------------------------------------
    // !! CHANGE THESE PATHS !!
    // ----------------------------------------------------------------
    localparam INPUT_FILE    = "D:/meera/1-TOPS/FFT/fft_input.txt";
    localparam EXPECTED_FILE = "D:/meera/1-TOPS/FFT/fft_expected.txt";
    // ----------------------------------------------------------------

    localparam N           = 512;
    localparam FFT_TIMEOUT = 600000;

    // ----- DUT ports -----
    reg        clk, rst, start;
    reg        ext_we;
    reg  [8:0] ext_addr;
    reg [31:0] ext_din;
    wire[31:0] ext_dout;
    wire       done;

    // Twiddle RAM ports (NEW - must be driven)
    reg        tw_we;
    reg  [7:0] tw_ext_addr;
    reg [31:0] tw_ext_din;
    wire[31:0] tw_ext_dout;

    // ----- Input / expected arrays -----
    reg signed [15:0] in_re  [0:N-1];
    reg signed [15:0] in_im  [0:N-1];
    reg signed [15:0] exp_re [0:N-1];
    reg signed [15:0] exp_im [0:N-1];

    // ----- Readback arrays -----
    reg signed [15:0] out_re [0:N-1];
    reg signed [15:0] out_im [0:N-1];

    // ----- Waveform-visible error signals -----
    reg signed [15:0] err_re;
    reg signed [15:0] err_im;
    reg signed [15:0] max_err_re;
    reg signed [15:0] max_err_im;
    reg [8:0] bin_idx;

    integer i, pass_cnt, fail_cnt, cyc;
    integer abs_err_re, abs_err_im;

    // ----- Instantiate DUT -----
    nm32_fft_top dut (
        .clk        (clk),
        .rst        (rst),
        .start      (start),
        .ext_we     (ext_we),
        .ext_addr   (ext_addr),
        .ext_din    (ext_din),
        .ext_dout   (ext_dout),
        .done       (done),
        // Twiddle RAM ports
        .tw_we      (tw_we),
        .tw_ext_addr(tw_ext_addr),
        .tw_ext_din (tw_ext_din),
        .tw_ext_dout(tw_ext_dout)
    );

    // ----- Clock -----
    initial clk = 0;
    always #5 clk = ~clk;

    // ================================================================
    // Task: load input and expected files
    // ================================================================
    task load_files;
        integer fid, ret, idx;
        reg [15:0] t0, t1;
        begin
            fid = $fopen(INPUT_FILE, "r");
            if (fid == 0) begin $display("ERROR: cannot open %s", INPUT_FILE); $finish; end
            for (idx = 0; idx < N; idx = idx + 1) begin
                ret = $fscanf(fid, "%h %h\n", t0, t1);
                if (ret != 2) begin $display("ERROR: input file parse fail line %0d", idx+1); $finish; end
                in_re[idx] = t0; in_im[idx] = t1;
            end
            $fclose(fid);
            $display("Loaded: %s", INPUT_FILE);

            fid = $fopen(EXPECTED_FILE, "r");
            if (fid == 0) begin $display("ERROR: cannot open %s", EXPECTED_FILE); $finish; end
            for (idx = 0; idx < N; idx = idx + 1) begin
                ret = $fscanf(fid, "%h %h\n", t0, t1);
                if (ret != 2) begin $display("ERROR: expected file parse fail line %0d", idx+1); $finish; end
                exp_re[idx] = t0; exp_im[idx] = t1;
            end
            $fclose(fid);
            $display("Loaded: %s", EXPECTED_FILE);
        end
    endtask

    // ================================================================
    // Task: initialise twiddle RAM
    // W_512^n = cos(2pi*n/512) - j*sin(2pi*n/512), n = 0..255
    // Packed as {wr[31:16], wi[15:0]} matching tw_re/tw_im in DUT.
    // Uses the same floor() formula as the MATLAB gen script.
    // ================================================================
    task init_twiddle_ram;
        integer n;
        real    angle, cr, sr;
        integer wr_int, wi_int;
        reg signed [15:0] wr_q, wi_q;
        begin
            $display("Writing twiddle RAM...");
            tw_we = 1'b0;
            for (n = 0; n < 256; n = n + 1) begin
                angle  = 2.0 * 3.14159265358979323846 * n / 512.0;
                cr     = $cos(angle);
                sr     = $sin(angle);
                // floor() toward -inf, same as Verilog >>> on signed
                wr_int = $rtoi($floor(cr * 32768.0));
                wi_int = $rtoi($floor(-sr * 32768.0));
                // clamp to Q15
                if (wr_int >  32767) wr_int =  32767;
                if (wr_int < -32768) wr_int = -32768;
                if (wi_int >  32767) wi_int =  32767;
                if (wi_int < -32768) wi_int = -32768;
                wr_q = wr_int[15:0];
                wi_q = wi_int[15:0];

                @(negedge clk);
                tw_we       = 1'b1;
                tw_ext_addr = n[7:0];
                tw_ext_din  = {wr_q, wi_q};
            end
            @(negedge clk);
            tw_we = 1'b0;
            repeat(2) @(posedge clk);
            $display("Twiddle RAM written.");
        end
    endtask

    // ================================================================
    // Task: write 512 input samples to data RAM
    // ================================================================
    task write_samples;
        integer idx;
        begin
            $display("Writing input samples...");
            for (idx = 0; idx < N; idx = idx + 1) begin
                @(negedge clk);
                ext_we   = 1'b1;
                ext_addr = idx[8:0];
                ext_din  = {in_re[idx], in_im[idx]};
            end
            @(negedge clk);
            ext_we  = 1'b0;
            ext_din = 32'h0;
            // Wait several cycles so FSM sees ext_we=0 cleanly before start
            repeat(8) @(posedge clk);
            $display("Input samples written.");
        end
    endtask

    // ================================================================
    // Task: read 512 output bins through ext_dout port (realistic path).
    //
    // Read latency through the FSM + RAM is exactly 2 posedges:
    //   Posedge 1: FSM state 0 registers ext_addr -> ram_addr_a
    //   Posedge 2: RAM registers ram_addr_a -> dout_a (= ext_dout)
    //
    // Protocol per bin:
    //   negedge : drive ext_addr = idx  (setup before posedge)
    //   posedge : FSM latches into ram_addr_a
    //   posedge : RAM outputs data onto ext_dout
    //   #1      : sample ext_dout just after posedge (past any glitch)
    //
    // We pipeline by driving addr[n+1] while waiting for addr[n] data.
    // ================================================================
    // ================================================================
    // Safe Synchronous Read Back Task
    // ================================================================
    task read_outputs;
        integer idx;
        begin
            $display("Reading output bins synchronously...");
            ext_we = 1'b0;
            ext_din = 32'h0000_0000;
            
            // Step through all 512 entries one by one
            for (idx = 0; idx < N; idx = idx + 1) begin
                
                // 1. Present the target address on the rising edge
                @(posedge clk);
                ext_addr = idx[8:0];
                
                // 2. Wait exactly one full clock cycle for the RAM to 
                //    latch the address and register its output bus!
                @(posedge clk);
                #1; // Step 1ns past edge to sample rock-solid data
                
                // 3. Extract the stable values safely into your memory array
                out_re[idx] = ext_dout[31:16];
                out_im[idx] = ext_dout[15:0];
            end
            
            $display("Read back completed smoothly.");
        end
    endtask

    // ================================================================
    // Main stimulus
    // ================================================================
    initial begin
        // Init all signals
        rst = 1; start = 0;
        ext_we = 0; ext_addr = 0; ext_din = 0;
        tw_we = 0; tw_ext_addr = 0; tw_ext_din = 0;
        err_re = 0; err_im = 0;
        max_err_re = 0; max_err_im = 0;
        bin_idx = 0;
        pass_cnt = 0; fail_cnt = 0;

        // Reset
        repeat(8) @(posedge clk);
        rst = 0;
        repeat(4) @(posedge clk);

        // Load reference vectors
        load_files();

        // Step 1: write twiddle ROM values into twiddle RAM
        init_twiddle_ram();

        // Step 2: write input samples into data RAM
        write_samples();

        // Step 3: assert start for exactly one cycle
        $display("Asserting start...");
        @(negedge clk);
        start = 1'b1;
        @(posedge clk);  // FSM in state 0 samples start=1 -> goes to state 1
        @(negedge clk);
        start = 1'b0;

        // Step 4: wait for done
        $display("Waiting for FFT to complete...");
        cyc = 0;
        @(posedge clk);
        while (done !== 1'b1 && cyc < FFT_TIMEOUT) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        if (done !== 1'b1) begin
            $display("ERROR: FFT timed out after %0d cycles", FFT_TIMEOUT);
            $finish;
        end
        $display("FFT done after ~%0d cycles (~%0d ns)", cyc, cyc*10);

        // --- FIXED: STRATEGIC BUS CLAIM & HANDSHAKE CUSHION ---
        // The FSM is now transitioning state 6 -> state 0. 
        // We must immediately clamp our external driving lines to a safe,
        // known state so they don't leak uninitialized 'x' into the RAM decoder!
        @(negedge clk);
        ext_we   = 1'b0;
        ext_addr = 9'h000;
        ext_din  = 32'h0000_0000;
        
        // Give the internal RAM blocks 4 clean clock cycles to settle 
        // statically into State 0 mode
        repeat(4) @(posedge clk);
        $display("FFT complete, reading outputs directly from RAM...");

        // Step 5: read outputs
        read_outputs();

        // Step 6: compare
        $display("-------------------------------------------------------------");
        $display(" bin |  got_re   got_im  | exp_re   exp_im  | err_re  err_im");
        $display("-------------------------------------------------------------");

        for (i = 0; i < N; i = i + 1) begin
            bin_idx = i[8:0];
            err_re = $signed(out_re[i]) - $signed(exp_re[i]);
            err_im = $signed(out_im[i]) - $signed(exp_im[i]);

            abs_err_re = err_re[15] ? (~err_re + 1) : err_re;
            abs_err_im = err_im[15] ? (~err_im + 1) : err_im;
            if (abs_err_re > max_err_re) max_err_re = abs_err_re;
            if (abs_err_im > max_err_im) max_err_im = abs_err_im;

            if (abs_err_re <= 2 && abs_err_im <= 2) begin
                pass_cnt = pass_cnt + 1;
                if (i < 4 || i >= N-4)
                    $display(" %3d | %7d  %7d | %7d  %7d | %5d   %5d  PASS",
                             i, $signed(out_re[i]), $signed(out_im[i]),
                             $signed(exp_re[i]),   $signed(exp_im[i]),
                             $signed(err_re),      $signed(err_im));
            end else begin
                fail_cnt = fail_cnt + 1;
                $display(" %3d | %7d  %7d | %7d  %7d | %5d   %5d  FAIL <<<",
                         i, $signed(out_re[i]), $signed(out_im[i]),
                         $signed(exp_re[i]),   $signed(exp_im[i]),
                         $signed(err_re),      $signed(err_im));
            end
        end

        $display("-------------------------------------------------------------");
        $display("RESULT: %0d / %0d bins passed (tolerance +-2 LSB)", pass_cnt, N);
        $display("Max error: re=%0d  im=%0d", $signed(max_err_re), $signed(max_err_im));
        if (fail_cnt == 0)
            $display("*** ALL BINS PASS ***");
        else
            $display("*** %0d BINS FAILED ***", fail_cnt);
        $display("-------------------------------------------------------------");

        #200; $finish;
    end

endmodule