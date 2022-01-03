module  subBytes_ASMD (
    input [127:0] state_in,
    input clk, rst_n,enable,
    output wire output_ready,
    output wire [127:0] state_out

);
    wire [1:0]local_cnt;
    // wire run;
    subBytes_cu cu(.clk(clk),
                  .rst_n(rst_n),
                  .enable(enable),
                //   .output_ready(output_ready),
                  .local_cnt(local_cnt)
                //   .running_state(run)
                 );
    subBytes_dp dp(  .state_in(state_in),
                    .local_cnt(local_cnt),
                    .output_ready(output_ready),

                    .state_out(state_out)
                    // .en(en)
    );   



endmodule


module subBytes_cu(
    input clk, rst_n, enable,
    // output reg output_ready,
    output reg[1:0] local_cnt
    // output reg running_state

);
    localparam DONE = 1'b0;
	localparam RUNNING = 1'b1;
	always @(posedge clk or negedge rst_n)
    begin
		if (~rst_n || ~enable)
        begin
			local_cnt <= 0; 
     	    // output_ready <= 0;
        end
        else 
            begin 
                // if(local_cnt==3)
                //     // output_ready <= 1;
                // else
                    local_cnt = local_cnt + 1;
            end
	end
endmodule

module subBytes_dp (
    input [1:0]local_cnt,
    // input en,
    output reg output_ready,
    input [127:0] state_in,
    output reg [127:0] state_out

);
    reg [31:0] subByte_LUT_input; 
    wire [31:0] subByte_LUT_output;
    aes_sbox sbox(
                .sboxw(subByte_LUT_input),
                .new_sboxw(subByte_LUT_output)
                 );
    always @(local_cnt or subByte_LUT_output or state_in)//state_in or local_cnt or en )
     begin
        // if (local_cnt)
        case (local_cnt)
                2'b00:
                begin  
                    subByte_LUT_input = state_in[31:0];
                    state_out[31:0]  = subByte_LUT_output;
                     output_ready = 0; 

                end
                2'b01:
                begin 
                    subByte_LUT_input = state_in[63:32] ;
                    state_out[63:32]  = subByte_LUT_output;
     
                end
                2'b10:
                begin 
                    subByte_LUT_input = state_in[95:64] ;
                    state_out[95:64]  = subByte_LUT_output;

                end
                2'b11:
                begin 
                    subByte_LUT_input = state_in [127:96] ;
                    state_out[127:96]  = subByte_LUT_output;
                    output_ready = 1; 
                end
            endcase
        // else 
           
    end
    
endmodule




