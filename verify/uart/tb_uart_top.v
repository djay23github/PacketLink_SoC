`timescale 1ns / 1ps
/* verilator lint_off WIDTHTRUNC */
module tb_uart_top;

// Parameters

localparam CLK_PERIOD = 20; // 50 MHz
localparam PRESCALE = 54;

reg clk;
reg rst_n;

reg uart_rxd;
wire uart_txd;

wire [7:0] rx_data;
wire rx_valid;

reg [7:0] tx_data;
reg tx_valid;
wire tx_ready;

// inout VPWR;
// inout VGND;


assign uart_rxd = uart_txd; // Loopback for testing

integer total_passes;
integer total_fails;

integer NUM_DIRECTED_TESTS = 16;
integer NUM_BURST_TESTS = 32;
integer NUM_RANDOM_TESTS = 50;

integer unique_values;
integer i;
reg seen_values [0:255];

reg [7:0] directed_tests [0:15];

reg [7:0] random_test_data;

uart_top #(.PRESCALE(PRESCALE))
        dut (.clk(clk),
             .rst_n(rst_n),
             .uart_rxd(uart_rxd),
             .uart_txd(uart_txd),
             .rx_data(rx_data),
             .rx_valid(rx_valid),
             .tx_data(tx_data),
             .tx_valid(tx_valid),
             .tx_ready(tx_ready)
        );

//  UART Netlist DUT
// uart_top    netdut (
//              .clk(clk),
//              .rst_n(rst_n),
//              .uart_rxd(uart_rxd),
//              .uart_txd(uart_txd),
//              .rx_data(rx_data),
//              .rx_valid(rx_valid),
//              .tx_data(tx_data),
//              .tx_valid(tx_valid),
//              .tx_ready(tx_ready), 
//              .VPWR(VPWR),
//              .VGND(VGND)
//         );

always #(CLK_PERIOD/2) clk = ~clk;

// Monitor for idle state and errors

// assign VPWR = 1'b1;
// assign VGND = 1'b0;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n && !tx_valid && tx_ready) begin
        if(uart_txd !== 1'b1) begin
            $display("[ERROR] @ %0t | UART TXD should be idle (1) when not transmitting. Got: %b", $time, uart_txd);
        end
    end
end

initial begin 
 directed_tests[0] = 8'h00;
 directed_tests[1] = 8'hFF;
 directed_tests[2] = 8'hAA;
 directed_tests[3] = 8'h55;
 directed_tests[4] = 8'h0F;
 directed_tests[5] = 8'hF0;
 directed_tests[6] = 8'hDE;
 directed_tests[7] = 8'hAD;
 directed_tests[8] = 8'hBE;
 directed_tests[9] = 8'hEF;
 directed_tests[10] = 8'h01;
 directed_tests[11] = 8'h80;
 directed_tests[12] = 8'h7F;
 directed_tests[13] = 8'hFE;
 directed_tests[14] = 8'hC3;
 directed_tests[15] = 8'h3C;
end

initial begin
    for(i=0; i<256; i++) seen_values[i] = 1'b0;
end

// UART TX Driver

task uart_send_byte(input [7:0] data);
begin
    @(posedge clk);
    while (!tx_ready) @(posedge clk); // Wait until DUT is ready
    tx_data = data;
    tx_valid = 1;
    @(posedge clk);
    tx_valid = 0;

    if(seen_values[data]) begin
        $display("[WARNING] @ %0t | Byte %02h has already been sent before.", $time, data);
    end else begin
        seen_values[data] = 1'b1;
        unique_values = unique_values + 1;
    end

    $display("[TX] @ %0t | Sent byte: %02h", $time, data);
end
endtask 

// UART RX Checker

task  uart_expected_byte(input [7:0] expected);
begin
    wait(rx_valid);
    @(posedge clk);
    if(rx_data !== expected) begin
        $display("[RX] @ %0t | Expected byte: %02h, Got: %02h", $time, expected, rx_data);
        total_fails = total_fails + 1;
    end else begin
        $display("[RX] @ %0t | Received expected byte: %02h", $time, expected);
        total_passes = total_passes + 1;
    end
end
endtask

// Start bit verification

task uart_verify_start_bit;
begin
    wait(uart_txd === 0);
    $display("[INFO] @ %0t | Detected start bit (TXD went low)", $time);
end
endtask

// Stop bit verification

task uart_verify_stop_bit;
begin
    wait(uart_txd === 1);
    $display("[INFO] @ %0t | Detected stop bit (TXD went high)", $time);
end
endtask

//--------------------------------------------------------
// Main Test Sequence
//--------------------------------------------------------

initial begin

    //----------------------------------------------------
    // Initialization
    //----------------------------------------------------

    clk = 1'b0;
    rst_n = 1'b0;

    tx_data  = 8'h00;
    tx_valid = 1'b0;

    total_passes   = 0;
    total_fails   = 0;

    unique_values = 0;

    //----------------------------------------------------
    // Reset
    //----------------------------------------------------

    // repeat (10) @(posedge clk);
    #10;
    rst_n = 1'b1;

    $display("\n================================================");
    $display(" UART VERIFICATION TESTBENCH ");
    $display("================================================");

    $display("Clock Frequency : 50 MHz");
    $display("Baud Rate       : 115200");
    $display("Prescale        : 54");

    $display("================================================\n");

    //----------------------------------------------------
    // Directed Tests
    //----------------------------------------------------

    $display("[INFO] Running directed tests...\n");

    for (i = 0; i < NUM_DIRECTED_TESTS; i = i + 1) begin
        fork
            begin
                uart_send_byte(directed_tests[i]);
            end
            begin
                uart_verify_start_bit;
            end

        join
        uart_expected_byte(directed_tests[i]);
        uart_verify_stop_bit;
    end

    //----------------------------------------------------
    // Burst Traffic Test
    //----------------------------------------------------

    $display("\n[INFO] Running burst traffic test...\n");

    for (i = 0; i < NUM_BURST_TESTS; i = i + 1) begin
        uart_send_byte(i[7:0]);
        uart_expected_byte(i[7:0]);
    end

    //----------------------------------------------------
    // Randomized Tests
    //----------------------------------------------------

    $display("\n[INFO] Running randomized tests...\n");
    for (i = 0; i < NUM_RANDOM_TESTS; i = i + 1) begin
        random_test_data = $random;
        uart_send_byte(random_test_data);
        uart_expected_byte(random_test_data);
    end

    //----------------------------------------------------
    // Final Summary
    //----------------------------------------------------

    $display("\n================================================");
    $display(" UART VERIFICATION SUMMARY");
    $display("================================================");

    $display("Total Tests Executed : %0d", NUM_DIRECTED_TESTS + NUM_BURST_TESTS + NUM_RANDOM_TESTS);
    $display("Total Pass           : %0d", total_passes);
    $display("Total Fail           : %0d", total_fails);

    $display("Unique Byte Coverage : %0d / 256",
                unique_values);

    $display("Coverage Percentage  : %0.2f%%",
                (unique_values * 100.0) / 256.0);

    if (total_fails == 0)
        $display("FINAL STATUS : ALL TESTS PASSED");
    else
        $display("FINAL STATUS : FAILURES DETECTED");
    $display("================================================\n");
    $finish;
end

initial begin
    $dumpfile("verify/tb_uart_top.vcd");
    $dumpvars(0, tb_uart_top);
end

endmodule
