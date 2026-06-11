module serdes_top(
    input   wire    clk,
    input   wire    rst_n,

    input   wire    [7:0] parallel_data_in,
    input   wire    tx_valid,
    output  reg    [7:0] parallel_data_out,

    output  wire    tx_serial,
    input   wire    rx_serial,

    output wire tx_done,
    output reg rx_valid

);

    localparam [2:0] STATE_IDLE    = 3'd0;
    localparam [2:0] STATE_ENCODE  = 3'd1;
    localparam [2:0] STATE_LOAD    = 3'd2;
    localparam [2:0] STATE_SHIFT   = 3'd3;
    localparam [2:0] STATE_DECODE  = 3'd4;
    localparam [2:0] STATE_OUTPUT  = 3'd5;

    reg [2:0] state;
    reg [3:0] shift_count;

    wire       capture_en, enc_en, load_en, shift_en, dec_en;

    wire [7:0] buffered_data, decoded_data;
    wire [9:0] received_data, encoded_data;


    // Control signal generation based on state machine
    assign capture_en = (state == STATE_IDLE) && tx_valid;
    assign enc_en     = (state == STATE_ENCODE);
    assign load_en    = (state == STATE_LOAD);
    assign shift_en   = (state == STATE_SHIFT);
    assign dec_en     = (state == STATE_DECODE);
    assign tx_done    = (state == STATE_IDLE);

    serdes_8bit_buffer data_buffer(
        .clk(clk),
        .rst_n(rst_n),
        .data_8b_in(parallel_data_in),
        .capture_en(capture_en),
        .data_8b_out(buffered_data)
    );

    encoder_8b_10b encode_data(
        .clk(clk),
        .rst_n(rst_n),
        .enc_en(enc_en),
        .data_8b_in(buffered_data),
        .data_10b_out(encoded_data)
    );

    piso_10bit par_to_ser(
        .clk(clk),
        .rst_n(rst_n),
        .par_in(encoded_data),
        .load_en(load_en),
        .shift_en(shift_en),
        .ser_out(tx_serial)
    );

    sipo_10bit ser_to_par(
        .clk(clk),
        .rst_n(rst_n),
        .ser_in(rx_serial),
        .shift_en(shift_en),
        .par_out(received_data)
    );

    decoder_10b_8b decode_data(
        .clk(clk),
        .rst_n(rst_n),
        .dec_en(dec_en),
        .data_10b_in(received_data),
        .data_8b_out(decoded_data)
    );

    // State machine to control the SerDes pipeline
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            shift_count <= 4'd0;
            parallel_data_out <= 8'h00;
            rx_valid <= 1'b0;
        end
        else begin
            rx_valid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    shift_count <= 4'd0;
                    if (tx_valid) begin
                        state <= STATE_ENCODE;
                    end
                end

                STATE_ENCODE: begin
                    state <= STATE_LOAD;
                end

                STATE_LOAD: begin
                    state <= STATE_SHIFT;
                    shift_count <= 4'd0;
                end

                STATE_SHIFT: begin
                    if (shift_count == 4'd9) begin
                        state <= STATE_DECODE;
                    end
                    shift_count <= shift_count + 4'd1;
                end

                STATE_DECODE: begin
                    state <= STATE_OUTPUT;
                end

                STATE_OUTPUT: begin
                    parallel_data_out <= decoded_data;
                    rx_valid <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: begin
                    state <= STATE_IDLE;
                    shift_count <= 4'd0;
                    parallel_data_out <= 8'h00;
                end
            endcase
        end
    end


endmodule

