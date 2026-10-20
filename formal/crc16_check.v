// CRC-16 matches a byte-wise Rocksoft model.
// Configuration and the data byte are registered so they are stable on both
// edges of a byte (the engine steps on the falling edge and the rising edge).
// The model applies all 8 bits when the engine finishes the byte. SymbiYosys
// BMC is 16 steps (formal/crc16.sby); `done` is reachable at step 14.
`default_nettype none
module crc16_formal (
    input wire clk,
    input wire rst_n
);
    (* anyseq *) reg [15:0] poly_n, init_n, xorout_n;
    (* anyseq *) reg        refin_n, refout_n, start_n, clear_n;
    (* anyseq *) reg [7:0]  din_n;

    reg [15:0] poly, init, xorout, gcrc, cap_poly;
    reg        refin, refout, start, clear, saw_last;
    reg [7:0]  din, cap_byte;
    reg [2:0]  left;

    wire        busy, done;
    wire [15:0] result;

    crc16_engine #(.WIDTH(16), .RESET_VAL(16'hFFFF)) dut (
        .clk(clk), .rst_n(rst_n),
        .poly(poly), .init(init), .xorout(xorout),
        .refin(refin), .refout(refout),
        .clear(clear), .start(start), .din(din),
        .busy(busy), .done(done), .result(result)
    );

    function [7:0] rev8;
        input [7:0] x;
        begin
            rev8 = {x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7]};
        end
    endfunction

    function [15:0] crc_byte;
        input [15:0] crc_in;
        input [7:0]  data;
        input [15:0] poly_in;
        integer i;
        reg [15:0] c;
        reg [7:0]  bits;
        begin
            c = crc_in;
            bits = data;
            for (i = 0; i < 8; i = i + 1) begin
                c = {c[14:0], 1'b0} ^ ((c[15] ^ bits[7]) ? poly_in : 16'h0000);
                bits = {bits[6:0], 1'b0};
            end
            crc_byte = c;
        end
    endfunction

    function [15:0] rev16;
        input [15:0] x;
        begin
            rev16 = {x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7],
                     x[8], x[9], x[10], x[11], x[12], x[13], x[14], x[15]};
        end
    endfunction

    always @* if ($initstate) assume(!rst_n);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            poly     <= 16'h1021;
            init     <= 16'hFFFF;
            xorout   <= 16'h0000;
            refin    <= 1'b0;
            refout   <= 1'b0;
            start    <= 1'b0;
            clear    <= 1'b0;
            din      <= 8'h00;
            gcrc     <= 16'hFFFF;
            cap_poly <= 16'h1021;
            cap_byte <= 8'h00;
            left     <= 3'd0;
            saw_last <= 1'b0;
        end else begin
            start   <= start_n;
            clear   <= clear_n;
            din     <= din_n;
            xorout  <= xorout_n;
            refout  <= refout_n;
            saw_last <= (left == 3'd1) && !clear;
            // Hold poly/init/refin across the start cycle and the byte.
            // xorout and refout are applied combinationally to the result.
            if (!(left != 3'd0 || start || clear)) begin
                poly  <= poly_n;
                init  <= init_n;
                refin <= refin_n;
            end
            if (clear) begin
                gcrc <= init;
                left <= 3'd0;
            end else if (left != 3'd0) begin
                if (left == 3'd1)
                    gcrc <= crc_byte(gcrc, cap_byte, cap_poly);
                left <= left - 3'd1;
            end else if (start) begin
                cap_byte <= refin ? rev8(din) : din;
                cap_poly <= poly;
                left     <= 3'd4;
            end
        end
    end

    wire [15:0] gresult = (refout ? rev16(gcrc) : gcrc) ^ xorout;

    always @(posedge clk) begin
        if (rst_n) begin
            assert(busy == (left != 3'd0));
            assert(done == saw_last);
            if (left == 3'd0)
                assert(result == gresult);
        end
        // Reachable within the BMC bound: one byte can finish.
        cover(done && rst_n);
    end
endmodule
`default_nettype wire
