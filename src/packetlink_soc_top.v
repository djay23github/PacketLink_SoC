/* verilator lint_off UNUSEDSIGNAL */
module packetlink_soc_top #(
    parameter FIFO_ADDR_WIDTH    = 4,
    parameter PAYLOAD_LENGTH     = 4,
    parameter MAX_PAYLOAD_LENGTH = 16,
    parameter UART_PRESCALE     = 54
)(
    //--------------------------------------------------
    // Clocks / Reset
    //--------------------------------------------------

    input  wire        uart_clk,
    input  wire        serdes_clk,
    input  wire        rst_n,

`ifdef USE_POWER_PINS
    inout  wire        VPWR,
    inout  wire        VGND,
`endif

    //--------------------------------------------------
    // UART Physical Pins
    //--------------------------------------------------

    input  wire        uart_rxd,
    output wire        uart_txd,

    //--------------------------------------------------
    // SERDES Physical Pins
    //--------------------------------------------------

    output wire        serdes_tx,
    input  wire        serdes_rx,

    //--------------------------------------------------
    // Status
    //--------------------------------------------------

    output wire        tx_fifo_full,
    output wire        rx_fifo_full,
    output wire        tx_fifo_empty,
    output wire        rx_fifo_empty,

    output reg         tx_fifo_overflow,
    output reg         rx_fifo_overflow,
    output reg         crc_error_sticky,
    output wire        packet_valid_pulse
);

    //--------------------------------------------------
    // Reset Synchronization
    //--------------------------------------------------

    wire uart_rst_n;
    wire serdes_rst_n;

    reset_sync u_uart_reset_sync (
        .clk         (uart_clk),
        .async_rst_n (rst_n),
        .sync_rst_n  (uart_rst_n)
    );

    reset_sync u_serdes_reset_sync (
        .clk         (serdes_clk),
        .async_rst_n (rst_n),
        .sync_rst_n  (serdes_rst_n)
    );

    //--------------------------------------------------
    // UART Domain Signals
    //--------------------------------------------------

    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;

    wire [7:0] uart_tx_data;
    wire       uart_tx_valid;
    wire       uart_tx_ready;

    //--------------------------------------------------
    // TX FIFO: UART Domain -> SERDES Domain
    //--------------------------------------------------

    wire [7:0] tx_fifo_dout;
    wire       tx_fifo_rd_en;
    wire       tx_fifo_wr_en;

    assign tx_fifo_wr_en = uart_rx_valid;

    //--------------------------------------------------
    // Packet Framer Signals, SERDES Domain
    //--------------------------------------------------

    wire [7:0] framer_data;
    wire       framer_valid;
    wire       framer_ready;

    //--------------------------------------------------
    // SERDES Signals
    //--------------------------------------------------

    wire [7:0] serdes_parallel_out;
    wire       serdes_tx_done;
    wire       serdes_rx_valid;

    reg [7:0] serdes_parallel_out_q;
    reg       serdes_rx_valid_q;

    assign framer_ready = serdes_tx_done;

    //--------------------------------------------------
    // Deframer Signals, SERDES Domain
    //--------------------------------------------------

    wire [7:0] payload_data;
    wire       payload_valid;
    wire       crc_error_pulse;

    //--------------------------------------------------
    // RX FIFO: SERDES Domain -> UART Domain
    //--------------------------------------------------

    wire [7:0] rx_fifo_dout;
    wire       rx_fifo_wr_en;
    reg        rx_fifo_rd_en_reg;

    assign rx_fifo_wr_en = payload_valid;

    //--------------------------------------------------
    // UART TX Adapter Signals
    //--------------------------------------------------

    localparam UART_TX_IDLE = 2'd0;
    localparam UART_TX_WAIT = 2'd1;
    localparam UART_TX_LOAD = 2'd2;
    localparam UART_TX_SEND = 2'd3;

    reg [1:0] uart_tx_state;

    reg [7:0] uart_tx_data_reg;
    reg       uart_tx_valid_reg;
    wire rx_fifo_rd_en;

    assign uart_tx_data  = uart_tx_data_reg;
    assign uart_tx_valid = uart_tx_valid_reg;
    assign rx_fifo_rd_en = rx_fifo_rd_en_reg;

    //--------------------------------------------------
    // Sticky Status Flags
    //--------------------------------------------------

    always @(posedge uart_clk or negedge uart_rst_n) begin
        if (!uart_rst_n) begin
            tx_fifo_overflow <= 1'b0;
        end else begin
            if (uart_rx_valid && tx_fifo_full)
                tx_fifo_overflow <= 1'b1;
        end
    end

    always @(posedge serdes_clk or negedge serdes_rst_n) begin
        if (!serdes_rst_n) begin
            rx_fifo_overflow <= 1'b0;
            crc_error_sticky <= 1'b0;
        end else begin
            if (payload_valid && rx_fifo_full)
                rx_fifo_overflow <= 1'b1;

            if (crc_error_pulse)
                crc_error_sticky <= 1'b1;
        end
    end

    //--------------------------------------------------
    // RX FIFO -> UART TX Adapter
    //
    // The async FIFO has registered read data:
    //   cycle N   : adapter requests a read by registering rd_en
    //   cycle N+1 : FIFO observes rd_en and updates dout
    //   cycle N+2 : adapter captures the updated dout
    //
    // So UART TX waits one extra cycle before loading rx_fifo_dout.
    //--------------------------------------------------

    always @(posedge uart_clk or negedge uart_rst_n) begin
        if (!uart_rst_n) begin
            uart_tx_state     <= UART_TX_IDLE;
            uart_tx_data_reg  <= 8'h00;
            uart_tx_valid_reg <= 1'b0;
            rx_fifo_rd_en_reg <= 1'b0;
        end else begin
            uart_tx_valid_reg <= 1'b0;
            rx_fifo_rd_en_reg <= 1'b0;

            case (uart_tx_state)

                UART_TX_IDLE: begin
                    if (!rx_fifo_empty && uart_tx_ready) begin
                        rx_fifo_rd_en_reg <= 1'b1;
                        uart_tx_state     <= UART_TX_WAIT;
                    end
                end

                UART_TX_WAIT: begin
                    uart_tx_state <= UART_TX_LOAD;
                end

                UART_TX_LOAD: begin
                    uart_tx_data_reg <= rx_fifo_dout;
                    uart_tx_state    <= UART_TX_SEND;
                end

                UART_TX_SEND: begin
                    if (uart_tx_ready) begin
                        uart_tx_valid_reg <= 1'b1;
                        uart_tx_state     <= UART_TX_IDLE;
                    end
                end

                default: begin
                    uart_tx_state <= UART_TX_IDLE;
                end

            endcase
        end
    end

    //--------------------------------------------------
    // UART Macro, 50 MHz Domain
    //--------------------------------------------------

    uart_top #(.PRESCALE(UART_PRESCALE)) u_uart_top (
