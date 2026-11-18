`timescale 1ns / 1ps

module mac (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] x,
    input  wire [31:0] y,
    input  wire        start,
    output wire [31:0] z,
    output wire        busy
);

    reg        busy_r;
    reg [31:0] z_r;

    assign busy = busy_r;
    assign z    = z_r;

    wire mul_start;
    assign mul_start = start && !busy_r;

    // x/y 中的 4 组 8 位有符号数，符号扩展为 32 位
    wire [31:0] x0 = {{24{x[7]}},   x[7:0]};
    wire [31:0] x1 = {{24{x[15]}},  x[15:8]};
    wire [31:0] x2 = {{24{x[23]}},  x[23:16]};
    wire [31:0] x3 = {{24{x[31]}},  x[31:24]};

    wire [31:0] y0 = {{24{y[7]}},   y[7:0]};
    wire [31:0] y1 = {{24{y[15]}},  y[15:8]};
    wire [31:0] y2 = {{24{y[23]}},  y[23:16]};
    wire [31:0] y3 = {{24{y[31]}},  y[31:24]};

    wire [63:0] p0;
    wire [63:0] p1;
    wire [63:0] p2;
    wire [63:0] p3;

    wire busy0;
    wire busy1;
    wire busy2;
    wire busy3;

    multiplier U_mul0 (
        .clk   (clk),
        .rst   (rst),
        .x     (x0),
        .y     (y0),
        .start (mul_start),
        .z     (p0),
        .busy  (busy0)
    );

    multiplier U_mul1 (
        .clk   (clk),
        .rst   (rst),
        .x     (x1),
        .y     (y1),
        .start (mul_start),
        .z     (p1),
        .busy  (busy1)
    );

    multiplier U_mul2 (
        .clk   (clk),
        .rst   (rst),
        .x     (x2),
        .y     (y2),
        .start (mul_start),
        .z     (p2),
        .busy  (busy2)
    );

    multiplier U_mul3 (
        .clk   (clk),
        .rst   (rst),
        .x     (x3),
        .y     (y3),
        .start (mul_start),
        .z     (p3),
        .busy  (busy3)
    );

    wire signed [31:0] p0_32;
    wire signed [31:0] p1_32;
    wire signed [31:0] p2_32;
    wire signed [31:0] p3_32;

    assign p0_32 = p0[31:0];
    assign p1_32 = p1[31:0];
    assign p2_32 = p2[31:0];
    assign p3_32 = p3[31:0];

    wire signed [31:0] mac_sum;
    assign mac_sum = p0_32 + p1_32 + p2_32 + p3_32;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_r <= 1'b0;
            z_r    <= 32'd0;
        end else begin
            if (start && !busy_r) begin
                busy_r <= 1'b1;
            end else if (busy_r && !busy0 && !busy1 && !busy2 && !busy3) begin
                z_r    <= mac_sum;
                busy_r <= 1'b0;
            end
        end
    end

endmodule
