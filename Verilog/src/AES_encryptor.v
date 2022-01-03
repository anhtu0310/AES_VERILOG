// ‘timescale 1 ns / 100 ps
module AES_encrptor (
    input clk, rst_n,start,
    input [127:0] plain_text, key,
    output reg done,
    output reg [127:0] cipher_text
);
    reg [127:0] state;
    reg sub_byte_en,mix_col_en;
    // wire [3:0]rcnt;
    reg [3:0]round_cnt;
    wire sub_byte_ready,mix_col_ready; 
    wire [127:0]state_SB,state_SR,state_MC,round_key;
    wire [127:0]round_state_out;
    reg get_key;

    // assign rcnt = round_cnt;
    subBytes_ASMD sb (.clk(clk),
                .enable(sub_byte_en),
                .state_in(state),
                .state_out(state_SB),
                .output_ready(sub_byte_ready)
                );

    shiftRows sr(.state_in(state_SB),
                  .state_out(state_SR)
                  );

    mixCols_ASMD   mx(.clk(clk),
                .enable(mix_col_en),
                .state_in(state_SR),
                .state_out(state_MC),
                .round_cnt(round_cnt),
                .output_ready(mix_col_ready)
                );

    keyScheduler ks(.in_key(key),
                    .round_key(round_key),
                    .round_cnt(round_cnt)
                    // .tick(mix_col_ready)
                  );

    assign round_state_out = state_MC ^ round_key;

	localparam IDLE     = 3'b000;
	localparam LOAD     = 3'b001;
	localparam SUBBYTE  = 3'b010;
	localparam MIXCOL   = 3'b011;
    localparam ENDROUND = 3'b100;
	localparam END      = 3'b101;

	reg [2:0] current_state, next_state;

	always @(current_state or start or mix_col_ready or sub_byte_ready )//round_state_out)
	begin
        sub_byte_en = 0;
        mix_col_en = 0;
        done = 0;
		case (current_state)
		IDLE: if (start) 
                begin
                    round_cnt = 0;
                    next_state = LOAD;
                end
			  else 
                next_state = IDLE;
		LOAD: 
            begin
                if (!round_cnt)
                    state = plain_text ^ key;
                // else 
                //     state = round_state_out;
                next_state = SUBBYTE;
            end
		SUBBYTE: 
            if (sub_byte_ready)
                next_state = MIXCOL;
                
			else 
            begin 
                sub_byte_en = 1;
			    next_state = SUBBYTE;
            end
        MIXCOL:
            
            if (mix_col_ready )
                next_state = ENDROUND;
			else 
            begin 
                mix_col_en = 1;
			    next_state = MIXCOL;
            end
        ENDROUND:
            begin
            if(round_cnt == 9)
                next_state = END;
            else 
                begin 
                    round_cnt = round_cnt + 1;
                    next_state = LOAD;
                end
                    state = round_state_out;

            end
        END:
            begin
               next_state = IDLE;
               cipher_text = state;
               done = 1;
            end
		endcase
	end 
	always @(posedge clk or negedge rst_n)
	begin
		if (~rst_n)
			current_state <= IDLE;
		else
			current_state <= next_state;
	end
endmodule

module AES_tb();
    reg clk, rst_n,start;
    reg [127:0] plain_text, key;
    wire done;
    wire [127:0] cipher_text;

AES_encrptor DUT(.clk(clk), 
                .rst_n(rst_n),
                .start(start),
                .plain_text(plain_text),
                .cipher_text(cipher_text),
                .key(key),
                .done(done)
                );
    always #5 clk= ~clk;

    initial begin
        key = 128'h6162636465666768696a6b6c6d6e6f70;
        plain_text = 128'hffca32589aac5530f3c63e5c9ea8512c;
        rst_n = 0;
        clk = 1;
        #10
        rst_n = 1;
        #10
        start = 1; 

        // en = 1 ;/
    end
    
endmodule