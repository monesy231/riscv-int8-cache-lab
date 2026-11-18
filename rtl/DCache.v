`timescale 1ns / 1ps

module DCache(
    input  wire         cpu_clk,
    input  wire         cpu_rst,
    input  wire [ 3:0]  data_ren,       // 来自CPU的读使能信号
    input  wire [31:0]  data_addr,      // 来自CPU的地址
    output reg          data_valid,     // 输出给CPU的数据有效信号
    output reg  [31:0]  data_rdata,     // 输出给CPU的读数据
    input  wire [ 3:0]  data_wen,       // 来自CPU的写使能信号
    input  wire [31:0]  data_wdata,     // 来自CPU的写数据
    output reg          data_wresp,     // 输出给CPU的写响应
    input  wire         dev_wrdy,       // 主存/外设写就绪
    output reg  [ 3:0]  cpu_wen,        // 输出给主存/外设的写使能
    output reg  [31:0]  cpu_waddr,      // 输出给主存/外设的写地址
    output reg  [31:0]  cpu_wdata,      // 输出给主存/外设的写数据
    input  wire         dev_rrdy,       // 主存/外设读就绪
    output reg  [ 3:0]  cpu_ren,        // 输出给主存/外设的读使能
    output reg  [31:0]  cpu_raddr,      // 输出给主存/外设的读地址
    input  wire         dev_rvalid,     // 主存/外设读数据有效
    input  wire [127:0] dev_rdata       // 主存返回128bit；外设访问时低32bit有效
);

    wire uncached = (data_addr[31:16] == 16'hFFFF) &&
                    ((data_ren != 4'h0) || (data_wen != 4'h0));

    ///////////////////////////////////////////////////////////
    // 读状态机

    localparam R_IDLE       = 2'b00;
    localparam R_LOOKUP     = 2'b01;
    localparam R_WAIT_RRDY  = 2'b10;
    localparam R_WAIT_RDATA = 2'b11;

    reg [1:0]  r_state, r_nstat;
    reg [31:0] r_req_addr;
    reg [ 3:0] r_req_ren;
    reg        r_req_uncached;

    // 防止CPU的data_ren保持高电平时，同一个读请求被重复接收
    reg        r_done_hold;
    reg [31:0] r_done_addr;

    wire read_req_blocked =
        r_done_hold &&
        (data_ren != 4'h0) &&
        (data_addr == r_done_addr);

    wire new_read_req =
        (data_ren != 4'h0) &&
        !read_req_blocked;

    localparam W_IDLE      = 2'b00;
    localparam W_LOOKUP    = 2'b01;
    localparam W_WAIT_WRDY = 2'b10;
    localparam W_WAIT_RESP = 2'b11;

    reg [1:0]  w_state, w_nstat;
    reg [31:0] w_req_addr;
    reg [ 3:0] w_req_wen;
    reg [31:0] w_req_wdata;
    reg        w_req_uncached;

    wire wr_resp = dev_wrdy & (cpu_wen == 4'h0);

    wire [133:0] cache_line_r;
    wire         valid_bit      = cache_line_r[133];
    wire [4:0]   tag_from_cache = cache_line_r[132:128];
    wire [127:0] cache_data_r   = cache_line_r[127:0];

    wire [4:0] tag_from_cpu_r = r_req_addr[14:10];
    wire [4:0] tag_from_cpu_w = w_req_addr[14:10];

    wire [1:0] r_offset = r_req_addr[3:2];
    wire [1:0] w_offset = w_req_addr[3:2];

    wire hit_r = (r_state == R_LOOKUP) &&
                   (!r_req_uncached) &&
                   valid_bit &&
                   (tag_from_cache == tag_from_cpu_r);

    wire hit_w = (w_state == W_LOOKUP) &&
                   (!w_req_uncached) &&
                   valid_bit &&
                   (tag_from_cache == tag_from_cpu_w);

    reg [31:0] data_from_cache;
    reg [31:0] data_from_mem;

    always @(*) begin
        case (r_offset)
            2'd0: data_from_cache = cache_data_r[ 31:  0];
            2'd1: data_from_cache = cache_data_r[ 63: 32];
            2'd2: data_from_cache = cache_data_r[ 95: 64];
            2'd3: data_from_cache = cache_data_r[127: 96];
            default: data_from_cache = 32'h0;
        endcase
    end

    always @(*) begin
        case (r_offset)
            2'd0: data_from_mem = dev_rdata[ 31:  0];
            2'd1: data_from_mem = dev_rdata[ 63: 32];
            2'd2: data_from_mem = dev_rdata[ 95: 64];
            2'd3: data_from_mem = dev_rdata[127: 96];
            default: data_from_mem = 32'h0;
        endcase
    end

    reg [31:0]  old_word;
    reg [31:0]  new_word;
    reg [127:0] wr_cache_data;

    always @(*) begin
        case (w_offset)
            2'd0: old_word = cache_data_r[ 31:  0];
            2'd1: old_word = cache_data_r[ 63: 32];
            2'd2: old_word = cache_data_r[ 95: 64];
            2'd3: old_word = cache_data_r[127: 96];
            default: old_word = 32'h0;
        endcase

        new_word = old_word;

        if (w_req_wen[0])
            new_word[ 7: 0] = w_req_wdata[ 7: 0];
        if (w_req_wen[1])
            new_word[15: 8] = w_req_wdata[15: 8];
        if (w_req_wen[2])
            new_word[23:16] = w_req_wdata[23:16];
        if (w_req_wen[3])
            new_word[31:24] = w_req_wdata[31:24];

        wr_cache_data = cache_data_r;

        case (w_offset)
            2'd0: wr_cache_data[ 31:  0] = new_word;
            2'd1: wr_cache_data[ 63: 32] = new_word;
            2'd2: wr_cache_data[ 95: 64] = new_word;
            2'd3: wr_cache_data[127: 96] = new_word;
            default: wr_cache_data = cache_data_r;
        endcase
    end

    wire r_refill =
        (r_state == R_WAIT_RDATA) &&
        dev_rvalid &&
        (!r_req_uncached);

    wire w_update_cache =
        (w_state == W_LOOKUP) &&
        hit_w;

    wire cache_we = r_refill || w_update_cache;

    wire [5:0] cache_index =
        r_refill       ? r_req_addr[9:4] :
        w_update_cache ? w_req_addr[9:4] :
        ((r_state == R_IDLE) && new_read_req && !uncached) ? data_addr[9:4] :
        ((w_state == W_IDLE) && (data_wen != 4'h0) && !uncached) ? data_addr[9:4] :
        (r_state != R_IDLE) ? r_req_addr[9:4] :
        (w_state != W_IDLE) ? w_req_addr[9:4] :
        data_addr[9:4];

    wire [133:0] refill_cache_line = {1'b1, r_req_addr[14:10], dev_rdata};
    wire [133:0] write_cache_line  = {1'b1, tag_from_cache, wr_cache_data};

    wire [133:0] cache_line_w =
        r_refill ? refill_cache_line : write_cache_line;

    cache_line_ram U_dsram (
        .clk    (cpu_clk),
        .rst    (cpu_rst),
        .we     (cache_we),
        .index  (cache_index),
        .d      (cache_line_w),
        .q      (cache_line_r)
    );

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst)
            r_state <= R_IDLE;
        else
            r_state <= r_nstat;
    end

    always @(*) begin
        case (r_state)
            R_IDLE: begin
                if (new_read_req) begin
                    if (uncached)
                        r_nstat = dev_rrdy ? R_WAIT_RDATA : R_WAIT_RRDY;
                    else
                        r_nstat = R_LOOKUP;
                end else begin
                    r_nstat = R_IDLE;
                end
            end

            R_LOOKUP: begin
                if (hit_r)
                    r_nstat = R_IDLE;
                else
                    r_nstat = dev_rrdy ? R_WAIT_RDATA : R_WAIT_RRDY;
            end

            R_WAIT_RRDY: begin
                r_nstat = dev_rrdy ? R_WAIT_RDATA : R_WAIT_RRDY;
            end

            R_WAIT_RDATA: begin
                r_nstat = dev_rvalid ? R_IDLE : R_WAIT_RDATA;
            end

            default: begin
                r_nstat = R_IDLE;
            end
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            r_req_addr     <= 32'h0;
            r_req_ren      <= 4'h0;
            r_req_uncached <= 1'b0;

            data_valid <= 1'b0;
            data_rdata <= 32'h0;
            cpu_ren    <= 4'h0;
            cpu_raddr  <= 32'h0;
        end else begin
            data_valid <= 1'b0;
            data_rdata <= 32'h0;
            cpu_ren    <= 4'h0;

            case (r_state)
                R_IDLE: begin
                    if (new_read_req) begin
                        r_req_addr     <= data_addr;
                        r_req_ren      <= data_ren;
                        r_req_uncached <= uncached;

                        if (uncached && dev_rrdy) begin
                            cpu_ren   <= data_ren;
                            cpu_raddr <= data_addr;
                        end
                    end
                end

                R_LOOKUP: begin
                    if (hit_r) begin
                        data_valid <= 1'b1;
                        data_rdata <= data_from_cache;
                    end else begin
                        if (dev_rrdy) begin
                            cpu_ren   <= 4'hF;
                            cpu_raddr <= {r_req_addr[31:4], 4'b0000};
                        end
                    end
                end

                R_WAIT_RRDY: begin
                    if (dev_rrdy) begin
                        if (r_req_uncached) begin
                            cpu_ren   <= r_req_ren;
                            cpu_raddr <= r_req_addr;
                        end else begin
                            cpu_ren   <= 4'hF;
                            cpu_raddr <= {r_req_addr[31:4], 4'b0000};
                        end
                    end
                end

                R_WAIT_RDATA: begin
                    if (dev_rvalid) begin
                        data_valid <= 1'b1;

                        if (r_req_uncached)
                            data_rdata <= dev_rdata[31:0];
                        else
                            data_rdata <= data_from_mem;
                    end
                end

                default: begin
                    data_valid <= 1'b0;
                    data_rdata <= 32'h0;
                    cpu_ren    <= 4'h0;
                end
            endcase
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            r_done_hold <= 1'b0;
            r_done_addr <= 32'h0;
        end else begin
            if ((data_ren == 4'h0) || (data_addr != r_done_addr)) begin
                r_done_hold <= 1'b0;
            end

            if ((r_state == R_LOOKUP) && hit_r) begin
                r_done_hold <= 1'b1;
                r_done_addr <= r_req_addr;
            end

            if ((r_state == R_WAIT_RDATA) && dev_rvalid) begin
                r_done_hold <= 1'b1;
                r_done_addr <= r_req_addr;
            end
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst)
            w_state <= W_IDLE;
        else
            w_state <= w_nstat;
    end

    always @(*) begin
        case (w_state)
            W_IDLE: begin
                if (data_wen != 4'h0)
                    w_nstat = W_LOOKUP;
                else
                    w_nstat = W_IDLE;
            end

            W_LOOKUP: begin
                if (dev_wrdy)
                    w_nstat = W_WAIT_RESP;
                else
                    w_nstat = W_WAIT_WRDY;
            end

            W_WAIT_WRDY: begin
                if (dev_wrdy)
                    w_nstat = W_WAIT_RESP;
                else
                    w_nstat = W_WAIT_WRDY;
            end

            W_WAIT_RESP: begin
                if (wr_resp)
                    w_nstat = W_IDLE;
                else
                    w_nstat = W_WAIT_RESP;
            end

            default: begin
                w_nstat = W_IDLE;
            end
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            w_req_addr     <= 32'h0;
            w_req_wen      <= 4'h0;
            w_req_wdata    <= 32'h0;
            w_req_uncached <= 1'b0;

            cpu_wen    <= 4'h0;
            cpu_waddr  <= 32'h0;
            cpu_wdata  <= 32'h0;
            data_wresp <= 1'b0;
        end else begin
            cpu_wen    <= 4'h0;
            data_wresp <= 1'b0;

            case (w_state)
                W_IDLE: begin
                    if (data_wen != 4'h0) begin
                        w_req_addr     <= data_addr;
                        w_req_wen      <= data_wen;
                        w_req_wdata    <= data_wdata;
                        w_req_uncached <= uncached;
                    end
                end

                W_LOOKUP: begin
                    if (dev_wrdy) begin
                        cpu_wen   <= w_req_wen;
                        cpu_waddr <= w_req_addr;
                        cpu_wdata <= w_req_wdata;
                    end
                end

                W_WAIT_WRDY: begin
                    if (dev_wrdy) begin
                        cpu_wen   <= w_req_wen;
                        cpu_waddr <= w_req_addr;
                        cpu_wdata <= w_req_wdata;
                    end
                end

                W_WAIT_RESP: begin
                    cpu_wen <= 4'h0;

                    if (wr_resp) begin
                        data_wresp <= 1'b1;
                    end
                end

                default: begin
                    cpu_wen    <= 4'h0;
                    data_wresp <= 1'b0;
                end
            endcase
        end
    end

endmodule
