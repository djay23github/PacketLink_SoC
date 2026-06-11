module packet_framer #(
    parameter PAYLOAD_LENGTH = 4
)(
    input  wire       clk,
    input  wire       rst_n,

    //--------------------------------------------------
    // Registered-read FIFO Interface
    //--------------------------------------------------

    input  wire [7:0] fifo_dout,
    input  wire       fifo_empty,

    output wire        fifo_rd_en,

    //--------------------------------------------------
    // SERDES Stream Interface
    //--------------------------------------------------

    output reg [7:0]  serdes_data,
    output reg        serdes_valid,

    input  wire       serdes_ready
);

    //--------------------------------------------------
    // Local Parameters
    //--------------------------------------------------

    localparam IDLE            = 3'd0;
    localparam SEND_SOP        = 3'd1;
    localparam SEND_LEN        = 3'd2;
    localparam READ_PAYLOAD    = 3'd3;
    localparam CAPTURE_PAYLOAD = 3'd4;
    localparam SEND_PAYLOAD    = 3'd5;
    localparam SEND_CRC        = 3'd6;

    localparam SOP_BYTE        = 8'hBC;

    //--------------------------------------------------
    // Registers
    //--------------------------------------------------

    reg [2:0] state;
    reg [7:0] payload_count;
    reg [7:0] payload_byte;
    reg [7:0] crc_reg;

    wire [7:0] crc_in;
    wire [7:0] crc_next;

    //--------------------------------------------------
    // CRC over LEN + PAYLOAD. SOP is not included.
    //--------------------------------------------------

    assign crc_in = (state == SEND_LEN)     ? PAYLOAD_LENGTH[7:0] :
                    (state == SEND_PAYLOAD) ? payload_byte        :
                                               8'h00;

    crc8 u_crc (
        .data_in (crc_in),
        .crc_in  (crc_reg),
        .crc_out (crc_next)
    );

    //--------------------------------------------------
    // SERDES stream outputs
    //
    // The current state presents stable data. The FSM
    // advances only when SERDES accepts that data.
    //--------------------------------------------------

    always @(*) begin
        serdes_data  = 8'h00;
        serdes_valid = 1'b0;

        case (state)
            SEND_SOP: begin
                serdes_data  = SOP_BYTE;
                serdes_valid = 1'b1;
            end

            SEND_LEN: begin
                serdes_data  = PAYLOAD_LENGTH[7:0];
                serdes_valid = 1'b1;
            end

            SEND_PAYLOAD: begin
                serdes_data  = payload_byte;
                serdes_valid = 1'b1;
            end

            SEND_CRC: begin
                serdes_data  = crc_reg;
                serdes_valid = 1'b1;
            end

            default: begin
                serdes_data  = 8'h00;
                serdes_valid = 1'b0;
            end
        endcase
    end

    //--------------------------------------------------
    // FSM
    //--------------------------------------------------

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            payload_count <= 8'd0;
            payload_byte  <= 8'd0;
            crc_reg       <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    payload_count <= 8'd0;
                    crc_reg       <= 8'd0;

                    if (!fifo_empty)
                        state <= SEND_SOP;
                end

                SEND_SOP: begin
                    if (serdes_ready) begin
                        state        <= SEND_LEN;
                    end
                end

                SEND_LEN: begin
                    if (serdes_ready) begin
                        crc_reg      <= crc_next;
                        state        <= READ_PAYLOAD;
                    end
                end

                // Assert rd_en for one cycle. The FIFO used in this project has
                // registered read data, so fifo_dout becomes valid after this cycle.
                READ_PAYLOAD: begin
                    if (!fifo_empty) begin
                        state      <= CAPTURE_PAYLOAD;
                    end
                end

                // Capture the byte that was requested from the FIFO.
                CAPTURE_PAYLOAD: begin
                    payload_byte <= fifo_dout;
                    state        <= SEND_PAYLOAD;
                end

                SEND_PAYLOAD: begin
                    if (serdes_ready) begin
                        crc_reg       <= crc_next;
                        payload_count <= payload_count + 1'b1;

                        if (payload_count == (PAYLOAD_LENGTH - 1))
                            state <= SEND_CRC;
                        else
                            state <= READ_PAYLOAD;
                    end
                end

                SEND_CRC: begin
                    if (serdes_ready) begin
                        state        <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    assign fifo_rd_en = (state == READ_PAYLOAD) && !fifo_empty;

endmodule
