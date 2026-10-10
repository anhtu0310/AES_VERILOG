`timescale 1ns / 1ps

// Iterative AES-128 encryptor: one round per clock, one shared round and
// key-expansion datapath. Latency 10 clocks; a new block can be accepted in
// the clock the previous one finishes, so throughput is one block per 10
// clocks. About a tenth of the area of aes128_pipe.
//
// Handshake: a block is taken when in_valid && in_ready. out_valid pulses
// for one clock with the result on out_block, which then holds until the
// next result.
module aes128_iter (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         in_valid,
    output wire         in_ready,
    input  wire [127:0] in_key,
    input  wire [127:0] in_block,

    output reg          out_valid,
    output reg  [127:0] out_block
);

`include "aes_functions.vh"

    reg         busy;
    reg [3:0]   round;      // round being computed, 1..10
    reg [7:0]   rcon;
    reg [127:0] state, rkey;

    wire         last     = (round == 4'd10);
    wire [127:0] next_key = aes_next_key(rkey, rcon);
    wire [127:0] next_st  = aes_round(state, next_key, last);
    wire [7:0]   next_rc  = aes_xtime(rcon);
    wire         load     = in_valid && in_ready;

    assign in_ready = !busy || last;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy      <= 1'b0;
            round     <= 4'd0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= busy && last;
            if (load) begin
                busy  <= 1'b1;
                round <= 4'd1;
            end else if (busy) begin
                busy  <= !last;
                round <= round + 4'd1;
            end
        end
    end

    always @(posedge clk) begin
        if (load) begin
            state <= in_block ^ in_key;
            rkey  <= in_key;
            rcon  <= 8'h01;
        end else if (busy) begin
            state <= next_st;
            rkey  <= next_key;
            rcon  <= next_rc;
        end
        if (busy && last)
            out_block <= next_st;
    end

endmodule
