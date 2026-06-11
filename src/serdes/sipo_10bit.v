module sipo_10bit(
    input           clk,
    input           rst_n,
    input           ser_in,
    input           shift_en,
    output [9:0]    par_out
);

    reg [9:0] shift_reg;

    assign par_out = shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 10'b0000000000;
        end
        else if (shift_en) begin
            shift_reg <= {ser_in, shift_reg[9:1]};
        end
    end

endmodule
