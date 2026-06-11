`timescale 1ns/1ps
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off UNUSEDSIGNAL */

module tb_packetlink_soc_top;

    parameter UART_CLK_PERIOD_NS   = 20;
    parameter SERDES_CLK_PERIOD_NS = 5;
    parameter UART_PRESCALE        = 16'd54;
    parameter UART_BIT_PERIOD_NS   = 8640;

    parameter PAYLOAD_LENGTH       = 4;
    parameter NUM_DIRECTED_BYTES   = 40;
    parameter NUM_RANDOM_BYTES     = 24;
    parameter TOTAL_BYTES          = NUM_DIRECTED_BYTES + NUM_RANDOM_BYTES;
    parameter EXPECTED_PACKETS     = TOTAL_BYTES / PAYLOAD_LENGTH;
    parameter EXPECTED_FRAME_BYTES = EXPECTED_PACKETS * (PAYLOAD_LENGTH + 3);

    reg  uart_clk;
    reg  serdes_clk;
    reg  rst_n;

    reg  uart_rxd;
    wire uart_txd;

    wire serdes_tx;
    wire serdes_rx;

    wire tx_fifo_full;
    wire rx_fifo_full;
    wire tx_fifo_empty;
    wire rx_fifo_empty;

    wire tx_fifo_overflow;
    wire rx_fifo_overflow;
    wire crc_error_sticky;
    wire packet_valid_pulse;
    wire VPWR;
    wire VGND;

    reg [7:0] expected_mem [0:TOTAL_BYTES-1];
    reg [7:0] received_byte;
    reg [7:0] rand_byte;

    integer init_idx;
    integer send_idx;
    integer recv_idx;
    integer pass_count;
    integer fail_count;
    integer packet_count;
    integer random_seed;

    integer framer_accept_count;
    integer serdes_rx_count;
    integer payload_valid_count;
    integer crc_error_count;
    integer tx_fifo_full_seen;
    integer rx_fifo_full_seen;
    integer tx_fifo_empty_seen;
    integer rx_fifo_empty_seen;

    assign serdes_rx = serdes_tx;

`ifdef GATE_LEVEL_SIM
    packetlink_soc_top dut (
`else
    packetlink_soc_top #(
        .UART_PRESCALE      (UART_PRESCALE),
        .FIFO_ADDR_WIDTH    (4),
        .PAYLOAD_LENGTH     (PAYLOAD_LENGTH),
        .MAX_PAYLOAD_LENGTH (16)
    ) dut (
`endif
        .uart_clk           (uart_clk),
        .serdes_clk         (serdes_clk),
        .rst_n              (rst_n),

`ifdef USE_POWER_PINS
        .VPWR               (VPWR),
        .VGND               (VGND),
`endif

        .uart_rxd           (uart_rxd),
        .uart_txd           (uart_txd),

        .serdes_tx          (serdes_tx),
        .serdes_rx          (serdes_rx),

        .tx_fifo_full       (tx_fifo_full),
        .rx_fifo_full       (rx_fifo_full),
        .tx_fifo_empty      (tx_fifo_empty),
        .rx_fifo_empty      (rx_fifo_empty),

        .tx_fifo_overflow   (tx_fifo_overflow),
        .rx_fifo_overflow   (rx_fifo_overflow),
        .crc_error_sticky   (crc_error_sticky),
        .packet_valid_pulse (packet_valid_pulse)
    );

    assign VPWR = 1'b1;
    assign VGND = 1'b0;

    always #(UART_CLK_PERIOD_NS/2)   uart_clk   = ~uart_clk;
    always #(SERDES_CLK_PERIOD_NS/2) serdes_clk = ~serdes_clk;

    always @(posedge serdes_clk or negedge rst_n) begin
        if (!rst_n) begin
            packet_count <= 0;
            framer_accept_count <= 0;
            serdes_rx_count     <= 0;
            payload_valid_count <= 0;
            crc_error_count     <= 0;
            rx_fifo_full_seen   <= 0;
        end else begin
            if (packet_valid_pulse)
                packet_count <= packet_count + 1;

