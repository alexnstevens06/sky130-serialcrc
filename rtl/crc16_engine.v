// Programmable bit-serial CRC engine (Rocksoft model).
// - poly in normal (MSB-first) form without the implicit x^WIDTH term
// - refin: each input byte is bit-reversed before processing
// - refout: the register is bit-reversed before the final XOR
// Processes one bit per clock: a byte takes 8 cycles (busy high).
// `clear` loads the register with `init` (and cancels a byte in flight).
`default_nettype none
module crc16_engine #(
    parameter             WIDTH     = 16,
    parameter [WIDTH-1:0] RESET_VAL = {WIDTH{1'b1}}
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] poly,
    input  wire [WIDTH-1:0] init,
    input  wire [WIDTH-1:0] xorout,
    input  wire             refin,
    input  wire             refout,
    input  wire             clear,
    input  wire             start,
    input  wire [7:0]       din,
    output wire             busy,
    output reg              done,
    output wire [WIDTH-1:0] result
);
    reg [WIDTH-1:0] crc;
    reg [7:0]       sh;
    reg [3:0]       cnt;

    wire [7:0]       din_rev;
    wire [WIDTH-1:0] crc_rev;
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : g_rev8
            assign din_rev[i] = din[7-i];
        end
        for (i = 0; i < WIDTH; i = i + 1) begin : g_revw
            assign crc_rev[i] = crc[WIDTH-1-i];
        end
    endgenerate

    assign busy = (cnt != 4'd0);
    wire fb = crc[WIDTH-1] ^ sh[7];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc  <= RESET_VAL;
            sh   <= 8'd0;
            cnt  <= 4'd0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (clear) begin
                crc <= init;
                cnt <= 4'd0;
            end else if (busy) begin
                crc  <= {crc[WIDTH-2:0], 1'b0} ^ (fb ? poly : {WIDTH{1'b0}});
                sh   <= {sh[6:0], 1'b0};
                cnt  <= cnt - 4'd1;
                done <= (cnt == 4'd1);
            end else if (start) begin
                sh  <= refin ? din_rev : din;
                cnt <= 4'd8;
            end
        end
    end

    assign result = (refout ? crc_rev : crc) ^ xorout;
endmodule
`default_nettype wire
