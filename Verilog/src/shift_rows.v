module shiftRows (
    input [127:0] state_in,
    output [127:0] state_out
);
wire [31:0] w0,w1,w2,w3,ws0,ws1,ws2,ws3;
     assign w0 = state_in[127 : 96];
     assign w1 = state_in[95 : 64];
     assign w2 = state_in[63 : 32];
     assign w3 = state_in[31 : 0];

     assign ws0 = {w0[31 : 24], w1[23 : 16], w2[15 : 8], w3[07 : 0]};
     assign ws1 = {w1[31 : 24], w2[23 : 16], w3[15 : 8], w0[07 : 0]};
     assign ws2 = {w2[31 : 24], w3[23 : 16], w0[15 : 8], w1[07 : 0]};
     assign ws3 = {w3[31 : 24], w0[23 : 16], w1[15 : 8], w2[07 : 0]};

    assign state_out = {ws0, ws1, ws2, ws3}; 

endmodule

module shiftRows_tb ();
    reg [127:0] state;
    wire [127:0] out;
    shiftRows DUT(.state_in(state),
                  .state_out(out)
                  );
    initial begin
        state = 128'h11246800389a40d2d9f401dae7fdc50d;
    end
endmodule