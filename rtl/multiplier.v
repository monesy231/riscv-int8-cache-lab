`timescale 1ns / 1ps

module multiplier (
    input  wire        clk,
    input  wire        rst,     // high active
    input  wire [31:0] x,       // multiplicand
    input  wire [31:0] y,       // multiplier
    input  wire        start,   // 1 - multiplication should begin
    output reg  [63:0] z,       // product
    output wire        busy     // 1 - performing multiplication; 0 - multiplication ends
);

    reg busy_r;
    assign busy = busy_r;

    reg signed [32:0] a;        // 部分积，多 1 位
    reg signed [32:0] m;        // 被乘数符号扩展
    reg [31:0]        q;        // 乘数寄存器
    reg               q_1;      // Booth 附加位
    reg [5:0]         count;    // 计数 0~31

    reg signed [32:0] a_calc;
    reg signed [32:0] a_shift;
    reg [31:0]        q_shift;
    reg               q_1_shift;

    // Booth 单步组合逻辑
    always @(*) begin
        a_calc = a;

        case ({q[0], q_1})
            2'b01: a_calc = a + m;   // +x
            2'b10: a_calc = a - m;   // -x
            default: a_calc = a;     // 不操作
        endcase

        // 对 {A, Q, Q-1} 算术右移一位
        a_shift   = {a_calc[32], a_calc[32:1]};
        q_shift   = {a_calc[0], q[31:1]};
        q_1_shift = q[0];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a      <= 33'd0;
            m      <= 33'd0;
            q      <= 32'd0;
            q_1    <= 1'b0;
            count  <= 6'd0;
            z      <= 64'd0;
            busy_r <= 1'b0;
        end else begin
            if (start && !busy_r) begin
                // start、x、y 只有一个周期有效，所以要缓存
                a      <= 33'd0;
                m      <= {x[31], x};
                q      <= y;
                q_1    <= 1'b0;
                count  <= 6'd0;
                busy_r <= 1'b1;
            end else if (busy_r) begin
                a   <= a_shift;
                q   <= q_shift;
                q_1 <= q_1_shift;

                if (count == 6'd31) begin
                    // 第 32 次 Booth 运算完成
                    z      <= {a_shift[31:0], q_shift};
                    busy_r <= 1'b0;
                    count  <= 6'd0;
                end else begin
                    count <= count + 6'd1;
                end
            end
        end
    end

endmodule
