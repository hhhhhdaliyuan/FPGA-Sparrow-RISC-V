module otsu_binarize (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       in_vsync,
    input  wire       in_hsync,
    input  wire       in_de,
    input  wire [7:0] in_pix,
    output reg        out_vsync,
    output reg        out_hsync,
    output reg        out_de,
    output reg        out_bin,
    output reg        out_frame_valid
);

// FSM States
localparam S_IDLE      = 2'd0;
localparam S_PRE_CALC  = 2'd1;
localparam S_EVALUATE  = 2'd2;
localparam S_CLEAR     = 2'd3;

reg [1:0] state;
reg [8:0] bin_idx;
reg [31:0] hist [0:255];
reg [7:0]  threshold_reg;

reg in_vsync_d;
wire sof_rise;
assign sof_rise = in_vsync & (~in_vsync_d);

reg sof_seen;
reg [31:0] total_count;
reg [39:0] sum_all;
reg [31:0] w_b;
reg [39:0] sum_b;
reg [127:0] max_score;
reg [7:0] new_threshold;

integer i;

// Combinational temporaries for evaluation phase
wire [31:0] w_b_temp;
wire [39:0] sum_b_temp;
wire [63:0] delta_a;
wire [63:0] delta_b;
wire [63:0] delta_abs;
wire [127:0] score_val;

assign w_b_temp   = w_b + hist[bin_idx];
assign sum_b_temp = sum_b + (bin_idx[7:0] * hist[bin_idx]);
assign delta_a    = sum_b_temp[39:8] * total_count;
assign delta_b    = sum_all[39:8] * w_b_temp;
assign delta_abs  = (delta_a >= delta_b) ? (delta_a - delta_b) : (delta_b - delta_a);
assign score_val  = delta_abs * delta_abs;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_vsync_d   <= 1'b0;
        threshold_reg <= 8'd64;
        sof_seen      <= 1'b0;
        out_frame_valid <= 1'b0;
        out_vsync    <= 1'b0;
        out_hsync    <= 1'b0;
        out_de       <= 1'b0;
        out_bin      <= 1'b0;
        state        <= S_IDLE;
        bin_idx      <= 9'd0;
        total_count  <= 32'd0;
        sum_all      <= 40'd0;
        w_b          <= 32'd0;
        sum_b        <= 40'd0;
        max_score    <= 128'd0;
        new_threshold <= 8'd64;

        for (i = 0; i < 256; i = i + 1) begin
            hist[i] <= 32'd0;
        end
    end else begin
        in_vsync_d <= in_vsync;

        if (in_de) begin
            hist[in_pix] <= hist[in_pix] + 32'd1;
        end

        if (sof_rise) begin
            if (!sof_seen) begin
                sof_seen <= 1'b1;
            end else begin
                out_frame_valid <= 1'b1;
            end
            
            state <= S_PRE_CALC;
            bin_idx <= 9'd0;
            total_count <= 32'd0;
            sum_all <= 40'd0;
            w_b <= 32'd0;
            sum_b <= 40'd0;
            max_score <= 128'd0;
            new_threshold <= threshold_reg;
        end else begin
            // FSM state machine
            case (state)
                S_IDLE: begin
                    // Wait for sof_rise
                end
                
                S_PRE_CALC: begin
                    // Phase 1: Calculate total_count and sum_all
                    if (bin_idx < 256) begin
                        total_count <= total_count + hist[bin_idx];
                        sum_all <= sum_all + (bin_idx[7:0] * hist[bin_idx]);
                        bin_idx <= bin_idx + 9'd1;
                    end else begin
                        state <= S_EVALUATE;
                        bin_idx <= 9'd0;
                        w_b <= 32'd0;
                        sum_b <= 40'd0;
                        max_score <= 128'd0;
                    end
                end
                
                S_EVALUATE: begin
                    // Phase 2: Evaluate threshold candidates with no-divider score
                    if (bin_idx < 256) begin
                        if ((w_b_temp != 32'd0) && (w_b_temp < total_count)) begin
                            if (score_val > max_score) begin
                                max_score <= score_val;
                                new_threshold <= bin_idx[7:0];
                            end
                        end
                        
                        w_b <= w_b_temp;
                        sum_b <= sum_b_temp;
                        bin_idx <= bin_idx + 9'd1;
                    end else begin
                        state <= S_CLEAR;
                        bin_idx <= 9'd0;
                        threshold_reg <= new_threshold;
                    end
                end
                
                S_CLEAR: begin
                    // Phase 3: Clear histogram for next frame
                    if (bin_idx < 256) begin
                        hist[bin_idx] <= 32'd0;
                        bin_idx <= bin_idx + 9'd1;
                    end else begin
                        state <= S_IDLE;
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end

        out_vsync <= in_vsync;
        out_hsync <= in_hsync;
        out_de    <= in_de & out_frame_valid;
        out_bin   <= (in_de & out_frame_valid) ? (in_pix >= threshold_reg) : 1'b0;
    end
end

endmodule
