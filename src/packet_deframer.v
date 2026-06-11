/* verilator lint_off WIDTHTRUNC */
module packet_deframer #(
    parameter MAX_PAYLOAD_LENGTH = 16
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] serdes_data,
    input  wire       serdes_valid,

    output reg  [7:0] payload_data,
    output reg        payload_valid,

    output reg        packet_valid,
    output reg        crc_error
);

    localparam SOP_BYTE = 8'hBC;

    localparam WAIT_SOP     = 3'd0;
    localparam READ_LEN     = 3'd1;
    localparam READ_PAYLOAD = 3'd2;
    localparam READ_CRC     = 3'd3;
    localparam EMIT_PAYLOAD = 3'd4;


    reg [2:0] state;

    reg [7:0] length_reg;
    reg [7:0] payload_count;
    reg [7:0] emit_count;

    reg [7:0] crc_reg;
    reg [7:0] payload_mem [0:MAX_PAYLOAD_LENGTH-1];
    integer i;

    wire [7:0] crc_next;

    crc8 u_crc8 (
        .data_in (serdes_data),
        .crc_in  (crc_reg),
        .crc_out (crc_next)
    );

    //--------------------------------------------------
    // Main FSM
    //--------------------------------------------------

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= WAIT_SOP;
            length_reg    <= 8'd0;
            payload_count <= 8'd0;
            emit_count    <= 8'd0;
            crc_reg       <= 8'd0;

            payload_data  <= 8'd0;
            payload_valid <= 1'b0;
            packet_valid  <= 1'b0;
            crc_error     <= 1'b0;

            for (i = 0; i < MAX_PAYLOAD_LENGTH; i = i + 1) begin
                payload_mem[i] <= 8'd0;
            end

        end else begin
            payload_valid <= 1'b0;
            packet_valid  <= 1'b0;
            crc_error     <= 1'b0;
            case (state)

                WAIT_SOP: begin
                    length_reg    <= 8'd0;
                    payload_count <= 8'd0;
                    emit_count    <= 8'd0;
                    crc_reg       <= 8'd0;

                    if (serdes_valid && (serdes_data == SOP_BYTE)) begin
                        state <= READ_LEN;
                    end
                end
                READ_LEN: begin
                    if (serdes_valid) begin
                        length_reg <= serdes_data;
                        emit_count <= 8'd0;
                        crc_reg    <= crc_next;

                        if (serdes_data > MAX_PAYLOAD_LENGTH[7:0]) begin
                            crc_error <= 1'b1;
                            state     <= WAIT_SOP;
                        end else if (serdes_data == 8'd0) begin
                            state <= READ_CRC;
                        end else begin
                            payload_count <= 8'd0;
                            state         <= READ_PAYLOAD;
                        end
                    end
                end
                READ_PAYLOAD: begin
                    if (serdes_valid) begin
                        payload_mem[payload_count] <= serdes_data;
                        crc_reg                    <= crc_next;
                        payload_count              <= payload_count + 1'b1;

                        if (payload_count == (length_reg - 1'b1)) begin
                            state <= READ_CRC;
                        end
                    end
                end
                READ_CRC: begin
                    if (serdes_valid) begin
                        if (serdes_data == crc_reg) begin
                            packet_valid <= 1'b1;

                            if (length_reg == 8'd0) begin
                                state <= WAIT_SOP;
                            end else begin
                                state <= EMIT_PAYLOAD;
                            end
                        end else begin
                            crc_error <= 1'b1;
                            state     <= WAIT_SOP;
                        end
                    end
                end
                EMIT_PAYLOAD: begin
                    payload_data  <= payload_mem[emit_count];
                    payload_valid <= 1'b1;
                    emit_count    <= emit_count + 1'b1;
                    if (emit_count == (length_reg - 1'b1)) begin
                        state <= WAIT_SOP;
                    end
                end
                default: begin
                    state <= WAIT_SOP;
                end
            endcase
        end
    end

endmodule
