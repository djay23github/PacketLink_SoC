/* verilator lint_off WIDTHEXPAND */
module uart_rx #
(
    parameter DATA_WIDTH = 8
)
(
    input  wire                   clk,
    input  wire                   rst,

    /*
     * AXI output
     */
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,

    /*
     * UART interface
     */
    input  wire                   rxd,

    /*
     * Status
     */
    output wire                   busy,
    output wire                   overrun_error,
    output wire                   frame_error,

    /*
     * Configuration
     */
    input  wire [15:0]            prescale

);

reg [DATA_WIDTH-1:0] m_axis_tdata_reg;
reg m_axis_tvalid_reg;

reg rxd_reg;

reg busy_reg;
reg overrun_error_reg;
reg frame_error_reg;

reg [DATA_WIDTH-1:0] data_reg;
reg [18:0] prescale_reg;
reg [3:0] bit_cnt;

assign m_axis_tdata = m_axis_tdata_reg;
assign m_axis_tvalid = m_axis_tvalid_reg;

assign busy = busy_reg;
assign overrun_error = overrun_error_reg;
assign frame_error = frame_error_reg;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        m_axis_tdata_reg <= 0;
        m_axis_tvalid_reg <= 0;
        rxd_reg <= 1;
        prescale_reg <= 0;
        bit_cnt <= 0;
        busy_reg <= 0;
        overrun_error_reg <= 0;
        frame_error_reg <= 0;
    end else begin
        rxd_reg <= rxd;
        overrun_error_reg <= 0;
        frame_error_reg <= 0;

        if (m_axis_tvalid && m_axis_tready) begin
            m_axis_tvalid_reg <= 0;
        end

        if (prescale_reg > 0) begin
            prescale_reg <= prescale_reg - 1;
        end else if (bit_cnt > 0) begin
            if (bit_cnt > DATA_WIDTH+1) begin
                if (!rxd_reg) begin
                    bit_cnt <= bit_cnt - 1;
                    prescale_reg <= (prescale << 3)-1;
                end else begin
                    bit_cnt <= 0;
                    prescale_reg <= 0;
                end
            end else if (bit_cnt > 1) begin
                bit_cnt <= bit_cnt - 1;
                prescale_reg <= (prescale << 3)-1;
                data_reg <= {rxd_reg, data_reg[DATA_WIDTH-1:1]};
            end else if (bit_cnt == 1) begin
                bit_cnt <= bit_cnt - 1;
                if (rxd_reg) begin
                    m_axis_tdata_reg <= data_reg;
                    m_axis_tvalid_reg <= 1;
                    overrun_error_reg <= m_axis_tvalid_reg;
                end else begin
                    frame_error_reg <= 1;
                end
            end
        end else begin
            busy_reg <= 0;
            if (!rxd_reg) begin
                prescale_reg <= (prescale << 2)-2;
                bit_cnt <= DATA_WIDTH+2;
                data_reg <= 0;
                busy_reg <= 1;
            end
        end
    end
end

endmodule
