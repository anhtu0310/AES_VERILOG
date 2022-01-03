module keyScheduler(
    input [127:0]in_key,
    input [3:0] round_cnt,
    output [127:0]round_key);
    reg[127:0] prev_key;
    reg [7:0]rcon ;
    wire [31:0]sbox_out;
    wire [7:0] r0;
 
    aes_sbox sbox(
                .sboxw({prev_key[23:16],prev_key[15:8],prev_key[7:0],prev_key[31:24]}),
                .new_sboxw(sbox_out)
                 );
    assign r0 = rcon ^  prev_key[127:120];  
    assign round_key[127:96] = sbox_out ^ {r0,prev_key[119:96]}; 

    assign round_key [95:64] = round_key[127:96] ^ prev_key [95:64];
    assign round_key [63:32] = round_key[95:64] ^ prev_key [63:32];
    assign round_key [31:0] = round_key[63:32] ^ prev_key [31:0];


    always @(round_cnt) begin
        $monitor("hejooo");
        if(round_cnt)
        begin
            rcon = {rcon[6 : 0], 1'b0} ^ (8'h1b & {8{rcon[7]}});
            prev_key = round_key;
        end
        else
        begin 
            prev_key = in_key;
            rcon = 8'h01;
        end
    end
    

endmodule
// module rcon(
//     input [3:0] round;
//     output [7:0] rcon_out
// );
// always @(round) begin
//     case (round)
//     4'd00: rcon_out = 1'h01;
//     4'd01: rcon_out = 1'h02;
//     4'd02: rcon_out = 1'h01;
//     4'd03: rcon_out = 1'h01;
//     4'd04: rcon_out = 1'h01;
//     4'd05: rcon_out = 1'h01;
//     4'd06: rcon_out = 1'h01;
//     4'd07: rcon_out = 1'h01;
//     4'd08: rcon_out = 1'h01;
//     4'd09: rcon_out = 1'h01;

module keySchedule_tb ();
    reg [127:0] key;
    reg[3:0] cnt;
    wire [127:0] out;
    keyScheduler DUT(.in_key(key),
                    .round_key(out),
                    .round_cnt(cnt) 
                  );
    integer i;
    initial begin
        key = 128'h6162636465666768696a6b6c6d6e6f70;
        for (i=0;i<10;i=i+1)
        begin
            cnt= i ;
            #5;
            key = out;
        end
    end
endmodule