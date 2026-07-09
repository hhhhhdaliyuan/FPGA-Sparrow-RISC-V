`timescale 1ns/1ps

module cnn_accel_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [14:0] addr_i,
    input  wire [31:0] data_i,
    input  wire [ 3:0] sel_i,
    input  wire        we_i,
    input  wire        rd_i,
    output reg  [31:0] data_o
);

    //=========================================================
    // 1. 地址映射与双口 RAM (PORT A)
    //=========================================================
    wire is_reg     = (addr_i <  15'h1000);
    wire is_in_ram  = (addr_i >= 15'h1000 && addr_i < 15'h2800);
    wire is_out_ram = (addr_i >= 15'h2800 && addr_i < 15'h4000);
    wire is_wt_ram  = (addr_i >= 15'h4000 && addr_i < 15'h4C00);

    wire [10:0] ram_in_addr  = addr_i[12:2] - 11'h400; 
    wire [10:0] ram_out_addr = addr_i[12:2] - 11'hA00; 
    wire [9:0]  ram_wt_addr  = addr_i[11:2];           

    reg [31:0] ram_input  [0:1535]; 
    reg [31:0] ram_output [0:1535]; 
    reg [31:0] ram_weight [0:767];  

    always @(posedge clk) begin
        if (we_i) begin
            if (is_in_ram)  ram_input[ram_in_addr]   <= data_i;
            if (is_wt_ram)  ram_weight[ram_wt_addr]  <= data_i;
        end
    end

    reg [31:0] ram_in_rdata, ram_out_rdata, ram_wt_rdata, reg_rdata;
    reg r_is_reg, r_is_in, r_is_out, r_is_wt;
    reg [31:0] reg_ctrl, reg_status, reg_tile_cfg;

    always @(posedge clk) begin
        if (rd_i) begin
            ram_in_rdata  <= ram_input[ram_in_addr];
            ram_out_rdata <= ram_output[ram_out_addr];
            ram_wt_rdata  <= ram_weight[ram_wt_addr];
            case (addr_i[11:0])
                12'h000: reg_rdata <= reg_ctrl;
                12'h004: reg_rdata <= reg_status;
                12'h008: reg_rdata <= reg_tile_cfg;
                default: reg_rdata <= 32'h0;
            endcase
            r_is_reg <= is_reg; r_is_in <= is_in_ram; r_is_out <= is_out_ram; r_is_wt <= is_wt_ram;
        end
    end

    always @(*) begin
        if      (r_is_reg) data_o = reg_rdata;
        else if (r_is_in)  data_o = ram_in_rdata;
        else if (r_is_out) data_o = ram_out_rdata;
        else if (r_is_wt)  data_o = ram_wt_rdata;
        else               data_o = 32'h0; 
    end

    //=========================================================
    // 2. 硬件 FSM 高速读写 (PORT B)
    //=========================================================
    reg [10:0] fsm_in_addr;
    reg [31:0] fsm_in_rdata;
    always @(posedge clk) fsm_in_rdata <= ram_input[fsm_in_addr];

    reg [9:0]  fsm_wt_addr;
    reg [31:0] fsm_wt_rdata;
    always @(posedge clk) fsm_wt_rdata <= ram_weight[fsm_wt_addr];

    reg [10:0] fsm_out_addr;
    reg [31:0] fsm_out_wdata;
    reg        fsm_out_we;
    always @(posedge clk) begin
        if (fsm_out_we) ram_output[fsm_out_addr] <= fsm_out_wdata;
    end

    //=========================================================
    // 3. 【绝对核心】总线直驱脉冲生成
    // 拦截软核向 0x0000 写 1 的动作，产生一个极其纯粹的物理脉冲
    //=========================================================
    wire start_trigger = (we_i && is_reg && (addr_i[11:0] == 12'h000) && data_i[0]);

    // 寄存器保持简单，只存不控
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl     <= 32'b0;
            reg_tile_cfg <= 32'b0;
        end else if (we_i && is_reg) begin
            if (addr_i[11:0] == 12'h000) reg_ctrl     <= data_i;
            if (addr_i[11:0] == 12'h008) reg_tile_cfg <= data_i;
        end 
    end

    //=========================================================
    // 4. FSM 调度器与数据通路 (绝对单向依赖)
    //=========================================================
    localparam S_IDLE     = 3'd0;
    localparam S_LOAD_WT  = 3'd1;
    localparam S_LOAD_PIX = 3'd2;
    localparam S_WAIT_MAC = 3'd3;
    localparam S_STORE    = 3'd4;
    localparam S_DONE     = 3'd5;

    reg [2:0]  state;
    reg [3:0]  step;
    reg [15:0] out_x, out_y;

    wire [15:0] tile_w = reg_tile_cfg[15:0];
    wire [15:0] tile_h = reg_tile_cfg[31:16];

    // 更新状态寄存器 (监控专用)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_status <= 32'b0;
        end else begin
            if (start_trigger) 
                reg_status[0] <= 1'b0;  // 脉冲来时清零 Done
            else if (state == S_DONE) 
                reg_status[0] <= 1'b1;  // 算完时置位 Done
                
            reg_status[1] <= (state != S_IDLE); 
            reg_status[27:24] <= state;      
            reg_status[23:16] <= out_x[7:0]; 
            reg_status[15:8]  <= out_y[7:0]; 
            reg_status[7:4]   <= step;       
        end
    end

    reg [1:0] dx, dy;
    always @(*) begin
        case(step)
            0: begin dx=0; dy=0; end
            1: begin dx=1; dy=0; end
            2: begin dx=2; dy=0; end
            3: begin dx=0; dy=1; end
            4: begin dx=1; dy=1; end
            5: begin dx=2; dy=1; end
            6: begin dx=0; dy=2; end
            7: begin dx=1; dy=2; end
            8: begin dx=2; dy=2; end
            default: begin dx=0; dy=0; end
        endcase
    end

    always @(*) begin
        fsm_wt_addr = step; 
        fsm_in_addr = (out_y + dy) * tile_w + (out_x + dx);
    end

    reg [7:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;
    reg [7:0] w0, w1, w2, w3, w4, w5, w6, w7, w8;
    
    reg mac_en;
    wire mac_valid;
    wire signed [31:0] mac_out;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            step <= 0; out_x <= 0; out_y <= 0;
            fsm_out_we <= 1'b0; mac_en <= 1'b0;
            p0<=0; p1<=0; p2<=0; p3<=0; p4<=0; p5<=0; p6<=0; p7<=0; p8<=0;
            w0<=0; w1<=0; w2<=0; w3<=0; w4<=0; w5<=0; w6<=0; w7<=0; w8<=0;
        end else begin
            fsm_out_we <= 1'b0; 
            
            case (state)
                S_IDLE: begin
                    // 【关键点】强制受总线物理脉冲唤醒，不再依赖寄存器循环判断
                    if (start_trigger) begin 
                        state <= S_LOAD_WT;
                        step <= 0; out_x <= 0; out_y <= 0;
                    end
                end
                S_LOAD_WT: begin
                    step <= step + 1;
                    case (step)
                        1: w0 <= fsm_wt_rdata[7:0];
                        2: w1 <= fsm_wt_rdata[7:0];
                        3: w2 <= fsm_wt_rdata[7:0];
                        4: w3 <= fsm_wt_rdata[7:0];
                        5: w4 <= fsm_wt_rdata[7:0];
                        6: w5 <= fsm_wt_rdata[7:0];
                        7: w6 <= fsm_wt_rdata[7:0];
                        8: w7 <= fsm_wt_rdata[7:0];
                        9: begin
                            w8 <= fsm_wt_rdata[7:0];
                            state <= S_LOAD_PIX;
                            step <= 0;
                        end
                    endcase
                end
                S_LOAD_PIX: begin
                    step <= step + 1;
                    case (step)
                        1: p0 <= fsm_in_rdata[7:0];
                        2: p1 <= fsm_in_rdata[7:0];
                        3: p2 <= fsm_in_rdata[7:0];
                        4: p3 <= fsm_in_rdata[7:0];
                        5: p4 <= fsm_in_rdata[7:0];
                        6: p5 <= fsm_in_rdata[7:0];
                        7: p6 <= fsm_in_rdata[7:0];
                        8: p7 <= fsm_in_rdata[7:0];
                        9: begin
                            p8 <= fsm_in_rdata[7:0];
                            state <= S_WAIT_MAC;
                            mac_en <= 1'b1; 
                            step <= 0;
                        end
                    endcase
                end
                S_WAIT_MAC: begin
                    mac_en <= 1'b0;
                    if (mac_valid) begin 
                        fsm_out_we <= 1'b1; 
                        fsm_out_wdata <= mac_out;
                        fsm_out_addr  <= out_y * (tile_w - 2) + out_x;
                        state <= S_STORE;
                    end
                end
                S_STORE: begin
                    if (out_x == tile_w - 3) begin
                        out_x <= 0;
                        if (out_y == tile_h - 3) state <= S_DONE;
                        else begin out_y <= out_y + 1; state <= S_LOAD_PIX; end
                    end else begin
                        out_x <= out_x + 1;
                        state <= S_LOAD_PIX;
                    end
                end
                S_DONE: begin
                    state <= S_IDLE; 
                end
            endcase
        end
    end

    //=========================================================
    // 5. 实例化 MAC
    //=========================================================
    cnn_mac_3x3 u_mac (
        .clk      (clk),
        .rst_n    (rst_n),
        .en       (mac_en),
        .p0(p0), .p1(p1), .p2(p2),
        .p3(p3), .p4(p4), .p5(p5),
        .p6(p6), .p7(p7), .p8(p8),
        .w0(w0), .w1(w1), .w2(w2),
        .w3(w3), .w4(w4), .w5(w5),
        .w6(w6), .w7(w7), .w8(w8),
        .bias     (32'd0), 
        .en_relu  (reg_ctrl[2]),
        .mac_out  (mac_out),
        .mac_valid(mac_valid)
    );

endmodule