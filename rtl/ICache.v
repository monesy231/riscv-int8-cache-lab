`timescale 1ns / 1ps

module ICache(
    input  wire         cpu_clk,
    input  wire         cpu_rst,
    input  wire         inst_rreq,      // 来自CPU的取指请求
    input  wire [31:0]  inst_addr,      // 来自CPU的取指地址
    output reg          inst_valid,     // 输出给CPU的指令有效信号（读指令命中）
    output reg  [31:0]  inst_out,       // 输出给CPU的指令
    input  wire         dev_rrdy,       // 主存就绪信号（高电平表示主存可接收ICache的读请求）
    output reg  [ 3:0]  cpu_ren,        // 输出给主存的读使能信号
    output reg  [31:0]  cpu_raddr,      // 输出给主存的读地址
    input  wire         dev_rvalid,     // 来自主存的数据有效信号
    input  wire [127:0] dev_rdata       // 来自主存的读数据
);

    // 定义ICache状态机的状态及状态变量
    localparam IDLE       = 2'b00;
    localparam LOOKUP     = 2'b01;
    localparam WAIT_RRDY  = 2'b10;
    localparam WAIT_RDATA = 2'b11;

    reg [1:0]  state, nstat;
    reg [31:0] req_addr;

    wire [133:0] cache_line_r;

    wire [4:0] tag_from_cpu   = req_addr[14:10];
    wire [1:0] offset         = req_addr[3:2];

    wire       valid_bit      = cache_line_r[133];
    wire [4:0] tag_from_cache = cache_line_r[132:128];

    wire hit = (state == LOOKUP) &&
               valid_bit &&
               (tag_from_cache == tag_from_cpu);

    wire refill = (state == WAIT_RDATA) && dev_rvalid;

    reg [31:0] inst_from_cache;
    reg [31:0] inst_from_mem;

    always @(*) begin
        case (offset)
            2'd0: inst_from_cache = cache_line_r[ 31:  0];
            2'd1: inst_from_cache = cache_line_r[ 63: 32];
            2'd2: inst_from_cache = cache_line_r[ 95: 64];
            2'd3: inst_from_cache = cache_line_r[127: 96];
            default: inst_from_cache = 32'h0;
        endcase
    end

    always @(*) begin
        case (offset)
            2'd0: inst_from_mem = dev_rdata[ 31:  0];
            2'd1: inst_from_mem = dev_rdata[ 63: 32];
            2'd2: inst_from_mem = dev_rdata[ 95: 64];
            2'd3: inst_from_mem = dev_rdata[127: 96];
            default: inst_from_mem = 32'h0;
        endcase
    end

    wire       cache_we     = refill;
    wire [5:0] cache_index  = (state == IDLE) ? inst_addr[9:4] : req_addr[9:4];
    wire [133:0] cache_line_w = {1'b1, req_addr[14:10], dev_rdata};
    cache_line_ram U_isram (
        .clk    (cpu_clk),
        .rst    (cpu_rst),
        .we     (cache_we),
        .index  (cache_index),
        .d      (cache_line_w),
        .q      (cache_line_r)
    );

    // 编写状态机现态的更新逻辑
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst)
            state <= IDLE;
        else
            state <= nstat;
    end

    // 编写状态机的状态转移逻辑
    always @(*) begin
        case (state)
            IDLE: begin
                nstat = inst_rreq ? LOOKUP : IDLE;
            end
            LOOKUP: begin
                if (hit)
                    nstat = IDLE;
                else
                    nstat = dev_rrdy ? WAIT_RDATA : WAIT_RRDY;
            end
            WAIT_RRDY: begin
                nstat = dev_rrdy ? WAIT_RDATA : WAIT_RRDY;
            end
            WAIT_RDATA: begin
                nstat = dev_rvalid ? IDLE : WAIT_RDATA;
            end
            default: begin
                nstat = IDLE;
            end
        endcase
    end

    // 生成状态机的输出信号
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            req_addr   <= 32'h0;
            cpu_ren    <= 4'h0;
            cpu_raddr  <= 32'h0;
            inst_valid <= 1'b0;
            inst_out   <= 32'h0;
        end else begin
            inst_valid <= 1'b0;
            inst_out   <= 32'h0;
            cpu_ren    <= 4'h0;

            case (state)
                IDLE: begin
                    if (inst_rreq) begin
                        req_addr <= inst_addr;
                    end
                end

                LOOKUP: begin
                    if (hit) begin
                        inst_valid <= 1'b1;
                        inst_out   <= inst_from_cache;
                    end else begin
                        cpu_raddr <= {req_addr[31:4], 4'b0000};
                        cpu_ren   <= dev_rrdy ? 4'hF : 4'h0;
                    end
                end

                WAIT_RRDY: begin
                    cpu_raddr <= {req_addr[31:4], 4'b0000};
                    cpu_ren   <= dev_rrdy ? 4'hF : 4'h0;
                end

                WAIT_RDATA: begin
                    if (dev_rvalid) begin
                        inst_valid <= 1'b1;
                        inst_out   <= inst_from_mem;
                    end
                end

                default: begin
                    cpu_ren    <= 4'h0;
                    inst_valid <= 1'b0;
                    inst_out   <= 32'h0;
                end
            endcase
        end
    end

endmodule
