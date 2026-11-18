`timescale 1ns / 1ps

module tb_arithmetic;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg mul_start = 1'b0;
    reg [31:0] mul_x = 0, mul_y = 0;
    wire [63:0] product;
    wire mul_busy;

    reg mac_start = 1'b0;
    reg [31:0] packed_x = 0, packed_y = 0;
    wire [31:0] dot;
    wire mac_busy;

    multiplier mul_dut (.clk(clk), .rst(rst), .x(mul_x), .y(mul_y),
                        .start(mul_start), .z(product), .busy(mul_busy));
    mac mac_dut (.clk(clk), .rst(rst), .x(packed_x), .y(packed_y),
                 .start(mac_start), .z(dot), .busy(mac_busy));

    task automatic check_mul(input reg signed [31:0] a, b);
        reg signed [63:0] expected;
        expected = a * b;
        @(negedge clk);
        mul_x = a;
        mul_y = b;
        mul_start = 1'b1;
        @(negedge clk);
        if (mul_busy !== 1'b1)
            $fatal(1, "multiplier did not accept start");
        mul_start = 1'b0;
        mul_x = ~a;
        mul_y = ~b;
        for (integer cycle = 1; cycle <= 32; cycle = cycle + 1) begin
            // A second pulse in the middle of the operation is ignored.
            mul_start = (cycle == 5);
            @(negedge clk);
            if (mul_busy !== (cycle < 32))
                $fatal(1, "multiplier busy changed at the wrong cycle (%0d)", cycle);
        end
        if (product !== expected)
            $fatal(1, "%0d * %0d: expected %0d, got %0d", a, b, expected, $signed(product));
    endtask

    task automatic check_dot(input reg [31:0] a, b, input integer expected);
        @(negedge clk);
        packed_x = a;
        packed_y = b;
        mac_start = 1'b1;
        @(negedge clk);
        if (mac_busy !== 1'b1)
            $fatal(1, "mac did not accept start");
        mac_start = 1'b0;
        for (integer cycle = 1; cycle <= 33; cycle = cycle + 1) begin
            @(negedge clk);
            if (mac_busy !== (cycle < 33))
                $fatal(1, "mac busy changed at the wrong cycle (%0d)", cycle);
        end
        if (dot !== expected)
            $fatal(1, "dot4(%h, %h): expected %0d, got %0d", a, b, expected, $signed(dot));
    endtask

    integer accumulator;
    initial begin
        if ($test$plusargs("waves")) begin
            $dumpfile("tb_arithmetic.vcd");
            $dumpvars(0, tb_arithmetic);
        end
        repeat (2) @(negedge clk);
        rst = 1'b0;
        check_mul(32'sd0, -32'sd2147483647);
        check_mul(-32'sd1234567, 32'sd89123);
        check_mul(-32'sd17, -32'sd71);
        check_mul(32'sh80000000, -32'sd1);
        check_mul(32'sh80000000, 32'sh80000000);
        check_mul(32'sh80000000, 32'sh7fffffff);
        check_mul(32'sh7fffffff, 32'sh7fffffff);

        check_dot(32'h80808080, 32'h80808080, 65536);
        check_dot(32'h80808080, 32'h7f7f7f7f, -65024);

        // The first demo row spans two packed instructions. The caller accumulates.
        check_dot(32'hfc03fe01, 32'h0403ff02, -3);
        accumulator = $signed(dot);
        check_dot(32'hf807fa05, 32'h01fd05fe, -69);
        accumulator = accumulator + $signed(dot);
        if (accumulator != -72)
            $fatal(1, "the two groups must accumulate to -72");

        $display("PASS signed Booth multiplier and packed INT8 dot product");
        $finish(0);
    end

    initial #20000 $fatal(1, "arithmetic test timed out");
endmodule
