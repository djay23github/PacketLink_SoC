module encoder_8b_10b(
    input           clk,
    input           rst_n,
    input           enc_en,
    input  [7:0]    data_8b_in,
    output reg [9:0] data_10b_out
);

    reg [3:0] reg_4b;
    reg [5:0] reg_6b;

    always @(*) begin
        case (data_8b_in[7:5])
            3'b000: reg_4b = 4'b0100;
            3'b001: reg_4b = 4'b1001;
            3'b010: reg_4b = 4'b0101;
            3'b011: reg_4b = 4'b0011;
            3'b100: reg_4b = 4'b0010;
            3'b101: reg_4b = 4'b1010;
            3'b110: reg_4b = 4'b0110;
            3'b111: reg_4b = 4'b0001;
            default: reg_4b = 4'b0000;
        endcase

        case (data_8b_in[4:0])
            5'b00000: reg_6b = 6'b011000;
            5'b00001: reg_6b = 6'b011101;
            5'b00010: reg_6b = 6'b010010;
            5'b00011: reg_6b = 6'b110001;
            5'b00100: reg_6b = 6'b110101;
            5'b00101: reg_6b = 6'b101001;
            5'b00110: reg_6b = 6'b011001;
            5'b00111: reg_6b = 6'b111000;
            5'b01000: reg_6b = 6'b111001;
            5'b01001: reg_6b = 6'b100101;
            5'b01010: reg_6b = 6'b010101;
            5'b01011: reg_6b = 6'b110100;
            5'b01100: reg_6b = 6'b001101;
            5'b01101: reg_6b = 6'b101100;
            5'b01110: reg_6b = 6'b011100;
            5'b01111: reg_6b = 6'b010111;
            5'b10000: reg_6b = 6'b011011;
            5'b10001: reg_6b = 6'b100011;
            5'b10010: reg_6b = 6'b010011;
            5'b10011: reg_6b = 6'b110010;
            5'b10100: reg_6b = 6'b001011;
            5'b10101: reg_6b = 6'b101010;
            5'b10110: reg_6b = 6'b011010;
            5'b10111: reg_6b = 6'b111010;
            5'b11000: reg_6b = 6'b110011;
            5'b11001: reg_6b = 6'b100110;
            5'b11010: reg_6b = 6'b010110;
            5'b11011: reg_6b = 6'b110110;
            5'b11100: reg_6b = 6'b001110;
            5'b11101: reg_6b = 6'b101110;
            5'b11110: reg_6b = 6'b011110;
            5'b11111: reg_6b = 6'b101011;
            default: reg_6b = 6'b000000;
        endcase

    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_10b_out <= 10'b0000000000;
        end
        else if (enc_en) begin
            data_10b_out <= {reg_4b, reg_6b};
        end
    end

endmodule
