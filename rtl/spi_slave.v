// SPI slave, mode 0 (CPOL=0, CPHA=0), MSB first, oversampled by clk.
// Inputs must already be synchronized to clk. Requires f_clk >= 8 * f_sclk.
// Frame: 16 bits per transaction. byte0 = {rw, addr[6:0]}, byte1 = data.
//   rw=1: rd_req pulses after byte0; rd_data is sampled that cycle and shifted
//         out on MISO during byte1; rd_done pulses after byte1 completes
//         (used for read side effects).
//   rw=0: wr_en pulses after byte1 completes.
// Raising cs_n before 16 bits aborts the transaction with no write/rd_done.
`default_nettype none
module spi_slave (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sclk,
    input  wire       cs_n,
    input  wire       mosi,
    output reg        miso,
    output reg  [6:0] addr,
    output reg        rd_req,
    output reg        rd_done,
    input  wire [7:0] rd_data,
    output reg        wr_en,
    output reg  [7:0] wr_data
);
    reg       sclk_q;
    reg [3:0] bitcnt;
    reg [6:0] sh;
    reg       rw;
    reg [7:0] tx_sh;

    wire rise = sclk & ~sclk_q;
    wire fall = ~sclk & sclk_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // High so an SCLK that is already high when reset releases is
            // not a rising edge. A low SCLK is a falling edge at bitcnt 0,
            // which does not shift a bit.
            sclk_q  <= 1'b1;
            bitcnt  <= 4'd0;
            sh      <= 7'd0;
            rw      <= 1'b0;
            tx_sh   <= 8'd0;
            miso    <= 1'b0;
            addr    <= 7'd0;
            rd_req  <= 1'b0;
            rd_done <= 1'b0;
            wr_en   <= 1'b0;
            wr_data <= 8'd0;
        end else begin
            sclk_q  <= sclk;
            rd_req  <= 1'b0;
            rd_done <= 1'b0;
            wr_en   <= 1'b0;
            if (cs_n) begin
                bitcnt <= 4'd0;
                miso   <= 1'b0;
            end else begin
                if (rise) begin
                    sh     <= {sh[5:0], mosi};
                    bitcnt <= bitcnt + 4'd1;
                    if (bitcnt == 4'd7) begin
                        rw     <= sh[6];
                        addr   <= {sh[5:0], mosi};
                        rd_req <= sh[6];
                        tx_sh  <= 8'd0;
                    end
                    if (bitcnt == 4'd15) begin
                        if (rw) rd_done <= 1'b1;
                        else begin
                            wr_en   <= 1'b1;
                            wr_data <= {sh, mosi};
                        end
                    end
                end
                if (rd_req) tx_sh <= rd_data;
                if (fall) begin
                    if (bitcnt[3]) begin
                        miso  <= tx_sh[7];
                        tx_sh <= {tx_sh[6:0], 1'b0};
                    end else begin
                        miso  <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
