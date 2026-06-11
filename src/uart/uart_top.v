// =============================================================================
// uart_top.v: top-level wrapper for alexforencich UART core
//
// Strips AXI-Stream handshake down to a simple valid/ready interface that
// the bridge FSM can talk to directly.
//
// Baud rate is set by the PRESCALE parameter:
//   PRESCALE = clk_freq_hz / (baud_rate * 8)
//   For example, for 50 MHz clock and 115200 baud, Oversampling rate = 8 : use PRESCALE = 27.
//
// Interface:
//   clk, rst_n          - clock and active-low async reset
//   uart_rxd            - serial input  (from pad)
//   uart_txd            - serial output (to pad)
//   rx_data[7:0]        - received byte
//   rx_valid            - high for one clk when rx_data is valid
//   tx_data[7:0]        - byte to transmit
//   tx_valid            - assert for one clk to request TX
//   tx_ready            - high when UART TX is idle and can accept a byte
// =============================================================================

/* verilator lint_off PINCONNECTEMPTY */
module uart_top #(
    parameter PRESCALE = 16'd54    // 50 MHz / 115200 baud
) (
    input            clk,
    input            rst_n,

    // Physical serial pins
    input            uart_rxd,
    output           uart_txd,

    // RX interface
    output [7:0]     rx_data,
    output           rx_valid,

    // TX interface
    input  [7:0]     tx_data,
    input            tx_valid,
    output           tx_ready
);


    // =========================================================================
    // AXI-Stream TX wires (from this wrapper to core)
    // =========================================================================
    wire [7:0] axis_tx_tdata;
    wire       axis_tx_tvalid;
    wire       axis_tx_tready;

    // =========================================================================
    // AXI-Stream RX wires (from core to this wrapper)
    // =========================================================================
    wire [7:0] axis_rx_tdata;
    wire       axis_rx_tvalid;
    wire       axis_rx_tready;

    // =========================================================================
    // TX side: hold tx_data stable until the core accepts it.
    // tx_valid is a one-cycle pulse from the bridge; the UART core may not
    // be ready that exact cycle, so we register the request.
    // =========================================================================
    reg [7:0] tx_hold;
    reg       tx_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_hold    <= 8'h00;
            tx_pending <= 1'b0;
        end else begin
            if (tx_valid && !tx_pending) begin
                // New request from bridge
                tx_hold    <= tx_data;
                tx_pending <= 1'b1;
            end else if (axis_tx_tvalid && axis_tx_tready) begin
                // Core accepted the byte
                tx_pending <= 1'b0;
            end
        end
    end

    assign axis_tx_tdata  = tx_hold;
    assign axis_tx_tvalid = tx_pending;
    // tx_ready: bridge can submit the next byte when we're not holding one
    assign tx_ready       = !tx_pending;

    // =========================================================================
    // RX side: the core raises axis_rx_tvalid for one cycle per received byte.
    // We acknowledge immediately (tready always high) and register the output.
    // =========================================================================
    reg [7:0] rx_data_r;
    reg       rx_valid_r;

    assign axis_rx_tready = 1'b1;   // always ready to consume received bytes

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data_r  <= 8'h00;
            rx_valid_r <= 1'b0;
        end else begin
            rx_valid_r <= axis_rx_tvalid;  // one-cycle pulse
            if (axis_rx_tvalid)
                rx_data_r <= axis_rx_tdata;
        end
    end

    assign rx_data  = rx_data_r;
    assign rx_valid = rx_valid_r;

    // =========================================================================
    // alexforencich uart core instantiation
    // Source: https://github.com/alexforencich/verilog-uart
    //   uart.v instantiates uart_tx.v and uart_rx.v internally.
    //   Prescale sets baud rate: baud = clk / (prescale * 8)
    // =========================================================================
    uart #(
        .DATA_WIDTH(8)
    ) u_uart_core (
        .clk          (clk),
        .rst          (rst_n),

        // AXI-Stream TX (slave: we send data to the core)
        .s_axis_tdata (axis_tx_tdata),
        .s_axis_tvalid(axis_tx_tvalid),
        .s_axis_tready(axis_tx_tready),

        // AXI-Stream RX (master: core sends received data to us)
        .m_axis_tdata (axis_rx_tdata),
        .m_axis_tvalid(axis_rx_tvalid),
        .m_axis_tready(axis_rx_tready),

        // Physical pins
        .rxd          (uart_rxd),
        .txd          (uart_txd),

        // Status (unused at this level)
        .tx_busy      (),
        .rx_busy      (),
        .rx_overrun_error(),
        .rx_frame_error  (),

        // Baud prescale
        .prescale     (PRESCALE)
    );

endmodule
