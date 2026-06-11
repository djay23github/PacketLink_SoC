
/* verilator lint_off WIDTHTRUNC */
`timescale 1ns/100ps

module tb_packet_framer;

    parameter PAYLOAD_LENGTH = 4;

    reg clk;
    reg rst_n;

    reg  [7:0] fifo_dout;
    wire        fifo_empty;
    reg [4:0] fifo_count;
    wire       fifo_rd_en;

    wire [7:0] serdes_data;
    wire       serdes_valid;
    reg        serdes_ready;

    integer i;
    integer pass_count;
    integer fail_count;
    integer out_index;
    integer rd_index;
    integer check_index;

    reg [7:0] fifo_mem [0:15];
    reg [7:0] expected_packet [0:15];
    reg [7:0] captured_packet [0:15];

    reg [7:0] crc_calc;
    reg [7:0] crc_tmp_data;
    reg [7:0] crc_tmp_in;
    wire [7:0] crc_tmp_out;

    packet_framer #(
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .fifo_dout    (fifo_dout),
        .fifo_empty   (fifo_empty),
        .fifo_rd_en   (fifo_rd_en),
        .serdes_data  (serdes_data),
        .serdes_valid (serdes_valid),
        .serdes_ready (serdes_ready)
    );

    crc8 u_crc_model (
        .data_in (crc_tmp_data),
        .crc_in  (crc_tmp_in),
        .crc_out (crc_tmp_out)
    );

    always #2.5 clk = ~clk; // 200 MHz

    // Registered-read FIFO model: rd_en in cycle N, dout updates in cycle N+1.
    assign fifo_empty = (fifo_count == 0);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_dout  <= 8'h00;
            rd_index   <= 0;
            fifo_count <= 0;
        end else begin
            if (fifo_rd_en && !fifo_empty) begin
                fifo_dout  <= fifo_mem[rd_index];
                rd_index   <= rd_index + 1;
                fifo_count <= fifo_count - 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (serdes_valid) begin
            captured_packet[out_index] <= serdes_data;
            $display("[OUT] @ %0t ns packet[%0d]=%02h", $time, out_index, serdes_data);
            out_index <= out_index + 1;
        end
    end

    task crc_update;
        input [7:0] data;
        begin
            crc_tmp_data = data;
            crc_tmp_in   = crc_calc;
            #5;
            crc_calc = crc_tmp_out;
        end
    endtask

    task build_expected_packet;
        begin
            crc_calc = 8'h00;

            expected_packet[0] = 8'hBC;
            expected_packet[1] = PAYLOAD_LENGTH[7:0];

            crc_update(PAYLOAD_LENGTH[7:0]);

            for (i = 0; i < PAYLOAD_LENGTH; i = i + 1) begin
                expected_packet[i+2] = fifo_mem[i];
                crc_update(fifo_mem[i]);
            end

            expected_packet[2+PAYLOAD_LENGTH] = crc_calc;
        end
    endtask

    task check_packet;
        begin
            for (check_index = 0; check_index < PAYLOAD_LENGTH + 3; check_index = check_index + 1) begin
                if (captured_packet[check_index] !== expected_packet[check_index]) begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] packet[%0d] expected=%02h got=%02h",
                             check_index, expected_packet[check_index], captured_packet[check_index]);
                end else begin
                    pass_count = pass_count + 1;
                    $display("[PASS] packet[%0d]=%02h", check_index, captured_packet[check_index]);
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        fifo_dout = 8'h00;
        fifo_count = 5'd0;
        serdes_ready = 1'b1;
        pass_count = 0;
        fail_count = 0;
        out_index = 0;
        rd_index = 0;
        crc_calc = 8'h00;
        crc_tmp_data = 8'h00;
        crc_tmp_in = 8'h00;

        fifo_mem[0] = $random;
        fifo_mem[1] = $random;
        fifo_mem[2] = $random;
        fifo_mem[3] = $random;

        for (i = 0; i < 16; i = i + 1) begin
            expected_packet[i] = 8'h00;
            captured_packet[i] = 8'h00;
        end

        build_expected_packet();

        $display("\n===========================================================");
        $display(" PACKET FRAMER TESTBENCH STARTED");
        $display(" Registered-read FIFO model is used");
        $display(" Expected packet: 'SOP' 'PAYLOAD_LEN' '4-byte DATA' 'CRC'");
        $display("===========================================================\n");

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        fifo_count = PAYLOAD_LENGTH; // Make all payload bytes available in FIFO at once
        $display("[INFO] Payload bytes written to FIFO, count=%0d", fifo_count);


        #100;

        if (out_index != PAYLOAD_LENGTH + 3) begin
            fail_count = fail_count + 1;
            $display("[FAIL] Expected %0d output bytes, captured %0d", PAYLOAD_LENGTH+3, out_index);
        end else begin
            pass_count = pass_count + 1;
            $display("[PASS] Captured expected packet byte count: %0d", out_index);
        end

        check_packet();

        $display("\n========================================");
        $display(" PACKET FRAMER TEST SUMMARY");
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
