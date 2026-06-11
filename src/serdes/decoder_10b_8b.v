module decoder_10b_8b(
    input           clk,
    input           rst_n,
    input           dec_en,
    input  [9:0]    data_10b_in,
    output reg [7:0] data_8b_out
);

    reg [2:0] reg_3b;
    reg [4:0] reg_5b;

    always @(*) begin
        case (data_10b_in[9:6])
            4'b0100: reg_3b = 3'b000;
            4'b1001: reg_3b = 3'b001;
            4'b0101: reg_3b = 3'b010;
            4'b0011: reg_3b = 3'b011;
            4'b0010: reg_3b = 3'b100;
            4'b1010: reg_3b = 3'b101;
            4'b0110: reg_3b = 3'b110;
            4'b0001: reg_3b = 3'b111;
            default: reg_3b = 3'b000;
        endcase

        case (data_10b_in[5:0])
            6'b011000: reg_5b = 5'b00000;
            6'b011101: reg_5b = 5'b00001;
            6'b010010: reg_5b = 5'b00010;
            6'b110001: reg_5b = 5'b00011;
            6'b110101: reg_5b = 5'b00100;
            6'b101001: reg_5b = 5'b00101;
            6'b011001: reg_5b = 5'b00110;
            6'b111000: reg_5b = 5'b00111;
            6'b111001: reg_5b = 5'b01000;
            6'b100101: reg_5b = 5'b01001;
            6'b010101: reg_5b = 5'b01010;
            6'b110100: reg_5b = 5'b01011;
            6'b001101: reg_5b = 5'b01100;
            6'b101100: reg_5b = 5'b01101;
            6'b011100: reg_5b = 5'b01110;
            6'b010111: reg_5b = 5'b01111;
            6'b011011: reg_5b = 5'b10000;
            6'b100011: reg_5b = 5'b10001;
            6'b010011: reg_5b = 5'b10010;
            6'b110010: reg_5b = 5'b10011;
            6'b001011: reg_5b = 5'b10100;
            6'b101010: reg_5b = 5'b10101;
            6'b011010: reg_5b = 5'b10110;
            6'b111010: reg_5b = 5'b10111;
            6'b110011: reg_5b = 5'b11000;
            6'b100110: reg_5b = 5'b11001;
            6'b010110: reg_5b = 5'b11010;
            6'b110110: reg_5b = 5'b11011;
            6'b001110: reg_5b = 5'b11100;
            6'b101110: reg_5b = 5'b11101;
            6'b011110: reg_5b = 5'b11110;
            6'b101011: reg_5b = 5'b11111;
            default: reg_5b = 5'b00000;
        endcase

    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_8b_out <= 8'h00;
        end
        else if (dec_en) begin
            data_8b_out <= {reg_3b, reg_5b};
        end
    end

endmodule
