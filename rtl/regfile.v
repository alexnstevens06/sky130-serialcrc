// Register file / glue for tt_um_alexstevens_serialcrc. See SPEC.md for the map.
`default_nettype none
module regfile #(
    parameter [15:0] BAUD_RESET = 16'd86
) (
    input  wire        clk,
    input  wire        rst_n,
    // SPI-side bus
    input  wire [6:0]  addr,
    input  wire        rd_req,
    input  wire        rd_done,
    output reg  [7:0]  rd_data,
    input  wire        wr_en,
    input  wire [7:0]  wr_data,
    // UART
    output wire [15:0] baud_div,
    output wire        tx_start,
    output wire [7:0]  tx_data,
    input  wire        tx_busy,
    input  wire        rx_strobe,
    input  wire [7:0]  rx_byte,
    input  wire        rx_frame_err,
    output reg         rx_valid,
    // CRC
    output wire [15:0] crc_poly,
    output wire [15:0] crc_init,
    output wire [15:0] crc_xorout,
    output wire        crc_refin,
    output wire        crc_refout,
    output wire        crc_clear,
    output wire        crc_start,
    output wire [7:0]  crc_din,
    input  wire        crc_busy,
    input  wire        crc_done_pulse,
    input  wire [15:0] crc_result,
    // GPIO / IRQ
    output reg  [7:0]  gpio_out,
    output reg  [7:0]  gpio_oe,
    output wire        irq
);
    localparam A_ID      = 7'h00, A_CTRL    = 7'h01, A_STATUS  = 7'h02,
               A_BAUD_LO = 7'h03, A_BAUD_HI = 7'h04, A_UART    = 7'h05,
               A_POLY_LO = 7'h06, A_POLY_HI = 7'h07, A_INIT_LO = 7'h08,
               A_INIT_HI = 7'h09, A_XOR_LO  = 7'h0A, A_XOR_HI  = 7'h0B,
               A_CRC_DAT = 7'h0C, A_CRC_CMD = 7'h0D, A_CRC_LO  = 7'h0E,
               A_CRC_HI  = 7'h0F, A_GPIO    = 7'h10, A_GPIO_OE = 7'h11;
    localparam [7:0] CHIP_ID = 8'hA5;

    reg [4:0]  ctrl;
    reg [15:0] baud, poly, init, xorout;
    reg [7:0]  rx_data;
    reg        rx_overrun, frame_err, crc_done;
    reg [2:0]  status_snap;   // sticky STATUS bits [5:3] captured when a read starts

    wire [7:0] status = {2'b00, frame_err, crc_done, rx_overrun,
                         crc_busy, rx_valid, tx_busy};

    wire wr_uart    = wr_en && addr == A_UART;
    wire wr_crc_dat = wr_en && addr == A_CRC_DAT;
    wire wr_crc_cmd = wr_en && addr == A_CRC_CMD;
    wire autofeed   = ctrl[2] && rx_strobe;

    assign baud_div   = baud;
    assign tx_start   = wr_uart && !tx_busy;
    assign tx_data    = wr_data;
    assign crc_poly   = poly;
    assign crc_init   = init;
    assign crc_xorout = xorout;
    assign crc_refin  = ctrl[0];
    assign crc_refout = ctrl[1];
    assign crc_clear  = wr_crc_cmd && wr_data[0];
    // UART autofeed has priority over an SPI CRC_DATA write in the same cycle.
    assign crc_start  = !crc_busy && (autofeed || wr_crc_dat);
    assign crc_din    = autofeed ? rx_byte : wr_data;
    assign irq        = (ctrl[3] && rx_valid) || (ctrl[4] && crc_done);

    always @(*) begin
        case (addr)
            A_ID:      rd_data = CHIP_ID;
            A_CTRL:    rd_data = {3'b000, ctrl};
            A_STATUS:  rd_data = status;
            A_BAUD_LO: rd_data = baud[7:0];
            A_BAUD_HI: rd_data = baud[15:8];
            A_UART:    rd_data = rx_data;
            A_POLY_LO: rd_data = poly[7:0];
            A_POLY_HI: rd_data = poly[15:8];
            A_INIT_LO: rd_data = init[7:0];
            A_INIT_HI: rd_data = init[15:8];
            A_XOR_LO:  rd_data = xorout[7:0];
            A_XOR_HI:  rd_data = xorout[15:8];
            A_CRC_LO:  rd_data = crc_result[7:0];
            A_CRC_HI:  rd_data = crc_result[15:8];
            A_GPIO:    rd_data = gpio_out;
            A_GPIO_OE: rd_data = gpio_oe;
            default:   rd_data = 8'h00;
        endcase
    end

    wire rd_status_done = rd_done && addr == A_STATUS;
    wire rd_uart_done   = rd_done && addr == A_UART;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl        <= 5'd0;
            baud        <= BAUD_RESET;
            poly        <= 16'h1021;
            init        <= 16'hFFFF;
            xorout      <= 16'h0000;
            gpio_out    <= 8'h00;
            gpio_oe     <= 8'h00;
            rx_data     <= 8'h00;
            rx_valid    <= 1'b0;
            rx_overrun  <= 1'b0;
            frame_err   <= 1'b0;
            crc_done    <= 1'b0;
            status_snap <= 3'b000;
        end else begin
            if (wr_en) begin
                case (addr)
                    A_CTRL:    ctrl         <= wr_data[4:0];
                    A_BAUD_LO: baud[7:0]    <= wr_data;
                    A_BAUD_HI: baud[15:8]   <= wr_data;
                    A_POLY_LO: poly[7:0]    <= wr_data;
                    A_POLY_HI: poly[15:8]   <= wr_data;
                    A_INIT_LO: init[7:0]    <= wr_data;
                    A_INIT_HI: init[15:8]   <= wr_data;
                    A_XOR_LO:  xorout[7:0]  <= wr_data;
                    A_XOR_HI:  xorout[15:8] <= wr_data;
                    A_GPIO:    gpio_out     <= wr_data;
                    A_GPIO_OE: gpio_oe      <= wr_data;
                    default: ;
                endcase
            end

            if (rd_req && addr == A_STATUS) status_snap <= status[5:3];

            // Read side effects happen only when the read completes; sticky
            // bits are cleared only if they were set in the value returned.
            if (rd_status_done) begin
                if (status_snap[0]) rx_overrun <= 1'b0;
                if (status_snap[1]) crc_done   <= 1'b0;
                if (status_snap[2]) frame_err  <= 1'b0;
            end
            if (rd_uart_done) rx_valid <= 1'b0;

            // Events (set has priority over clear).
            if (rx_strobe) begin
                rx_data  <= rx_byte;
                rx_valid <= 1'b1;
                if (rx_valid && !rd_uart_done) rx_overrun <= 1'b1;
            end
            if (rx_frame_err)   frame_err <= 1'b1;
            if (crc_done_pulse) crc_done  <= 1'b1;
        end
    end
endmodule
`default_nettype wire
