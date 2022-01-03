module  mixCols_ASMD (
    input [127:0] state_in,
    input clk, rst_n, enable,
    input [3:0] round_cnt,
    output wire output_ready,
    output wire [127:0] state_out

);
    wire [1:0]local_cnt;
    // wire run;
    mixcols_cu cu(.clk(clk),
                  .rst_n(rst_n),
                  .enable(enable),
                  .output_ready(output_ready),
                  .local_cnt(local_cnt)
                //   .running_state(run)
                 );
    mixcols_dp dp(  .state_in(state_in),
                    .local_cnt(local_cnt),
                    .round_cnt(round_cnt),
                    // .output_ready(output_ready),
                    .state_out(state_out)
    );   



endmodule


module mixcols_cu(
    input clk, rst_n, enable, 
    output reg output_ready,
    output reg[1:0] local_cnt

);
    localparam DONE = 1'b0;
	localparam RUNNING = 1'b1;
	always @(posedge clk or negedge rst_n)
    begin
		if (~rst_n || ~enable)
        begin
			local_cnt <= 0; 
     	    output_ready <= 0;
        end
        else 
            begin 
                if(local_cnt==2)
                // begin
                    output_ready <= 1;
                //     // running_state <= 0;
                // end
            
                    local_cnt = local_cnt + 1;
            end
	end
endmodule

module mixcols_dp (
    input [1:0]local_cnt,
    input [3:0]round_cnt,
    // output reg output_ready,
    // input en,
    input [127:0] state_in,
    output reg [127:0] state_out
);
    reg [31:0] col_mul_input; 
    wire [31:0] col_mul_output;
    column_mul cm(
                .word_in(col_mul_input),
                .word_out(col_mul_output)
                 );
    always @(local_cnt or col_mul_output or state_in)//state_in or local_cnt or en )
     begin
        if (round_cnt == 9)
            state_out = state_in;
        else
        case (local_cnt)
                2'b00:
                begin  
              col_mul_input = state_in[31:0];
                    state_out[31:0]  = col_mul_output;
                
                end
                2'b01:
                begin 
                    col_mul_input = state_in[63:32] ;
                    state_out[63:32]  = col_mul_output;
     
                end
                2'b10:
                begin 
                    col_mul_input = state_in[95:64] ;
                    state_out[95:64]  = col_mul_output;

                end
                2'b11:
                begin 
                    col_mul_input = state_in [127:96] ;
                    state_out[127:96]  = col_mul_output;
                    // output_ready = 1; 
                end
            endcase
        // else 
           
    end
    
endmodule


module column_mul (
    input [31:0] word_in,
    output [31:0] word_out
);
    
    reg cout;
    function [7:0] mul2 (
    input [7:0] byte);
        mul2 = {byte[6 : 0], 1'b0} ^ (8'h1b & {8{byte[7]}});
    endfunction

    wire [7:0] temp;

    assign temp =word_in [7:0]  ^ word_in [15:8]  ^ word_in[23:16]  ^ word_in[31:24];

    assign word_out[31:24] = word_in[31:24] ^ temp ^ mul2(word_in[31:24] ^word_in[23:16]  );
    assign word_out[23:16]  = word_in [23:16]   ^ temp ^ mul2(word_in[23:16] ^word_in[15:8]);
    assign word_out[15:8]  = word_in[15:8]  ^ temp ^ mul2(word_in[15:8]  ^word_in[7:0]);
    assign word_out[7:0]  = word_in[7:0] ^ temp ^ mul2(word_in[7:0]^word_in[31:24] );


    
endmodule
module mul2_m (
    input [7:0]byte_in, 
    output [7:0]byte_out
);
assign byte_out= {byte_in[6 : 0], 1'b0} ^ (8'h1b & {8{byte_in[7]}});
endmodule

module mixCol_tb ();
    reg clk,rst_n;
    reg [127:0] state_in;
    wire [127:0] state_out;
    wire rdy;
    // reg en;
    mixCols_ASMD DUT (.clk(clk),
                .rst_n(rst_n),
                .state_in(state_in),
                .state_out(state_out),
                .output_ready(rdy)
                );

    // column_mul DUT2(.word_in(state_in[31:0]),
    //                 .word_out(state_out[31:0])
    //                 );
    always #5 clk= ~clk;
    initial begin
        rst_n = 0;
                clk = 1;

        #5
        state_in = 128'h88372bfc53cd15a7b0467618f934d52b;

        #10
        rst_n = 1;
        // en = 1 ;/
    end

endmodule
