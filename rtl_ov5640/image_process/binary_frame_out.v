module binary_frame_out (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       in_vsync,
    input  wire       in_hsync,
    input  wire       in_de,
    input  wire       in_bin,
    input  wire       in_valid,
    output reg        out_vsync,
    output reg        out_hsync,
    output reg        out_de,
    output reg [7:0]  out_pix
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_vsync <= 1'b0;
        out_hsync <= 1'b0;
        out_de    <= 1'b0;
        out_pix   <= 8'd0;
    end else begin
        out_vsync <= in_vsync;
        out_hsync <= in_hsync;
        out_de    <= in_de & in_valid;
        out_pix   <= (in_de & in_valid & in_bin) ? 8'hFF : 8'h00;
    end
end

endmodule
