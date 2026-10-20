// UART receiver, 8N1, mid-bit sampling. Each bit lasts (div + 1) clocks.
// - false-start rejection: start bit re-checked at its midpoint
// - framing check: stop bit must be high, else frame_err pulses and the
//   receiver waits for the line to return high (break) before re-arming.
// rx must already be synchronized to clk.
// The bit-timer terminal count is a registered flag (cz), not a 16-bit compare.
`default_nettype none
module uart_rx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] div,
    input  wire        rx,
    output reg         valid,
    output reg  [7:0]  data,
    output reg         frame_err
);
    localparam S_IDLE = 3'd0, S_START = 3'd1, S_DATA = 3'd2,
               S_STOP = 3'd3, S_BREAK = 3'd4;

    reg [2:0]  state;
    reg [15:0] cnt;
    reg        cz;       // cnt == 0, registered one cycle ahead
    wire       div_z  = (div == 16'd0);
    wire       cnt_1  = (cnt == 16'd1);
    // Center of a (div + 1)-cycle bit, 0-based from the cycle the bit is
    // first seen, is (div + 1) >> 1. S_START samples on the cycle after cz
    // is set, so the counter loads one less: (div - 1) >> 1. div == 0 is a
    // one-cycle start bit and does not use this. Loading div >> 1 instead
    // waits one cycle past the center when div is even.
    wire [15:0] start_cnt = (div - 16'd1) >> 1;
    wire        start_z   = (start_cnt == 16'd0);
    reg [2:0]  bitn;
    reg [7:0]  sh;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            cnt       <= 16'd0;
            cz        <= 1'b1;
            bitn      <= 3'd0;
            sh        <= 8'd0;
            data      <= 8'd0;
            valid     <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            valid     <= 1'b0;
            frame_err <= 1'b0;
            case (state)
                S_IDLE: if (!rx) begin
                    if (div_z) begin
                        // 1 clock/bit: this cycle is the whole start bit.
                        // S_START would sample one bit late and corrupt the byte.
                        state <= S_DATA;
                        cnt   <= div;
                        cz    <= 1'b1;
                        bitn  <= 3'd0;
                    end else begin
                        state <= S_START;
                        cnt   <= start_cnt;
                        cz    <= start_z;
                    end
                end
                S_START: if (!cz) begin cnt <= cnt - 16'd1; cz <= cnt_1; end
                else if (!rx) begin
                    state <= S_DATA;
                    cnt   <= div;
                    cz    <= div_z;
                    bitn  <= 3'd0;
                end else begin
                    state <= S_IDLE;     // glitch, not a real start bit
                end
                S_DATA: if (!cz) begin cnt <= cnt - 16'd1; cz <= cnt_1; end
                else begin
                    sh   <= {rx, sh[7:1]};
                    cnt  <= div;
                    cz    <= div_z;
                    bitn <= bitn + 3'd1;
                    if (bitn == 3'd7) state <= S_STOP;
                end
                S_STOP: if (!cz) begin cnt <= cnt - 16'd1; cz <= cnt_1; end
                else if (rx) begin
                    valid <= 1'b1;
                    data  <= sh;
                    state <= S_IDLE;
                end else begin
                    frame_err <= 1'b1;
                    state     <= S_BREAK;
                end
                S_BREAK: if (rx) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    // The only encodings this FSM writes are IDLE..BREAK. A state above
    // S_BREAK is the default arm. Posedge-only so the check is not an
    // async-reset assertion.
`ifdef FORMAL
    always @(posedge clk) if (rst_n) assert(state <= S_BREAK);
`endif
endmodule
`default_nettype wire
