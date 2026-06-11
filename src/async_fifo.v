/* verilator lint_off WIDTHEXPAND */
//============================================================
// Dual-clock Asynchronous FIFO
// Verilog-2001 style
//
// Notes:
// - DEPTH = 2**ADDR_WIDTH
// - Registered read output: dout updates on rd_clk when rd_en && !empty
// - full and empty are registered in their respective clock domains
// - Gray-coded pointers are synchronized across clock domains
//============================================================

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    //--------------------------------------------------
    // Write Clock Domain
    //--------------------------------------------------
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    output wire                  full,

    //--------------------------------------------------
    // Read Clock Domain
    //--------------------------------------------------
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] dout,
    output wire                  empty
);

    //--------------------------------------------------
    // Local Parameters
    //--------------------------------------------------
    localparam DEPTH = (1 << ADDR_WIDTH);

    //--------------------------------------------------
    // Memory
    //--------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    //--------------------------------------------------
    // Binary and Gray Pointers
    // One extra MSB is used to distinguish full vs empty.
    //--------------------------------------------------
    reg  [ADDR_WIDTH:0] wr_ptr_bin;
    reg  [ADDR_WIDTH:0] wr_ptr_gray;

    reg  [ADDR_WIDTH:0] rd_ptr_bin;
    reg  [ADDR_WIDTH:0] rd_ptr_gray;

    wire [ADDR_WIDTH:0] wr_ptr_bin_next;
    wire [ADDR_WIDTH:0] wr_ptr_gray_next;

    wire [ADDR_WIDTH:0] rd_ptr_bin_next;
    wire [ADDR_WIDTH:0] rd_ptr_gray_next;

    //--------------------------------------------------
    // Cross-domain synchronized Gray pointers
    //--------------------------------------------------
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync2;

    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1;
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync2;

    //--------------------------------------------------
    // Registered status flags
    //--------------------------------------------------
    reg full_reg;
    reg empty_reg;

    //--------------------------------------------------
    // Accepted read/write enables
    //--------------------------------------------------
    wire wr_inc;
    wire rd_inc;

    assign wr_inc = wr_en && !full_reg;
    assign rd_inc = rd_en && !empty_reg;

    //--------------------------------------------------
    // Pointer next-state logic
    //--------------------------------------------------
    assign wr_ptr_bin_next = wr_ptr_bin + {{ADDR_WIDTH{1'b0}}, wr_inc};
    assign rd_ptr_bin_next = rd_ptr_bin + {{ADDR_WIDTH{1'b0}}, rd_inc};

    assign wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
    assign rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    //--------------------------------------------------
    // Full / Empty next-state logic
    //--------------------------------------------------
    wire full_next;
    wire empty_next;

    assign full_next =
        (wr_ptr_gray_next ==
        {
            ~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
             rd_ptr_gray_sync2[ADDR_WIDTH-2:0]
        });

    assign empty_next =
        (rd_ptr_gray_next == wr_ptr_gray_sync2);

    //--------------------------------------------------
    // Write Pointer / Memory Write / Full Flag
    //--------------------------------------------------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= {ADDR_WIDTH+1{1'b0}};
            wr_ptr_gray <= {ADDR_WIDTH+1{1'b0}};
            full_reg    <= 1'b0;
        end
        else begin
            if (wr_inc) begin
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= din;
                wr_ptr_bin  <= wr_ptr_bin_next;
                wr_ptr_gray <= wr_ptr_gray_next;
            end

            full_reg <= full_next;
        end
    end

    //--------------------------------------------------
    // Read Pointer / Memory Read / Empty Flag
    //--------------------------------------------------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= {ADDR_WIDTH+1{1'b0}};
            rd_ptr_gray <= {ADDR_WIDTH+1{1'b0}};
            empty_reg   <= 1'b1;
            dout        <= {DATA_WIDTH{1'b0}};
        end
        else begin
            if (rd_inc) begin
                dout <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
                rd_ptr_bin  <= rd_ptr_bin_next;
                rd_ptr_gray <= rd_ptr_gray_next;
            end

            empty_reg <= empty_next;
        end
    end

    //--------------------------------------------------
    // Synchronize Read Pointer into Write Domain
    //--------------------------------------------------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= {ADDR_WIDTH+1{1'b0}};
            rd_ptr_gray_sync2 <= {ADDR_WIDTH+1{1'b0}};
        end
        else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    //--------------------------------------------------
    // Synchronize Write Pointer into Read Domain
    //--------------------------------------------------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= {ADDR_WIDTH+1{1'b0}};
            wr_ptr_gray_sync2 <= {ADDR_WIDTH+1{1'b0}};
        end
        else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    //--------------------------------------------------
    // Outputs
    //--------------------------------------------------
    assign full  = full_reg;
    assign empty = empty_reg;

endmodule
