`timescale 1ns/100ps
/* verilator lint_off INITIALDLY */
/* verilator lint_off WIDTHTRUNC    */
module tb_async_fifo;

    //--------------------------------------------------
    // Parameters
    //--------------------------------------------------
    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 4;
    parameter DEPTH      = (1 << ADDR_WIDTH);

    //--------------------------------------------------
    // DUT Signals
    //--------------------------------------------------
    reg                  wr_clk;
    reg                  rd_clk;
    reg                  wr_rst_n;
    reg                  rd_rst_n;

    reg                  wr_en;
    reg  [DATA_WIDTH-1:0] din;
    wire                 full;

    reg                  rd_en;
    wire [DATA_WIDTH-1:0] dout;
    wire                 empty;

    //--------------------------------------------------
    // Scoreboard
    //--------------------------------------------------
    reg [DATA_WIDTH-1:0] exp_mem [0:4095];
    integer wr_exp_idx;
    integer rd_exp_idx;
    integer pass_count;
    integer fail_count;
    integer total_reads;
    integer i;

    //--------------------------------------------------
    // DUT
    //--------------------------------------------------
    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),
        .din      (din),
        .full     (full),

        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),
        .dout     (dout),
        .empty    (empty)
    );

    //--------------------------------------------------
    // Clocks
    // Write clock: 50 MHz
    // Read clock : 200 MHz
    //--------------------------------------------------
    always #10  wr_clk = ~wr_clk;
    always #2.5 rd_clk = ~rd_clk;

    //--------------------------------------------------
    // Reset Task
    //--------------------------------------------------
    task apply_reset;
        begin
            wr_rst_n = 1'b0;
            rd_rst_n = 1'b0;
            wr_en    = 1'b0;
            rd_en    = 1'b0;
            din      = {DATA_WIDTH{1'b0}};

            repeat (5) @(posedge wr_clk);
            repeat (5) @(posedge rd_clk);

            wr_rst_n = 1'b1;
            rd_rst_n = 1'b1;

            // Allow synchronized pointers and registered flags to settle.
            repeat (6) @(posedge wr_clk);
            repeat (6) @(posedge rd_clk);
        end
    endtask

    //--------------------------------------------------
    // Write one byte
    //--------------------------------------------------
    task fifo_write;
        input [DATA_WIDTH-1:0] data;
        begin
            @(posedge wr_clk);
            while (full) begin
                @(posedge wr_clk);
            end

            din   <= data;
            wr_en <= 1'b1;

            @(posedge wr_clk);
            wr_en <= 1'b0;
            din   <= {DATA_WIDTH{1'b0}};

            exp_mem[wr_exp_idx] = data;
            wr_exp_idx = wr_exp_idx + 1;

            $display("[WRITE] @ %0t ns : data = %02h", $time, data);
        end
    endtask

    //--------------------------------------------------
    // Read one byte and compare
    // FIFO has registered read output:
    // rd_en accepted on rd_clk edge, dout updates after that edge.
    //--------------------------------------------------
    task fifo_read_check;
        reg [DATA_WIDTH-1:0] expected;
        begin
            @(posedge rd_clk);
            while (empty) begin
                @(posedge rd_clk);
            end

            expected = exp_mem[rd_exp_idx];

            rd_en <= 1'b1;
            @(posedge rd_clk);
            rd_en <= 1'b0;

            // Wait one delta/settle step after the read clock edge.
            #1;

            total_reads = total_reads + 1;

            if (dout !== expected) begin
                fail_count = fail_count + 1;
                $display("[FAIL]  @ %0t ns : expected %02h, got %02h", $time, expected, dout);
            end
            else begin
                pass_count = pass_count + 1;
                $display("[PASS]  @ %0t ns : read %02h", $time, dout);
            end

            rd_exp_idx = rd_exp_idx + 1;
        end
    endtask

    //--------------------------------------------------
    // Test: Directed write/read
    //--------------------------------------------------
    task run_directed_test;
        begin
            $display("\n[INFO] Directed write/read test");

            fifo_write(8'h00);
            fifo_write(8'hFF);
            fifo_write(8'hAA);
            fifo_write(8'h55);
            fifo_write(8'hA5);
            fifo_write(8'h5A);

            fifo_read_check;
            fifo_read_check;
            fifo_read_check;
            fifo_read_check;
            fifo_read_check;
            fifo_read_check;
        end
    endtask

    //--------------------------------------------------
    // Test: Fill FIFO and verify full behavior
    //--------------------------------------------------
    task run_full_test;
        begin
            $display("\n[INFO] Full flag test");

            for (i = 0; i < DEPTH; i = i + 1) begin
                fifo_write(i[7:0] + 8'h20);
            end

            // Give full flag one write-domain cycle to update if needed.
            @(posedge wr_clk);
            #1;

            if (full !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("[FAIL]  @ %0t ns : full flag not asserted after DEPTH writes", $time);
            end
            else begin
                pass_count = pass_count + 1;
                $display("[PASS]  @ %0t ns : full flag asserted", $time);
            end

            // Attempt extra write; it should be ignored.
            @(posedge wr_clk);
            din   <= 8'hEE;
            wr_en <= 1'b1;
            @(posedge wr_clk);
            wr_en <= 1'b0;
            din   <= 8'h00;

            for (i = 0; i < DEPTH; i = i + 1) begin
                fifo_read_check;
            end
        end
    endtask

    //--------------------------------------------------
    // Test: Empty flag behavior
    //--------------------------------------------------
    task run_empty_test;
        begin
            $display("\n[INFO] Empty flag test");

            // Allow empty to propagate in read domain after all reads.
            repeat (4) @(posedge rd_clk);
            #1;

            if (empty !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("[FAIL]  @ %0t ns : empty flag not asserted", $time);
            end
            else begin
                pass_count = pass_count + 1;
                $display("[PASS]  @ %0t ns : empty flag asserted", $time);
            end

            // Attempt read from empty; dout should not be checked/advanced.
            @(posedge rd_clk);
            rd_en <= 1'b1;
            @(posedge rd_clk);
            rd_en <= 1'b0;
        end
    endtask

    //--------------------------------------------------
    // Test: Interleaved random-ish traffic
    //--------------------------------------------------
    task run_interleaved_test;
        reg [7:0] value;
        begin
            $display("\n[INFO] Interleaved traffic test");

            for (i = 0; i < 22; i = i + 1) begin
                value = $random;
                fifo_write(value);

                if ((i % 3) == 2) begin
                    fifo_read_check;
                end
            end

            while (rd_exp_idx < wr_exp_idx) begin
                fifo_read_check;
            end
        end
    endtask

    //--------------------------------------------------
    // Main
    //--------------------------------------------------
    initial begin
        wr_clk = 1'b0;
        rd_clk = 1'b0;

        wr_exp_idx = 0;
        rd_exp_idx = 0;
        pass_count = 0;
        fail_count = 0;
        total_reads = 0;

        apply_reset;

        $display("\n==============================================");
        $display(" ASYNC FIFO TESTBENCH STARTED");
        $display(" DATA_WIDTH = %0d", DATA_WIDTH);
        $display(" ADDR_WIDTH = %0d", ADDR_WIDTH);
        $display(" DEPTH      = %0d", DEPTH);
        $display("==============================================");

        run_directed_test;
        run_full_test;
        run_empty_test;
        run_interleaved_test;

        $display("\n==============================================");
        $display(" ASYNC FIFO TEST SUMMARY");
        $display(" Total reads : %0d", total_reads);
        $display(" Pass count  : %0d", pass_count);
        $display(" Fail count  : %0d", fail_count);

        if (fail_count == 0)
            $display(" FINAL STATUS: PASS");
        else
            $display(" FINAL STATUS: FAIL");

        $display("==============================================\n");

        $finish;
    end

endmodule