`ifdef USE_POWER_PINS
        .VPWR      (VPWR),
        .VGND      (VGND),
`endif

        .clk       (uart_clk),
        .rst_n     (uart_rst_n),

        .uart_rxd  (uart_rxd),
        .uart_txd  (uart_txd),

        .rx_data   (uart_rx_data),
        .rx_valid  (uart_rx_valid),

        .tx_data   (uart_tx_data),
        .tx_valid  (uart_tx_valid),
        .tx_ready  (uart_tx_ready)
    );

    //--------------------------------------------------
    // TX Async FIFO
    // UART 50 MHz write -> SERDES 200 MHz read
    //--------------------------------------------------

    async_fifo #(
        .DATA_WIDTH (8),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) u_tx_async_fifo (
        .wr_clk     (uart_clk),
        .wr_rst_n   (uart_rst_n),
        .wr_en      (tx_fifo_wr_en),
        .din        (uart_rx_data),
        .full       (tx_fifo_full),

        .rd_clk     (serdes_clk),
        .rd_rst_n   (serdes_rst_n),
        .rd_en      (tx_fifo_rd_en),
        .dout       (tx_fifo_dout),
        .empty      (tx_fifo_empty)
    );

    //--------------------------------------------------
    // Packet Framer, 200 MHz Domain
    //--------------------------------------------------

    packet_framer #(
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH)
    ) u_packet_framer (
        .clk          (serdes_clk),
        .rst_n        (serdes_rst_n),

        .fifo_dout    (tx_fifo_dout),
        .fifo_empty   (tx_fifo_empty),
        .fifo_rd_en   (tx_fifo_rd_en),

        .serdes_data  (framer_data),
        .serdes_valid (framer_valid),
        .serdes_ready (framer_ready)
    );

    //--------------------------------------------------
    // SERDES Macro, 200 MHz Domain
    //--------------------------------------------------

    serdes_top u_serdes_top (
`ifdef USE_POWER_PINS
        .VPWR              (VPWR),
        .VGND              (VGND),
`endif

        .clk               (serdes_clk),
        .rst_n             (serdes_rst_n),

        .parallel_data_in  (framer_data),
        .tx_valid          (framer_valid),
        .parallel_data_out (serdes_parallel_out),

        .tx_serial         (serdes_tx),
        .rx_serial         (serdes_rx),
        
        .tx_done           (serdes_tx_done),
        .rx_valid          (serdes_rx_valid)
    );

    //--------------------------------------------------
    // Registered SERDES RX, 200 MHz Domain
    //--------------------------------------------------

    always @(posedge serdes_clk or negedge serdes_rst_n) begin
        if (!serdes_rst_n) begin
            serdes_parallel_out_q <= 8'h00;
            serdes_rx_valid_q     <= 1'b0;
        end else begin
            serdes_parallel_out_q <= serdes_parallel_out;
            serdes_rx_valid_q     <= serdes_rx_valid;
        end
    end

    //--------------------------------------------------
    // Buffered Packet Deframer, 200 MHz Domain
    //
    // Bad-CRC packets are dropped. Payload is emitted only
    // after CRC passes.
    //--------------------------------------------------

    packet_deframer #(
        .MAX_PAYLOAD_LENGTH(MAX_PAYLOAD_LENGTH)
    ) u_packet_deframer (
        .clk            (serdes_clk),
        .rst_n          (serdes_rst_n),

        .serdes_data    (serdes_parallel_out_q),
        .serdes_valid   (serdes_rx_valid_q),

        .payload_data   (payload_data),
        .payload_valid  (payload_valid),

        .packet_valid   (packet_valid_pulse),
        .crc_error      (crc_error_pulse)
    );

    //--------------------------------------------------
    // RX Async FIFO
    // SERDES 200 MHz write -> UART 50 MHz read
    //--------------------------------------------------

    async_fifo #(
        .DATA_WIDTH (8),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) u_rx_async_fifo (
        .wr_clk     (serdes_clk),
        .wr_rst_n   (serdes_rst_n),
        .wr_en      (rx_fifo_wr_en),
        .din        (payload_data),
        .full       (rx_fifo_full),

        .rd_clk     (uart_clk),
        .rd_rst_n   (uart_rst_n),
        .rd_en      (rx_fifo_rd_en),
        .dout       (rx_fifo_dout),
        .empty      (rx_fifo_empty)
    );

endmodule
