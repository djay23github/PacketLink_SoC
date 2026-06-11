`timescale 1ns/100ps

module tb_packet_deframer;

    parameter MAX_PAYLOAD_LENGTH = 16;

    reg clk;
    reg rst_n;

    reg  [7:0] serdes_data;
    reg        serdes_valid;

    wire [7:0] payload_data;
    wire       payload_valid;
    wire       packet_valid;
    wire       crc_error;

    integer pass_count;
    integer fail_count;
    integer i;
    integer payload_index;

    reg [7:0] captured_payload [0:31];
    reg       packet_valid_seen;
    reg       crc_error_seen;

    reg [7:0] crc_calc;
    reg [7:0] crc_tmp_data;
    reg [7:0] crc_tmp_in;
    wire [7:0] crc_tmp_out;

    packet_deframer #(
        .MAX_PAYLOAD_LENGTH(MAX_PAYLOAD_LENGTH)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .serdes_data   (serdes_data),
        .serdes_valid  (serdes_valid),
        .payload_data  (payload_data),
        .payload_valid (payload_valid),
        .packet_valid  (packet_valid),
        .crc_error     (crc_error)
    );

    crc8 u_crc_model (
        .data_in (crc_tmp_data),
        .crc_in  (crc_tmp_in),
        .crc_out (crc_tmp_out)
    );

    always #2.5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_index     <= 0;
            packet_valid_seen <= 1'b0;
            crc_error_seen    <= 1'b0;
        end else begin
            if (payload_valid) begin
                captured_payload[payload_index] <= payload_data;
                $display("[PAYLOAD] @ %0t ns payload[%0d]=%02h", $time, payload_index, payload_data);
                payload_index <= payload_index + 1;
            end

            if (packet_valid) begin
                packet_valid_seen <= 1'b1;
                $display("[INFO] @ %0t ns packet_valid pulse", $time);
            end

            if (crc_error) begin
                crc_error_seen <= 1'b1;
                $display("[INFO] @ %0t ns crc_error pulse", $time);
            end
        end
    end

    task clear_monitors;
        begin
            payload_index     = 0;
            packet_valid_seen = 1'b0;
            crc_error_seen    = 1'b0;
            for (i = 0; i < 32; i = i + 1) begin
                captured_payload[i] = 8'h00;
            end
        end
    endtask

    task send_byte;
        input [7:0] data;
        begin
            @(negedge clk);
            serdes_data  = data;
            serdes_valid = 1'b1;
            @(negedge clk);
            serdes_valid = 1'b0;
            serdes_data  = 8'h00;
        end
    endtask

    task crc_update;
        input [7:0] data;
        begin
            crc_tmp_data = data;
            crc_tmp_in   = crc_calc;
            #1;
            crc_calc     = crc_tmp_out;
        end
    endtask

    task check_byte;
        input integer index;
        input [7:0] expected;
        begin
            if (captured_payload[index] !== expected) begin
                fail_count = fail_count + 1;
                $display("[FAIL] payload[%0d] expected=%02h got=%02h", index, expected, captured_payload[index]);
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] payload[%0d]=%02h", index, captured_payload[index]);
            end
        end
    endtask

    task test_good_packet;
        reg [7:0] crc;
        begin
            $display("\n[TEST] Good packet should emit payload after CRC passes");
            clear_monitors();

            crc_calc = 8'h00;
            crc_update(8'h04);
            crc_update(8'h11);
            crc_update(8'h22);
            crc_update(8'h33);
            crc_update(8'h44);
            crc = crc_calc;

            send_byte(8'hBC);
            send_byte(8'h04);
            send_byte(8'h11);
            send_byte(8'h22);
            send_byte(8'h33);
            send_byte(8'h44);
            send_byte(crc);

            repeat (10) @(posedge clk);

            if (!packet_valid_seen) begin
                fail_count = fail_count + 1;
                $display("[FAIL] packet_valid was not seen");
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] packet_valid seen");
            end

            if (crc_error_seen) begin
                fail_count = fail_count + 1;
                $display("[FAIL] crc_error should not assert for good packet");
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] crc_error not asserted");
            end

            if (payload_index != 4) begin
                fail_count = fail_count + 1;
                $display("[FAIL] expected 4 payload bytes, got %0d", payload_index);
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] emitted 4 payload bytes");
            end

            check_byte(0, 8'h11);
            check_byte(1, 8'h22);
            check_byte(2, 8'h33);
            check_byte(3, 8'h44);
        end
    endtask

    task test_bad_crc_packet;
        reg [7:0] crc;
        begin
            $display("\n[TEST] Bad CRC packet should drop payload");
            clear_monitors();

            crc_calc = 8'h00;
            crc_update(8'h04);
            crc_update(8'hAA);
            crc_update(8'hBB);
            crc_update(8'hCC);
            crc_update(8'hDD);
            crc = crc_calc ^ 8'hFF;

            send_byte(8'hBC);
            send_byte(8'h04);
            send_byte(8'hAA);
            send_byte(8'hBB);
            send_byte(8'hCC);
            send_byte(8'hDD);
            send_byte(crc);

            repeat (10) @(posedge clk);

            if (!crc_error_seen) begin
                fail_count = fail_count + 1;
                $display("[FAIL] crc_error was not seen for bad packet");
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] crc_error seen");
            end

            if (packet_valid_seen) begin
                fail_count = fail_count + 1;
                $display("[FAIL] packet_valid should not assert for bad CRC");
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] packet_valid not asserted");
            end

            if (payload_index != 0) begin
                fail_count = fail_count + 1;
                $display("[FAIL] bad CRC payload leaked: %0d bytes emitted", payload_index);
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] bad CRC payload was fully dropped");
            end
        end
    endtask

    task test_wrong_sop;
        begin
            $display("\n[TEST] Wrong SOP should be ignored");
            clear_monitors();

            send_byte(8'hAA);
            send_byte(8'h04);
            send_byte(8'h11);
            send_byte(8'h22);
            send_byte(8'h33);
            send_byte(8'h44);
            send_byte(8'h00);

            repeat (10) @(posedge clk);

            if (payload_index != 0 && packet_valid_seen) begin
                fail_count = fail_count + 1;
                $display("[FAIL] wrong SOP was decoded");
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] wrong SOP ignored");
            end
        end
    endtask

    initial begin
        clk          = 1'b0;
        rst_n        = 1'b0;
        serdes_data  = 8'h00;
        serdes_valid = 1'b0;

        pass_count = 0;
        fail_count = 0;
        crc_calc   = 8'h00;
        crc_tmp_data = 8'h00;
        crc_tmp_in   = 8'h00;

        clear_monitors();

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("\n========================================");
        $display(" PACKET DEFRAMER TEST STARTED");
        $display(" Bad CRC payload must not be emitted");
        $display("========================================");

        test_good_packet();
        test_bad_crc_packet();
        test_wrong_sop();

        $display("\n========================================");
        $display(" PACKET DEFRAMER TEST SUMMARY");
        $display(" Pass : %0d", pass_count);
        $display(" Fail : %0d", fail_count);
        if (fail_count == 0)
            $display(" STATUS : PASS");
        else
            $display(" STATUS : FAIL");
        $display("========================================\n");

        $finish;
    end

endmodule