module aes_sbox(input wire [31 : 0]  sboxw,
                output wire [31 : 0] new_sboxw
               );

  //----------------------------------------------------------------
  // Four parallel, combinational sboxes.
  //----------------------------------------------------------------
  assign new_sboxw[31 : 24] = s(sboxw[31 : 24]);
  assign new_sboxw[23 : 16] = s(sboxw[23 : 16]);
  assign new_sboxw[15 : 08] = s(sboxw[15 : 08]);
  assign new_sboxw[07 : 00] = s(sboxw[07 : 00]);


  //----------------------------------------------------------------
  // Function that implements the S-box using gates.
  //----------------------------------------------------------------
  function [0 : 7] s(input [0 : 7] u);
    begin : cmt_s
      reg [21 : 0] y;
      reg [67 : 0] t;
      reg [17 : 0] z;

      y[14] = u[03]  ^ u[05];
      y[13] = u[00]  ^ u[06];
      y[09] = u[00]  ^ u[03];
      y[08] = u[00]  ^ u[05];
      t[00] = u[01]  ^ u[02];
      y[01] = t[00]  ^ u[07];
      y[04] = y[01]  ^ u[03];
      y[12] = y[13]  ^ y[14];
      y[02] = y[01]  ^ u[00];
      y[05] = y[01]  ^ u[06];
      y[03] = y[05]  ^ y[08];
      t[01] = u[04]  ^ y[12];
      y[15] = t[01]  ^ u[05];
      y[20] = t[01]  ^ u[01];
      y[06] = y[15]  ^ u[07];
      y[10] = y[15]  ^ t[00];
      y[11] = y[20]  ^ y[09];
      y[07] = u[07]  ^ y[11];
      y[17] = y[10]  ^ y[11];
      y[19] = y[10]  ^ y[08];
      y[16] = t[00]  ^ y[11];
      y[21] = y[13]  ^ y[16];
      y[18] = u[00]  ^ y[16];
      t[02] = y[12]  & y[15];
      t[03] = y[03]  & y[06];
      t[04] = t[03]  ^ t[02];
      t[05] = y[04]  & u[07];
      t[06] = t[05]  ^ t[02];
      t[07] = y[13]  & y[16];
      t[08] = y[05]  & y[01];
      t[09] = t[08]  ^ t[07];
      t[10] = y[02]  & y[07];
      t[11] = t[10]  ^ t[07];
      t[12] = y[09]  & y[11];
      t[13] = y[14]  & y[17];
      t[14] = t[13]  ^ t[12];
      t[15] = y[08]  & y[10];
      t[16] = t[15]  ^ t[12];
      t[17] = t[04]  ^ t[14];
      t[18] = t[06]  ^ t[16];
      t[19] = t[09]  ^ t[14];
      t[20] = t[11]  ^ t[16];
      t[21] = t[17]  ^ y[20];
      t[22] = t[18]  ^ y[19];
      t[23] = t[19]  ^ y[21];
      t[24] = t[20]  ^ y[18];
      t[25] = t[21]  ^ t[22];
      t[26] = t[21]  & t[23];
      t[27] = t[24]  ^ t[26];
      t[28] = t[25]  & t[27];
      t[29] = t[28]  ^ t[22];
      t[30] = t[23]  ^ t[24];
      t[31] = t[22]  ^ t[26];
      t[32] = t[31]  & t[30];
      t[33] = t[32]  ^ t[24];
      t[34] = t[23]  ^ t[33];
      t[35] = t[27]  ^ t[33];
      t[36] = t[24]  & t[35];
      t[37] = t[36]  ^ t[34];
      t[38] = t[27]  ^ t[36];
      t[39] = t[29]  & t[38];
      t[40] = t[25]  ^ t[39];
      t[41] = t[40]  ^ t[37];
      t[42] = t[29]  ^ t[33];
      t[43] = t[29]  ^ t[40];
      t[44] = t[33]  ^ t[37];
      t[45] = t[42]  ^ t[41];
      z[00] = t[44]  & y[15];
      z[01] = t[37]  & y[06];
      z[02] = t[33]  & u[07];
      z[03] = t[43]  & y[16];
      z[04] = t[40]  & y[01];
      z[05] = t[29]  & y[07];
      z[06] = t[42]  & y[11];
      z[07] = t[45]  & y[17];
      z[08] = t[41]  & y[10];
      z[09] = t[44]  & y[12];
      z[10] = t[37]  & y[03];
      z[11] = t[33]  & y[04];
      z[12] = t[43]  & y[13];
      z[13] = t[40]  & y[05];
      z[14] = t[29]  & y[02];
      z[15] = t[42]  & y[09];
      z[16] = t[45]  & y[14];
      z[17] = t[41]  & y[08];
      t[46] = z[15]  ^ z[16];
      t[47] = z[10]  ^ z[11];
      t[48] = z[05]  ^ z[13];
      t[49] = z[09]  ^ z[10];
      t[50] = z[02]  ^ z[12];
      t[51] = z[02]  ^ z[05];
      t[52] = z[07]  ^ z[08];
      t[53] = z[00]  ^ z[03];
      t[54] = z[06]  ^ z[07];
      t[55] = z[16]  ^ z[17];
      t[56] = z[12]  ^ t[48];
      t[57] = t[50]  ^ t[53];
      t[58] = z[04]  ^ t[46];
      t[59] = z[03]  ^ t[54];
      t[60] = t[46]  ^ t[57];
      t[61] = z[14]  ^ t[57];
      t[62] = t[52]  ^ t[58];
      t[63] = t[49]  ^ t[58];
      t[64] = z[04]  ^ t[59];
      t[65] = t[61]  ^ t[62];
      t[66] = z[01]  ^ t[63];
      s[00] = t[59]  ^ t[63];
      s[06] = ~t[56] ^ t[62];
      s[07] = ~t[48] ^ t[60];
      t[67] = t[64]  ^ t[65];
      s[03] = t[53]  ^ t[66];
      s[04] = t[51]  ^ t[66];
      s[05] = t[47]  ^ t[65];
      s[01] = ~t[64] ^ s[03];
      s[02] = ~t[55] ^ t[67];
    end
  endfunction // s
endmodule // aes_sbox


module subBytes_tb ();
    reg clk,rst_n;
    reg [127:0] state_in;
    wire [127:0] state_out;
    wire rdy;   
    // reg en;
    subBytes_ASMD DUT (.clk(clk),
                .rst_n(rst_n),
                .state_in(state_in),
                .state_out(state_out),
                .output_ready(rdy)
                // .en(en)
                );

    // column_mul DUT2(.word_in(state_in[31:0]),
    //                 .word_out(state_out[31:0])
    //                 );
    always #5 clk= ~clk;
    initial begin
        rst_n = 0;
                clk = 1;
        // en =1; 
        #5
        state_in = 128'he3a6f7527637727fe5ba097ab02107f3;

        #10
        rst_n = 1;
    end
endmodule
