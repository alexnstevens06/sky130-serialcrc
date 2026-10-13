// Programmable bit-serial CRC engine (Rocksoft model), dual-edge.
// - poly in normal (MSB-first) form without the implicit x^WIDTH term
// - refin: each input byte is bit-reversed before processing
// - refout: the register is bit-reversed before the final XOR
// Processes TWO bits per clock using both clock edges: on every falling edge
// crc_h captures one LFSR step of crc (bit sh[7]); on the next rising edge crc
// takes a second step from crc_h (bit sh[6]). A byte takes 4 cycles (busy high).
// Paths crc->crc_h (rise->fall) and crc_h->crc (fall->rise) are half-cycle paths.
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
    reg [WIDTH-1:0] crc_h;   // falling-edge half step
    reg [7:0]       sh;
    reg [2:0]       cnt;     // bit pairs left

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

    assign busy = (cnt != 3'd0);

    // One LFSR step of each register.
    wire [WIDTH-1:0] step_lo = {crc[WIDTH-2:0], 1'b0} ^
                               ((crc[WIDTH-1] ^ sh[7]) ? poly : {WIDTH{1'b0}});
    wire [WIDTH-1:0] step_hi = {crc_h[WIDTH-2:0], 1'b0} ^
                               ((crc_h[WIDTH-1] ^ sh[6]) ? poly : {WIDTH{1'b0}});

    // No reset: crc_h is recomputed from crc on every falling edge and is only
    // used while busy (which needs a start after reset). This keeps rst_n off
    // the falling-edge flops, so there is no half-cycle reset recovery path.
    always @(negedge clk) crc_h <= step_lo;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc  <= RESET_VAL;
            sh   <= 8'd0;
            cnt  <= 3'd0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (clear) begin
                crc <= init;
                cnt <= 3'd0;
            end else if (busy) begin
                crc  <= step_hi;
                sh   <= {sh[5:0], 2'b00};
                cnt  <= cnt - 3'd1;
                done <= (cnt == 3'd1);
            end else if (start) begin
                sh  <= refin ? din_rev : din;
                cnt <= 3'd4;
            end
        end
    end

    assign result = (refout ? crc_rev : crc) ^ xorout;
endmodule
`default_nettype wire
