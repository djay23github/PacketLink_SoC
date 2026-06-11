module reset_sync (
    input  wire clk,
    input  wire async_rst_n,
    output wire sync_rst_n
);

    reg rst_ff1;
    reg rst_ff2;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            rst_ff1 <= 1'b0;
            rst_ff2 <= 1'b0;
        end else begin
            rst_ff1 <= 1'b1;
            rst_ff2 <= rst_ff1;
        end
    end

    assign sync_rst_n = rst_ff2;

endmodule
