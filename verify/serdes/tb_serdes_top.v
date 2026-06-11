`timescale 1ns/1ps
/* verilator lint_off WIDTHTRUNC */

/* The testbench drives the SERDES valid/ready input handshake, then checks
   the looped-back byte when rx_valid is asserted. */


module tb_serdes_top;

    localparam integer NUM_DIRECTED_TESTS = 12;
    localparam integer NUM_RANDOM_TESTS   = 100;

    reg         clk;
    reg         rst_n;
    reg  [7:0]  parallel_data_in;
    reg         tx_valid;
    wire [7:0]  parallel_data_out;

    reg  [7:0]  test_vectors [0:NUM_DIRECTED_TESTS-1];
    reg  [7:0]  random_data;

    integer     i;
    integer     directed_pass_count;
    integer     random_pass_count;

    wire tx_serial;
    wire rx_serial;

    wire tx_done;
    wire rx_valid;


    // inout VPWR;
    // inout VGND; 


    serdes_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .parallel_data_in(parallel_data_in),
        .tx_valid(tx_valid),
        .parallel_data_out(parallel_data_out),
        .tx_serial(tx_serial),  
        .rx_serial(rx_serial),
        //     .VPWR(VPWR),
        //     .VGND(VGND),
        .tx_done(tx_done),
        .rx_valid(rx_valid)
    );


    always #2.5 clk = ~clk;


    // assign VPWR = 1'b1;
    // assign VGND = 1'b0;


    assign rx_serial = tx_serial; // Loopback for testing

    initial begin
        test_vectors[0] = 8'h00;
        test_vectors[1] = 8'h01;
        test_vectors[2] = 8'h7F;
        test_vectors[3] = 8'h80;
        test_vectors[4] = 8'hFF;
        test_vectors[5] = 8'hAA;
        test_vectors[6] = 8'h55;
        test_vectors[7] = 8'hA5;
        test_vectors[8] = 8'h5A;
        test_vectors[9] = 8'h3C;
        test_vectors[10] = 8'hC3;
        test_vectors[11] = 8'h81;
    end

    task send_and_check;
        input [7:0] expected_data;
        output reg pass;
        begin
            wait (tx_done == 1'b1);
            @(posedge clk);
            parallel_data_in = expected_data;
            tx_valid = 1'b1;
            @(posedge clk);
            tx_valid = 1'b0;

            wait (rx_valid == 1'b1);
            #1;
            if (parallel_data_out !== expected_data) begin
                $display("[ERROR] @ %0t ns: expected %02h, got %02h", $time, expected_data, parallel_data_out);
                pass = 1'b0;
            end
            else begin
                $display("[PASS]  @ %0t ns: input %02h -> output %02h",$time, expected_data, parallel_data_out);
                pass = 1'b1;
            end
            
        end
    endtask

    reg status;
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        status = 1'b0;
 
        parallel_data_in = 8'h00;
        tx_valid = 1'b0;
        random_data = 8'h00;
        directed_pass_count = 0;
        random_pass_count = 0;


        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        $display("[INFO] This SERDES module does not include RD/ER control");
        $display("[INFO]: Starting directed SerDes loopback tests...");
        
        for (i = 0; i < NUM_DIRECTED_TESTS; i = i + 1) begin
            send_and_check(test_vectors[i], status);

            if (status) begin
                directed_pass_count = directed_pass_count + 1;
            end
        end

        $display("[INFO]: Starting randomized SerDes loopback tests...");
        for (i = 0; i < NUM_RANDOM_TESTS; i = i + 1) begin
            random_data = $random;

            send_and_check(random_data, status);
            if (status) begin
                random_pass_count = random_pass_count + 1;
            end
        end

        if(directed_pass_count == NUM_DIRECTED_TESTS && random_pass_count == NUM_RANDOM_TESTS) begin
           
            if(tx_done || rx_valid) begin
                $display("\n[INFO]: All directed and random tests passed successfully!");
            end
            else begin
                $display("\n[ERROR]: Some tests failed. Please review the results above for details.");
            end
        end

        

        $display("\n[INFO]: SERDES Test case results:");
        $display("--------------------------------------------------");
        $display("Directed tests passed   : %0d / %0d", directed_pass_count, NUM_DIRECTED_TESTS);
        $display("Random tests passed     : %0d / %0d", random_pass_count, NUM_RANDOM_TESTS);
        $display("Total tests passed   : %0d / %0d", directed_pass_count + random_pass_count, NUM_DIRECTED_TESTS + NUM_RANDOM_TESTS);
        $display("--------------------------------------------------");
        $finish;
    end

endmodule