`ifndef GATE_LEVEL_SIM
            if (dut.framer_valid && dut.framer_ready)
                framer_accept_count <= framer_accept_count + 1;

            if (dut.serdes_rx_valid)
                serdes_rx_count <= serdes_rx_count + 1;

            if (dut.payload_valid)
                payload_valid_count <= payload_valid_count + 1;

            if (dut.crc_error_pulse)
                crc_error_count <= crc_error_count + 1;
`endif

            if (rx_fifo_full)
                rx_fifo_full_seen <= 1;
        end
    end

    always @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_fifo_full_seen  <= 0;
            tx_fifo_empty_seen <= 0;
            rx_fifo_empty_seen <= 0;
        end else begin
            if (tx_fifo_full)
                tx_fifo_full_seen <= 1;

            if (tx_fifo_empty)
                tx_fifo_empty_seen <= 1;

            if (rx_fifo_empty)
                rx_fifo_empty_seen <= 1;
        end
    end

    task uart_send_byte;
        input [7:0] data;
        integer bit_idx;
        begin
            uart_rxd = 1'b1;
            #(UART_BIT_PERIOD_NS);

            uart_rxd = 1'b0;
            #(UART_BIT_PERIOD_NS);

            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rxd = data[bit_idx];
                #(UART_BIT_PERIOD_NS);
            end

            uart_rxd = 1'b1;
            #(UART_BIT_PERIOD_NS);
        end
    endtask

    task uart_receive_byte;
        output [7:0] data;
        integer bit_idx;
        begin
            data = 8'h00;

            wait (uart_txd == 1'b0);
            #(UART_BIT_PERIOD_NS/2);

            if (uart_txd !== 1'b0)
                $display("[UART MON ERROR] @ %0t ns: false start bit", $time);

            #(UART_BIT_PERIOD_NS);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                data[bit_idx] = uart_txd;
                #(UART_BIT_PERIOD_NS);
            end

            if (uart_txd !== 1'b1)
                $display("[UART MON ERROR] @ %0t ns: stop bit not high", $time);

            #(UART_BIT_PERIOD_NS/2);
        end
    endtask

    task uart_idle_gap;
        input integer bit_times;
        begin
            uart_rxd = 1'b1;
            #(UART_BIT_PERIOD_NS * bit_times);
        end
    endtask


    initial begin
        #(UART_BIT_PERIOD_NS * (TOTAL_BYTES * 30 + 2500));
        $display("[TIMEOUT] Simulation timed out at %0t ns", $time);
        $display("Pass=%0d Fail=%0d Packets=%0d", pass_count, fail_count, packet_count);
        $display("TX FIFO overflow=%0b RX FIFO overflow=%0b CRC error=%0b",
                 tx_fifo_overflow, rx_fifo_overflow, crc_error_sticky);
        $finish;
    end

    initial begin
        uart_clk   = 1'b0;
        serdes_clk = 1'b0;
        rst_n      = 1'b0;
        uart_rxd   = 1'b1;

        pass_count   = 0;
        fail_count   = 0;
        packet_count = 0;
        random_seed  = 32'h1357_2468;

        expected_mem[0]  = 8'h00; // extremes and alternating patterns
        expected_mem[1]  = 8'hFF;
        expected_mem[2]  = 8'h55;
        expected_mem[3]  = 8'hAA;
        expected_mem[4]  = 8'hA5;
        expected_mem[5]  = 8'h5A;
        expected_mem[6]  = 8'h81;
        expected_mem[7]  = 8'h18;

        expected_mem[8]  = 8'hBC; // packet-control-looking payload values
        expected_mem[9]  = 8'h04;
        expected_mem[10] = 8'hB6;
        expected_mem[11] = 8'h76;

        expected_mem[12] = 8'h01; // walking ones
        expected_mem[13] = 8'h02;
        expected_mem[14] = 8'h04;
        expected_mem[15] = 8'h08;
        expected_mem[16] = 8'h10;
        expected_mem[17] = 8'h20;
        expected_mem[18] = 8'h40;
        expected_mem[19] = 8'h80;

        expected_mem[20] = 8'hFE; // walking zeros
        expected_mem[21] = 8'hFD;
        expected_mem[22] = 8'hFB;
        expected_mem[23] = 8'hF7;
        expected_mem[24] = 8'hEF;
        expected_mem[25] = 8'hDF;
        expected_mem[26] = 8'hBF;
        expected_mem[27] = 8'h7F;

        expected_mem[28] = 8'h33; // nibble and byte-lane patterns
        expected_mem[29] = 8'hCC;
        expected_mem[30] = 8'h0F;
        expected_mem[31] = 8'hF0;
        expected_mem[32] = 8'h99;
        expected_mem[33] = 8'h66;
        expected_mem[34] = 8'h3C;
        expected_mem[35] = 8'hC3;

        expected_mem[36] = 8'h12; // ordered byte pattern
        expected_mem[37] = 8'h34;
        expected_mem[38] = 8'h56;
        expected_mem[39] = 8'h78;

        for (init_idx = NUM_DIRECTED_BYTES; init_idx < TOTAL_BYTES; init_idx = init_idx + 1) begin
            rand_byte = $random(random_seed);
            expected_mem[init_idx] = rand_byte;
        end

        repeat (20) @(posedge uart_clk);
        rst_n = 1'b1;

        repeat (8) @(posedge uart_clk);
        repeat (16) @(posedge serdes_clk);

        $display("\n====================================================");
        $display(" SOC TOP FULL SYSTEM TEST");
        $display(" Path: UART RX -> FIFO -> FRAMER -> SERDES -> DEFRAMER -> FIFO -> UART TX");
        $display(" UART clock        : 50 MHz");
        $display(" SERDES clock      : 200 MHz");
        $display(" UART prescale     : %0d", UART_PRESCALE);
        $display(" UART bit period   : %0d ns", UART_BIT_PERIOD_NS);
        $display(" Payload size      : %0d bytes per packet", PAYLOAD_LENGTH);
        $display(" Directed bytes    : %0d", NUM_DIRECTED_BYTES);
        $display(" Random bytes      : %0d", NUM_RANDOM_BYTES);
        $display(" Total bytes       : %0d", TOTAL_BYTES);
        $display("====================================================\n");

        for (send_idx = 0; send_idx < TOTAL_BYTES; send_idx = send_idx + 1) begin
            $display("[SEND] @ %0t ns: UART input byte[%0d] = %02h", $time, send_idx, expected_mem[send_idx]);
            uart_send_byte(expected_mem[send_idx]);

            if ((send_idx % PAYLOAD_LENGTH) == (PAYLOAD_LENGTH - 1))
                uart_idle_gap(3);
            else if ((send_idx % 7) == 3)
                uart_idle_gap(1);
        end
    end

    initial begin
        wait (rst_n == 1'b1);
        repeat (20) @(posedge uart_clk);

        for (recv_idx = 0; recv_idx < TOTAL_BYTES; recv_idx = recv_idx + 1) begin
            uart_receive_byte(received_byte);

            if (received_byte === expected_mem[recv_idx]) begin
                pass_count = pass_count + 1;
                $display("[PASS] @ %0t ns: byte[%0d] expected=%02h received=%02h",
                         $time, recv_idx, expected_mem[recv_idx], received_byte);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] @ %0t ns: byte[%0d] expected=%02h received=%02h",
                         $time, recv_idx, expected_mem[recv_idx], received_byte);
            end
        end

        #(UART_BIT_PERIOD_NS * 8);

        $display("\n====================================================");
        $display(" SOC TOP TEST SUMMARY");
        $display("====================================================");
        $display("Pass count        : %0d", pass_count);
        $display("Fail count        : %0d", fail_count);
        $display("Packet count      : %0d", packet_count);
        $display("Expected packets  : %0d", EXPECTED_PACKETS);
`ifdef GATE_LEVEL_SIM
        $display("Framer bytes      : N/A for powered netlist simulation");
        $display("SERDES RX bytes   : N/A for powered netlist simulation");
        $display("Payload bytes     : N/A for powered netlist simulation");
        $display("CRC error pulses  : N/A for powered netlist simulation");
`else
        $display("Framer bytes      : %0d / %0d", framer_accept_count, EXPECTED_FRAME_BYTES);
        $display("SERDES RX bytes   : %0d / %0d", serdes_rx_count, EXPECTED_FRAME_BYTES);
        $display("Payload bytes     : %0d / %0d", payload_valid_count, TOTAL_BYTES);
        $display("CRC error pulses  : %0d", crc_error_count);
`endif
        $display("TX FIFO overflow  : %0b", tx_fifo_overflow);
        $display("RX FIFO overflow  : %0b", rx_fifo_overflow);
        $display("CRC error sticky  : %0b", crc_error_sticky);
        $display("TX FIFO full      : %0b", tx_fifo_full);
        $display("RX FIFO full      : %0b", rx_fifo_full);
        $display("TX FIFO full seen : %0d", tx_fifo_full_seen);
        $display("RX FIFO full seen : %0d", rx_fifo_full_seen);
        $display("TX FIFO empty seen: %0d", tx_fifo_empty_seen);
        $display("RX FIFO empty seen: %0d", rx_fifo_empty_seen);

`ifdef GATE_LEVEL_SIM
        if ((fail_count == 0) &&
            (packet_count == EXPECTED_PACKETS) &&
            (tx_fifo_overflow == 1'b0) &&
            (rx_fifo_overflow == 1'b0) &&
            (crc_error_sticky == 1'b0)) begin
            $display("FINAL STATUS      : PASS");
        end else begin
            $display("FINAL STATUS      : FAIL");
        end
`else
        if ((fail_count == 0) &&
            (packet_count == EXPECTED_PACKETS) &&
            (framer_accept_count == EXPECTED_FRAME_BYTES) &&
            (serdes_rx_count == EXPECTED_FRAME_BYTES) &&
            (payload_valid_count == TOTAL_BYTES) &&
            (crc_error_count == 0) &&
            (tx_fifo_overflow == 1'b0) &&
            (rx_fifo_overflow == 1'b0) &&
            (crc_error_sticky == 1'b0)) begin
            $display("FINAL STATUS      : PASS");
        end else begin
            $display("FINAL STATUS      : FAIL");
        end
`endif

        $display("====================================================\n");
        $finish;
    end

endmodule
