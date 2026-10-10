// AES-128 building blocks as constant-time combinational functions.
// `include this file inside a module body.
//
// State layout (FIPS-197 section 3.4): a 128-bit vector holds input bytes
// in0..in15 with in0 in bits [127:120]. Byte n is row n % 4 of column n / 4,
// so column c is the 32-bit word [127-32c -: 32] with row 0 in its top byte.
// Round keys use the same layout (w[4r] in the top word).

`include "aes_sbox.vh"

// Multiply by x (i.e. {02}) in GF(2^8) modulo x^8 + x^4 + x^3 + x + 1.
function [7:0] aes_xtime;
    input [7:0] b;
    begin
        aes_xtime = {b[6:0], 1'b0} ^ (8'h1b & {8{b[7]}});
    end
endfunction

function [31:0] aes_sub_word;
    input [31:0] w;
    begin
        aes_sub_word = {aes_sbox(w[31:24]), aes_sbox(w[23:16]),
                        aes_sbox(w[15:8]),  aes_sbox(w[7:0])};
    end
endfunction

function [127:0] aes_sub_bytes;
    input [127:0] s;
    begin
        aes_sub_bytes = {aes_sub_word(s[127:96]), aes_sub_word(s[95:64]),
                         aes_sub_word(s[63:32]),  aes_sub_word(s[31:0])};
    end
endfunction

// Row r is rotated left by r columns.
function [127:0] aes_shift_rows;
    input [127:0] s;
    reg [31:0] c0, c1, c2, c3;
    begin
        c0 = s[127:96]; c1 = s[95:64]; c2 = s[63:32]; c3 = s[31:0];
        aes_shift_rows = {c0[31:24], c1[23:16], c2[15:8], c3[7:0],
                          c1[31:24], c2[23:16], c3[15:8], c0[7:0],
                          c2[31:24], c3[23:16], c0[15:8], c1[7:0],
                          c3[31:24], c0[23:16], c1[15:8], c2[7:0]};
    end
endfunction

// One column times the MixColumns matrix [2 3 1 1; 1 2 3 1; 1 1 2 3; 3 1 1 2],
// written as b_i = a_i ^ t ^ xtime(a_i ^ a_(i+1)) with t = a0^a1^a2^a3.
function [31:0] aes_mix_column;
    input [31:0] c;
    reg [7:0] a0, a1, a2, a3, t;
    begin
        a0 = c[31:24]; a1 = c[23:16]; a2 = c[15:8]; a3 = c[7:0];
        t  = a0 ^ a1 ^ a2 ^ a3;
        aes_mix_column = {a0 ^ t ^ aes_xtime(a0 ^ a1),
                          a1 ^ t ^ aes_xtime(a1 ^ a2),
                          a2 ^ t ^ aes_xtime(a2 ^ a3),
                          a3 ^ t ^ aes_xtime(a3 ^ a0)};
    end
endfunction

function [127:0] aes_mix_columns;
    input [127:0] s;
    begin
        aes_mix_columns = {aes_mix_column(s[127:96]), aes_mix_column(s[95:64]),
                           aes_mix_column(s[63:32]),  aes_mix_column(s[31:0])};
    end
endfunction

// Next round key from the previous one (FIPS-197 section 5.2):
// w[i] = w[i-4] ^ SubWord(RotWord(w[i-1])) ^ Rcon for the first word,
// w[i] = w[i-4] ^ w[i-1] for the other three.
function [127:0] aes_next_key;
    input [127:0] k;
    input [7:0]   rcon;
    reg [31:0] w0, w1, w2, w3;
    begin
        w0 = k[127:96] ^ aes_sub_word({k[23:0], k[31:24]}) ^ {rcon, 24'd0};
        w1 = k[95:64] ^ w0;
        w2 = k[63:32] ^ w1;
        w3 = k[31:0]  ^ w2;
        aes_next_key = {w0, w1, w2, w3};
    end
endfunction

// Rcon for round 1..10 (round 0 has none).
function [7:0] aes_rcon;
    input [3:0] round;
    begin
        case (round)
            4'd1:    aes_rcon = 8'h01;
            4'd2:    aes_rcon = 8'h02;
            4'd3:    aes_rcon = 8'h04;
            4'd4:    aes_rcon = 8'h08;
            4'd5:    aes_rcon = 8'h10;
            4'd6:    aes_rcon = 8'h20;
            4'd7:    aes_rcon = 8'h40;
            4'd8:    aes_rcon = 8'h80;
            4'd9:    aes_rcon = 8'h1b;
            4'd10:   aes_rcon = 8'h36;
            default: aes_rcon = 8'h00;
        endcase
    end
endfunction

// One cipher round: SubBytes, ShiftRows, MixColumns (skipped in the final
// round), AddRoundKey.
function [127:0] aes_round;
    input [127:0] s;
    input [127:0] round_key;
    input         final_round;
    reg   [127:0] sr;
    begin
        sr = aes_shift_rows(aes_sub_bytes(s));
        aes_round = (final_round ? sr : aes_mix_columns(sr)) ^ round_key;
    end
endfunction
