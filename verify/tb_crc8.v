`timescale 1ns/1ps
/* verilator lint_off WIDTHTRUNC    */
module tb_crc8;

    reg  [7:0] data_in;
    reg  [7:0] crc_in;
    wire [7:0] crc_out;

    integer i;
    integer pass_count;
    integer fail_count;

    reg [7:0] expected_crc;

    crc8 dut (
        .data_in (data_in),
        .crc_in  (crc_in),
        .crc_out (crc_out)
    );

    function [7:0] crc8_ref;
        input [7:0] data;
        input [7:0] crc;
        begin
            crc8_ref[0] = crc[0] ^ crc[6] ^ crc[7] ^ data[0] ^ data[6] ^ data[7];
            crc8_ref[1] = crc[0] ^ crc[1] ^ crc[6] ^ data[0] ^ data[1] ^ data[6];
            crc8_ref[2] = crc[0] ^ crc[1] ^ crc[2] ^ crc[6] ^ data[0] ^ data[1] ^ data[2] ^ data[6];
            crc8_ref[3] = crc[1] ^ crc[2] ^ crc[3] ^ crc[7] ^ data[1] ^ data[2] ^ data[3] ^ data[7];
            crc8_ref[4] = crc[2] ^ crc[3] ^ crc[4] ^ data[2] ^ data[3] ^ data[4];
            crc8_ref[5] = crc[3] ^ crc[4] ^ crc[5] ^ data[3] ^ data[4] ^ data[5];
            crc8_ref[6] = crc[4] ^ crc[5] ^ crc[6] ^ data[4] ^ data[5] ^ data[6];
            crc8_ref[7] = crc[5] ^ crc[6] ^ crc[7] ^ data[5] ^ data[6] ^ data[7];
        end
    endfunction

    task check_crc;
        input [7:0] data;
        input [7:0] crc;
        begin
            data_in = data;
            crc_in  = crc;
            #1;
            expected_crc = crc8_ref(data, crc);

            if (crc_out !== expected_crc) begin
                fail_count = fail_count + 1;
                $display("[FAIL] data=%02h crc_in=%02h expected=%02h got=%02h",
                         data, crc, expected_crc, crc_out);
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] data=%02h crc_in=%02h expected=%02h crc_out=%02h",
                         data, crc, expected_crc, crc_out);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        data_in = 8'h00;
        crc_in  = 8'h00;

        $display("\n========================================");
        $display(" CRC8 TESTBENCH STARTED");
        $display("========================================\n");

        check_crc(8'h00, 8'h00);
        check_crc(8'hFF, 8'h00);
        check_crc(8'hBC, 8'h00);
        check_crc(8'h04, 8'h00);
        check_crc(8'hAA, 8'h55);
        check_crc(8'h55, 8'hAA);
        check_crc(8'hA5, 8'h3C);
        check_crc(8'h5A, 8'hC3);

        for (i = 0; i < 100; i = i + 1) begin
            check_crc($random, $random);
        end

        $display("\n========================================");
        $display(" CRC8 TEST SUMMARY");
        $display(" Pass : %0d", pass_count);
        $display(" Fail : %0d", fail_count);
        if (fail_count == 0)
            $display(" STATUS : PASS");
        else
            $display(" STATUS : FAIL");
        $display("========================================\n");

        $finish;
    end

    initial begin
        $dumpfile("tb_crc8.vcd");
        $dumpvars(0, tb_crc8);
    end

endmodule
