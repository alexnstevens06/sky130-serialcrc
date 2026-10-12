// Two-flop synchronizer for asynchronous inputs.
`default_nettype none
module sync2 #(
    parameter RESET_VAL = 1'b0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire d,
    output wire q
);
    reg [1:0] s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) s <= {2{RESET_VAL}};
        else        s <= {s[0], d};
    end
    assign q = s[1];
endmodule
`default_nettype wire
