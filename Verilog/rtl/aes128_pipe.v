`timescale 1ns / 1ps

// Fully pipelined AES-128 encryptor: one block per clock, latency 10 clocks.
//
// The ten rounds are unrolled into ten register stages. Each stage also
// expands its own round key from the previous stage's key, so the key
// travels down the pipeline with its block: every block may use a different
// key and changing the key never disturbs blocks already in flight.
//
//   stage 1:   s1 = Round(in_block ^ in_key, K1),  K1 = NextKey(in_key, 01)
//   stage r:   sr = Round(s(r-1), Kr),             Kr = NextKey(K(r-1), Rcon r)
//   stage 10:  final round (no MixColumns), registered on out_block
//
// in_tag is carried alongside each block (e.g. a sequence number or
// destination id) and comes out on out_tag with the result.
//
// ce is a global clock enable: while low the whole pipeline holds, so a
// consumer that cannot take a result can stall it. Tie it high otherwise.
// Data registers have no reset (cheaper on FPGAs); only the valid bits do.
module aes128_pipe #(
    parameter integer TAG_W = 1
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             ce,

    input  wire             in_valid,
    input  wire [127:0]     in_key,
    input  wire [127:0]     in_block,
    input  wire [TAG_W-1:0] in_tag,

    output wire             out_valid,
    output wire [127:0]     out_block,
    output wire [TAG_W-1:0] out_tag
);

`include "aes_functions.vh"

    localparam integer LATENCY = 10;

    reg [127:0]     st  [1:LATENCY];
    reg [127:0]     key [1:LATENCY-1];    // stage 10 needs no key forward
    reg [TAG_W-1:0] tag [1:LATENCY];
    reg [LATENCY:1] vld;

    // Stage 1 takes the inputs and does AddRoundKey(K0) up front.
    wire [127:0] k1  = aes_next_key(in_key, aes_rcon(4'd1));
    wire [127:0] s1  = aes_round(in_block ^ in_key, k1, 1'b0);

    always @(posedge clk) begin
        if (ce) begin
            st[1]  <= s1;
            key[1] <= k1;
            tag[1] <= in_tag;
        end
    end

    genvar r;
    generate
        for (r = 2; r <= LATENCY; r = r + 1) begin : g_stage
            wire [127:0] kr = aes_next_key(key[r-1], aes_rcon(r[3:0]));
            wire [127:0] sr = aes_round(st[r-1], kr, r == LATENCY);
            always @(posedge clk) begin
                if (ce) begin
                    st[r]  <= sr;
                    tag[r] <= tag[r-1];
                end
            end
            if (r < LATENCY) begin : g_key
                always @(posedge clk)
                    if (ce)
                        key[r] <= kr;
            end
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            vld <= {LATENCY{1'b0}};
        else if (ce)
            vld <= {vld[LATENCY-1:1], in_valid};
    end

    assign out_valid = vld[LATENCY];
    assign out_block = st[LATENCY];
    assign out_tag   = tag[LATENCY];

endmodule
