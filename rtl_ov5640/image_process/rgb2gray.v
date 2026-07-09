module rgb2gray (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       in_vsync,
    input  wire       in_hsync,
    input  wire       in_de,
    input  wire [7:0] in_r,
    input  wire [7:0] in_g,
    input  wire [7:0] in_b,
    output reg        out_vsync,
    output reg        out_hsync,
    output reg        out_de,
    output reg [7:0]  out_gray
);

reg [15:0] gray_sum;
reg        vsync_d;
reg        hsync_d;
reg        de_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vsync_d   <= 1'b0;
        hsync_d   <= 1'b0;
        de_d      <= 1'b0;
        out_vsync <= 1'b0;
        out_hsync <= 1'b0;
        out_de    <= 1'b0;
        out_gray  <= 8'd0;
        gray_sum  <= 16'd0;
    end else begin
        vsync_d <= in_vsync;
        hsync_d <= in_hsync;
        de_d    <= in_de;

        gray_sum <= (in_r * 8'd77) + (in_g * 8'd150) + (in_b * 8'd29);

        out_vsync <= vsync_d;
        out_hsync <= hsync_d;
        out_de    <= de_d;
        out_gray <= gray_sum[15:8];
    end
end

endmodule
