module serdes_8bit_buffer(
    input            clk,
    input            rst_n,
    input  [7:0]     data_8b_in,
    input            capture_en,
    output reg [7:0] data_8b_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_8b_out <= 8'h00;
        end
        else if (capture_en) begin
            data_8b_out <= data_8b_in;
        end
    end

endmodule
