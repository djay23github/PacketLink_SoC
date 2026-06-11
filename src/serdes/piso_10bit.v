module piso_10bit(
    input           clk,
    input           rst_n,
    input [9:0]     par_in,
    input           load_en,
    input           shift_en,
    output          ser_out
);

    reg [9:0] shift_reg;

    assign ser_out = shift_reg[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 10'b0000000000;
        end
        else if (load_en) begin
            shift_reg <= par_in;
        end
        else if (shift_en) begin
            shift_reg <= {1'b0, shift_reg[9:1]};
        end
    end

endmodule
