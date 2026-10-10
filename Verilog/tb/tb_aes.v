`timescale 1ns / 1ps

// Self-checking testbench for aes128_iter and aes128_pipe.
//
// Vectors come from text files, one "key plaintext ciphertext" (hex) per
// line. The Makefile passes:
//   +VEC=build/vectors.txt   FIPS-197 / SP 800-38A vectors followed by
//                            random ones from tools/aes_ref.py
//   +VEC2=tb/vectors_legacy.txt  the 100 vectors from the original C++ model
//
// Tests
//   iter  single blocks     each vector alone; latency must be 10 clocks
//   iter  back-to-back      in_valid held high; one block per 10 clocks
//   pipe  streaming         one block per clock; latency 10, N blocks in N+10
//   pipe  bubbles + stalls  random gaps on in_valid and random ce=0 stalls;
//                           results checked in order through in_tag
// Prints "TEST PASSED" or "TEST FAILED" and exits non-zero on failure.
module tb_aes;

    localparam integer MAXV = 4096;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg [127:0] vk [0:MAXV-1];
    reg [127:0] vp [0:MAXV-1];
    reg [127:0] vc [0:MAXV-1];
    integer nvec = 0;

    integer errors = 0;
    integer checks = 0;
    integer seed   = 1;

    task load_vectors(input [1023:0] fname);
        integer fd, n;
        reg [127:0] k, p, c;
        begin
            fd = $fopen(fname, "r");
            if (fd == 0) begin
                $display("TEST FAILED: cannot open %0s", fname);
                $fatal(1);
            end
            n = 3;
            while (n == 3 && nvec < MAXV) begin
                n = $fscanf(fd, "%h %h %h\n", k, p, c);
                if (n == 3) begin
                    vk[nvec] = k; vp[nvec] = p; vc[nvec] = c;
                    nvec = nvec + 1;
                end
            end
            $fclose(fd);
        end
    endtask

    task check(input [8*24-1:0] what, input integer idx, input [127:0] got);
        begin
            checks = checks + 1;
            if (got !== vc[idx]) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("FAIL %0s vector %0d: key=%h pt=%h got %h expected %h",
                             what, idx, vk[idx], vp[idx], got, vc[idx]);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Iterative core
    // ------------------------------------------------------------------
    reg          it_valid = 1'b0;
    reg  [127:0] it_key = 128'd0, it_blk = 128'd0;
    wire         it_ready, it_ovalid;
    wire [127:0] it_out;

    aes128_iter u_iter (
        .clk (clk), .rst_n (rst_n),
        .in_valid (it_valid), .in_ready (it_ready),
        .in_key (it_key), .in_block (it_blk),
        .out_valid (it_ovalid), .out_block (it_out)
    );

    // ------------------------------------------------------------------
    // Pipelined core
    // ------------------------------------------------------------------
    localparam integer TAG_W = 16;
    reg              p_ce = 1'b1, p_valid = 1'b0;
    reg  [127:0]     p_key = 128'd0, p_blk = 128'd0;
    reg  [TAG_W-1:0] p_tag = {TAG_W{1'b0}};
    wire             p_ovalid;
    wire [127:0]     p_out;
    wire [TAG_W-1:0] p_otag;

    aes128_pipe #(.TAG_W (TAG_W)) u_pipe (
        .clk (clk), .rst_n (rst_n), .ce (p_ce),
        .in_valid (p_valid), .in_key (p_key), .in_block (p_blk), .in_tag (p_tag),
        .out_valid (p_ovalid), .out_block (p_out), .out_tag (p_otag)
    );

    // Pipeline scoreboard: results must come back in issue order.
    integer p_expect = 0;
    integer p_recv   = 0;
    always @(posedge clk) begin
        if (rst_n && p_ce && p_ovalid) begin
            checks = checks + 1;
            if (p_otag !== p_expect[TAG_W-1:0]) begin
                errors = errors + 1;
                $display("FAIL pipe order: got tag %0d expected %0d", p_otag, p_expect);
            end
            check("pipe", p_otag, p_out);
            p_expect = p_expect + 1;
            p_recv   = p_recv + 1;
        end
    end

    integer cycle = 0;
    always @(posedge clk) cycle = cycle + 1;

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------
    integer i, t0, lat, sent;
    reg [1023:0] fname;

    initial begin
        if ($test$plusargs("VCD")) begin
            $dumpfile("build/tb_aes.vcd");
            $dumpvars(0, tb_aes);
        end
        void'($value$plusargs("SEED=%d", seed));
        if ($value$plusargs("VEC=%s", fname))  load_vectors(fname);
        if ($value$plusargs("VEC2=%s", fname)) load_vectors(fname);
        if (nvec == 0) begin
            $display("TEST FAILED: no vectors (+VEC=<file>)");
            $fatal(1);
        end
        $display("loaded %0d vectors", nvec);

        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;

        // ---- iterative: one block at a time, measure latency
        $display("--- aes128_iter: single blocks");
        for (i = 0; i < nvec; i = i + 1) begin
            @(negedge clk);
            if (!it_ready) begin
                errors = errors + 1;
                $display("FAIL iter not ready when idle");
            end
            it_valid = 1'b1; it_key = vk[i]; it_blk = vp[i];
            t0 = cycle;
            @(negedge clk) it_valid = 1'b0; it_key = ~vk[i]; it_blk = ~vp[i];  // inputs only sampled on load
            while (!it_ovalid) @(negedge clk);
            lat = cycle - t0 - 1;   // clocks after the edge that took the block
            check("iter", i, it_out);
            if (i == 0) $display("aes128_iter latency: %0d clocks", lat);
            if (lat != 10) begin
                errors = errors + 1;
                $display("FAIL iter latency %0d, expected 10", lat);
            end
        end

        // ---- iterative: back-to-back
        $display("--- aes128_iter: back-to-back");
        sent = 0;
        t0 = cycle;
        fork
            begin
                while (sent < nvec) begin
                    @(negedge clk);
                    it_valid = 1'b1; it_key = vk[sent]; it_blk = vp[sent];
                    @(posedge clk);
                    if (it_ready) sent = sent + 1;
                end
                @(negedge clk) it_valid = 1'b0;
            end
            begin : iter_rx
                integer got;
                got = 0;
                while (got < nvec) begin
                    @(negedge clk);
                    if (it_ovalid) begin
                        check("iter b2b", got, it_out);
                        got = got + 1;
                    end
                end
            end
        join
        $display("aes128_iter: %0d blocks in %0d clocks (%0.2f clocks/block)",
                 nvec, cycle - t0, (cycle - t0) * 1.0 / nvec);
        if (cycle - t0 > nvec * 10 + 12) begin
            errors = errors + 1;
            $display("FAIL iter back-to-back slower than 10 clocks/block");
        end

        // ---- pipeline: full-rate stream
        $display("--- aes128_pipe: streaming, one block per clock");
        @(negedge clk);
        t0 = cycle;
        for (i = 0; i < nvec; i = i + 1) begin
            p_valid = 1'b1; p_key = vk[i]; p_blk = vp[i]; p_tag = i;
            @(negedge clk);
            if (i == 9 && p_recv != 0) begin
                errors = errors + 1;
                $display("FAIL pipe result before 10 clocks");
            end
        end
        p_valid = 1'b0;
        while (p_recv < nvec) @(negedge clk);
        $display("aes128_pipe: %0d blocks in %0d clocks (latency 10, 1 block/clock)",
                 nvec, cycle - t0);
        if (cycle - t0 != nvec + 10) begin
            errors = errors + 1;
            $display("FAIL pipe stream took %0d clocks, expected %0d", cycle - t0, nvec + 10);
        end

        // ---- pipeline: random bubbles and stalls, keys change every block
        $display("--- aes128_pipe: random bubbles and ce stalls");
        p_expect = 0; p_recv = 0;
        i = 0;
        while (i < nvec) begin
            @(negedge clk);
            p_ce = ($random(seed) % 4) != 0;            // ~25 % stall cycles
            if (p_ce && ($random(seed) % 3) != 0) begin  // issue only when not stalled
                p_valid = 1'b1; p_key = vk[i]; p_blk = vp[i]; p_tag = i;
                i = i + 1;
            end else begin
                p_valid = ($random(seed) % 2) == 0;      // ignored while ce = 0 ...
                p_key = {4{$random(seed)}}; p_blk = {4{$random(seed)}};
                if (p_ce) p_valid = 1'b0;                // ... and a real bubble otherwise
            end
        end
        @(negedge clk) p_valid = 1'b0;
        while (p_recv < nvec) begin
            p_ce = ($random(seed) % 4) != 0;
            @(negedge clk);
        end
        p_ce = 1'b1;
        repeat (12) @(negedge clk);
        if (p_recv != nvec) begin
            errors = errors + 1;
            $display("FAIL pipe produced %0d extra results", p_recv - nvec);
        end

        $display("checks: %0d  errors: %0d", checks, errors);
        if (errors == 0)
            $display("TEST PASSED");
        else begin
            $display("TEST FAILED");
            $fatal(1);
        end
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TEST FAILED: timeout");
        $fatal(1);
    end

endmodule
